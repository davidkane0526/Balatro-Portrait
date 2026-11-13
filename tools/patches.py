#!/usr/bin/env python3
"""The game's own code stays out of this repository: the patches hold what the
mod changes, as unified diffs, and src/ is built from them and your copy of the
game. Day to day src/ is edited as ever.

    python tools/patches.py apply           # game + patches -> src/
    python tools/patches.py make            # src/ -> the patches of that game
    python tools/patches.py check           # do the patches still give src/?
    python tools/patches.py lint            # parse the patches, no game needed

There are two sets, one per copy of the game, and both give the same src/:
patches/portrait/ against Steam's and patches/portrait-mobile/ against the
Play Store's. The mobile game is a separate build with its own touch, save and
platform code, which Steamodded's patches and the rootless APK's engine cannot
run, so its set turns it into the code the mod is tested on instead of porting
the mod to it. After editing src/, `make` once with each game.

--game takes Balatro.exe, Balatro.love, the official APK or an extracted
folder. Without it: game_original_files/, $BALATRO_EXE, then the usual Steam
folders. The files of our own in src/ (portrait_*.lua, smali/) are tracked as
they are and never touched here.

A hunk goes where its lines are, nearest to the line it names, so a game
update that only moves code applies as it is; failing that up to FUZZ context
lines on each end may differ, and the report lists those hunks. A hunk that
still finds no place stops the run with src/ as it was: the patch needs
porting by hand. A game version outside TESTED_VERSIONS needs
--allow-untested-game.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "src")
PATCH_DIRS = {"steam": os.path.join(ROOT, "patches", "portrait"),
              "mobile": os.path.join(ROOT, "patches", "portrait-mobile")}
GAME_DIR = os.path.join(ROOT, "game_original_files")
STAMP = os.path.join(SRC_DIR, ".patched.json")

TESTED_VERSIONS = ("1.0.1o",)
# Files only the mobile game has. The code the patches give never loads them.
MOBILE_ONLY = ("engine/load_manager.lua", "engine/platform.lua")
FUZZ = 2
CONTEXT = 3

STEAM_GUESSES = [
    r"C:\Program Files (x86)\Steam\steamapps\common\Balatro\Balatro.exe",
    r"C:\Program Files\Steam\steamapps\common\Balatro\Balatro.exe",
] + [rf"{d}:\SteamLibrary\steamapps\common\Balatro\Balatro.exe" for d in "CDEFG"] \
  + [rf"{d}:\Steam\steamapps\common\Balatro\Balatro.exe" for d in "CDEFG"]


class PatchError(Exception):
    pass


def find_balatro(explicit=None):
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    env = os.environ.get("BALATRO_EXE")
    if env and os.path.isfile(env):
        return env
    for p in STEAM_GUESSES:
        if os.path.isfile(p):
            return p
    return None


def _is_game_file(rel):
    if rel == "version.jkr":
        return True
    return rel.endswith(".lua") and not rel.startswith(("localization/", "resources/"))


def _read_folder(folder):
    files = {}
    for base, _, names in os.walk(folder):
        for name in names:
            path = os.path.join(base, name)
            rel = os.path.relpath(path, folder).replace(os.sep, "/")
            if _is_game_file(rel):
                with open(path, "rb") as f:
                    files[rel] = f.read()
    return files


def read_game(path):
    """The game's code as {relative path: bytes}. The official APK keeps it
    under assets/, with CRLF line ends where Steam's has LF."""
    def lf(data):
        return data.replace(b"\r\n", b"\n")

    if os.path.isdir(path):
        for root in (path, os.path.join(path, "assets")):
            if os.path.isfile(os.path.join(root, "main.lua")):
                return {rel: lf(data) for rel, data in _read_folder(root).items()}
    else:
        try:
            with zipfile.ZipFile(path) as z:
                names = set(z.namelist())
                for prefix in ("", "assets/"):
                    if prefix + "main.lua" in names:
                        return {n[len(prefix):]: lf(z.read(n)) for n in names
                                if n.startswith(prefix) and _is_game_file(n[len(prefix):])}
        except zipfile.BadZipFile:
            raise PatchError(f"{path} is not a Balatro game file.")
    raise PatchError(f"No game code in {path}. Use Balatro.exe or Balatro.love from your Steam copy.")


def game_version(files):
    lines = files.get("version.jkr", b"").decode("utf-8", "replace").split("\n")
    return lines[1].strip() if len(lines) > 1 else "unknown"


def game_target(game):
    return "mobile" if b"PROD_mobile" in game.get("version.jkr", b"") else "steam"


def default_game():
    if os.path.isdir(GAME_DIR):
        return GAME_DIR
    game = find_balatro()
    if not game:
        raise PatchError("Balatro not found. Pass --game PATH or set BALATRO_EXE.")
    return game


def split_lines(data):
    return re.findall(rb"[^\n]*\n|[^\n]+", data)


def parse_patch(data, name="patch"):
    """Unified diff -> hunks, each {'start': old line, 'lines': [(tag, line)]}."""
    hunks = []
    lines = split_lines(data)
    i = 0
    while i < len(lines):
        m = re.match(rb"@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@", lines[i])
        i += 1
        if not m:
            continue
        old_left = int(m.group(2) or 1)
        hunk = {"start": int(m.group(1)), "lines": []}
        empty = True
        while i < len(lines) and not lines[i].startswith(b"@@"):
            line = lines[i]
            i += 1
            tag, text = line[:1], line[1:]
            if tag == b"\\":
                last_tag, last = hunk["lines"][-1]
                hunk["lines"][-1] = (last_tag, last.rstrip(b"\n"))
            elif tag in (b" ", b"-", b"+"):
                hunk["lines"].append((tag, text))
                if tag != b"+":
                    old_left -= 1
                empty = False
            else:
                raise PatchError(f"{name}: bad line {line[:40]!r}")
        if old_left != 0 or empty:
            raise PatchError(f"{name}: hunk at line {hunk['start']} does not match its header")
        hunks.append(hunk)
    return hunks


def _find_block(lines, block, expected, floor):
    """The place of `block` in `lines` nearest to `expected`, not before `floor`."""
    last = len(lines) - len(block)
    if not block:
        return min(max(expected, floor), len(lines))
    distance = 0
    while expected - distance >= floor or expected + distance <= last:
        for pos in (expected - distance, expected + distance):
            if floor <= pos <= last and lines[pos:pos + len(block)] == block:
                return pos
        distance += 1
    return None


def _trim(hunk_lines, fuzz):
    """Drop up to `fuzz` context lines from each end of a hunk. Returns what is
    left and how many lines went from the front."""
    trimmed = list(hunk_lines)
    dropped = 0
    while dropped < fuzz and trimmed and trimmed[0][0] == b" ":
        trimmed.pop(0)
        dropped += 1
    for _ in range(fuzz):
        if trimmed and trimmed[-1][0] == b" ":
            trimmed.pop()
    return trimmed, dropped


def apply_hunks(data, hunks):
    """Returns (patched bytes, fuzzed hunk numbers, failed hunk numbers)."""
    lines = split_lines(data)
    fuzzed, failed = [], []
    offset = 0  # how far the lines have moved from where the patch counts them
    floor = 0
    for number, hunk in enumerate(hunks, 1):
        for fuzz in range(FUZZ + 1):
            part, dropped = _trim(hunk["lines"], fuzz)
            old = [text for tag, text in part if tag != b"+"]
            named = hunk["start"] - 1 + dropped
            pos = _find_block(lines, old, named + offset, floor)
            if pos is not None:
                break
        if pos is None:
            failed.append(number)
            continue
        if fuzz:
            fuzzed.append(number)
        new = [text for tag, text in part if tag != b"-"]
        lines[pos:pos + len(old)] = new
        offset = pos - named + len(new) - len(old)
        floor = pos + len(new)
    return b"".join(lines), fuzzed, failed


def _patch_files(target):
    found = []
    for base, _, names in os.walk(PATCH_DIRS[target]):
        for name in names:
            if name.endswith(".patch"):
                path = os.path.join(base, name)
                found.append((os.path.relpath(path, PATCH_DIRS[target]).replace(os.sep, "/")[:-len(".patch")], path))
    return sorted(found)


def _hunk_summary(hunks, number):
    hunk = hunks[number - 1]
    changed = next((text for tag, text in hunk["lines"] if tag != b" "), b"")
    return f"hunk {number} (line {hunk['start']}): {changed.decode('utf-8', 'replace').strip()[:70]}"


def _is_balatro_plus_mobile(game):
    """Recognize the supplied Balatro+ 1.0.1o mobile source variant.

    It shares the PROD_mobile version marker with the upstream mobile game,
    but ships newer collaboration credits and has already removed F_BABYNAMES.
    Those differences make a small set of upstream patch hunks redundant.
    """
    version = game.get("version.jkr", b"")
    ui = game.get("functions/UI_definitions.lua", b"")
    globals_lua = game.get("globals.lua", b"")
    return (
        b"PROD_mobile" in version
        and b"['Critical Role']" in ui
        and b"['Dave the Diver']" in ui
        and b"G.F_BABYNAMES" not in ui
        and b"F_BABYNAMES" not in globals_lua
    )


def _adapt_balatro_plus_mobile_globals(data):
    """Apply the current mobile feature flags to the Balatro+ globals layout."""
    source = data.decode("utf-8")
    old_flags = (
        "    self.F_HIDE_BETA_LANGS = nil\n"
        "    self.F_TOUCH_MOUSE = nil\n"
        "    self.F_HIDE_LOADING_BAR = nil\n"
    )
    new_flags = (
        "    self.F_HIDE_BETA_LANGS = nil\n"
        "    self.F_VERTICAL_SETTINGS = false\n"
    )
    if source.count(old_flags) != 1:
        raise PatchError("Balatro+ globals: could not locate the mobile feature-flag defaults.")
    source = source.replace(old_flags, new_flags, 1)

    start = source.find("    if love.system.getOS() == 'iOS' or love.system.getOS() == 'Android' then")
    end = source.find("    if love.system.getPlatform and love.system.getPlatform() == 'tvos' then", start)
    if start < 0 or end < 0:
        raise PatchError("Balatro+ globals: could not locate the iOS/Android feature-flag block.")

    mobile_flags = (
        "    if love.system.getOS() == 'Android' or love.system.getOS() == 'iOS' then\n"
        "        self.F_SAVE_TIMER = 5\n"
        "        self.F_ENGLISH_ONLY = false\n"
        "        self.F_CRASH_REPORTS = false\n"
        "        self.F_VIDEO_SETTINGS = false\n"
        "        self.F_VERTICAL_SETTINGS = true\n"
        "        self.F_MOBILE_UI = true\n"
        "        self.F_EXTERNAL_LINKS = false\n"
        "        self.F_HAPTIC = true\n"
        "        self.F_QUIT_BUTTON = false\n"
        "    end\n\n"
    )
    source = source[:start] + mobile_flags + source[end:]
    return source.encode("utf-8")


def patched_game(game):
    """Apply the selected portrait patches and return {path: bytes}, plus fuzzed hunks."""
    target = game_target(game)
    plus_mobile = target == "mobile" and _is_balatro_plus_mobile(game)
    result = {rel: data for rel, data in game.items() if rel not in MOBILE_ONLY}
    fuzzed, failed = [], []
    redundant_plus_ui_hunks = {49, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95}

    for rel, path in _patch_files(target):
        with open(path, "rb") as f:
            hunks = parse_patch(f.read(), rel)
        if rel not in game:
            failed.append(f"{rel}: not in this copy of the game")
            continue

        result[rel], fuzzy, broken = apply_hunks(game[rel], hunks)
        fuzzed += [f"{rel} {_hunk_summary(hunks, n)}" for n in fuzzy]

        if plus_mobile and rel == "functions/UI_definitions.lua":
            already_present = (
                b"local loc_options = localize(_suit, 'collabs')" in game[rel]
                and b"['The Witcher']" in game[rel]
                and b"['Critical Role']" in game[rel]
                and b"['Dave the Diver']" in game[rel]
            )
            if already_present and set(broken) == redundant_plus_ui_hunks:
                broken = []

        if plus_mobile and rel == "globals.lua" and broken == [2, 3]:
            result[rel] = _adapt_balatro_plus_mobile_globals(result[rel])
            broken = []

        failed += [f"{rel} {_hunk_summary(hunks, n)}" for n in broken]

    if failed:
        shown = failed[:10] + ([f"and {len(failed) - 10} more"] if len(failed) > 10 else [])
        raise PatchError("These changes found no place in this copy of the game:\n  "
                         + "\n  ".join(shown)
                         + "\nThis copy differs from the one the patches were made for: "
                         "use an up to date mod, or Steam's Balatro.exe.")
    return result, fuzzed


def _hash(items):
    h = hashlib.sha256()
    for name, data in sorted(items):
        h.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
    return h.hexdigest()


def patches_hash(target):
    items = []
    for rel, path in _patch_files(target):
        with open(path, "rb") as f:
            items.append((rel, f.read()))
    return _hash(items)


def _src_game_files():
    """The game's files in src/: everything the stamp covers."""
    files = _read_folder(SRC_DIR) if os.path.isdir(SRC_DIR) else {}
    return {rel: data for rel, data in files.items() if not re.match(r"portrait_.*\.lua$", rel)}


def _write_stamp(target):
    with open(STAMP, "w") as f:
        json.dump({"target": target, "patches": patches_hash(target),
                   "src": _hash(_src_game_files().items())}, f, indent=2)


def src_state():
    """'missing': no game code in src/. 'stale': the patches changed since
    src/ was made. 'conflict': that, and src/ has edits of its own too.
    'ready': nothing to do."""
    if not os.path.isfile(os.path.join(SRC_DIR, "game.lua")):
        return "missing"
    try:
        with open(STAMP) as f:
            stamp = json.load(f)
    except (OSError, ValueError):
        return "stale"
    if stamp.get("patches") == patches_hash(stamp.get("target", "steam")):
        return "ready"
    return "stale" if stamp.get("src") == _hash(_src_game_files().items()) else "conflict"


def apply_to_src(game_path, allow_untested=False):
    game = read_game(game_path)
    version = game_version(game)
    if version not in TESTED_VERSIONS and not allow_untested:
        raise PatchError(f"This copy of the game is version {version}; the patches are made for "
                         f"{', '.join(TESTED_VERSIONS)}.\nPass --allow-untested-game to try it anyway.")
    result, fuzzed = patched_game(game)
    for rel, data in result.items():
        path = os.path.join(SRC_DIR, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    target = game_target(game)
    _write_stamp(target)
    print(f"  Patched {len(_patch_files(target))} game files for version {version} ({target}) -> src/")
    if fuzzed:
        print(f"  {len(fuzzed)} changes needed fuzz, check them in game:")
        for line in fuzzed:
            print(f"    {line}")


def _diff(rel, old, new):
    with tempfile.TemporaryDirectory() as tmp:
        for side, data in (("a", old), ("b", new)):
            with open(os.path.join(tmp, side), "wb") as f:
                f.write(data)
        out = subprocess.run(["git", "-c", "core.autocrlf=false", "diff", "--no-index", "--no-color",
                              "--no-ext-diff", "--text", "--histogram", f"-U{CONTEXT}", "a", "b"],
                             cwd=tmp, stdout=subprocess.PIPE).stdout
    body = out[out.index(b"@@"):]
    # The text git puts after @@ is a line of the game and tells a patch nothing.
    body = re.sub(rb"(?m)^(@@ [^@]* @@).*$", rb"\1", body)
    return f"--- a/{rel}\n+++ b/{rel}\n".encode() + body


def make(game_path):
    game = read_game(game_path)
    target = game_target(game)
    src = _src_game_files()
    missing = sorted(set(game) - set(src) - set(MOBILE_ONLY))
    if missing:
        raise PatchError(f"src/ has no {missing[0]}: run `python tools/patches.py apply` first.")
    written = 0
    keep = set()
    for rel in sorted(set(game) - set(MOBILE_ONLY)):
        if src[rel] == game[rel]:
            continue
        path = os.path.join(PATCH_DIRS[target], rel.replace("/", os.sep) + ".patch")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(_diff(rel, game[rel], src[rel]))
        keep.add(path)
        written += 1
    for _, path in _patch_files(target):
        if path not in keep:
            os.remove(path)
    result, _ = patched_game(game)
    wrong = [rel for rel in result if result[rel] != src[rel]]
    if wrong:
        raise PatchError(f"The new patches do not give src/ back: {', '.join(wrong)}")
    _write_stamp(target)
    folder = os.path.relpath(PATCH_DIRS[target], ROOT).replace(os.sep, "/")
    print(f"  {written} patches -> {folder}/ (they give src/ back byte for byte)")


def check(game_path):
    game = read_game(game_path)
    result, _ = patched_game(game)
    src = _src_game_files()
    wrong = [rel for rel in result if src.get(rel) != result[rel]]
    if wrong:
        raise PatchError("src/ and the patches differ: " + ", ".join(sorted(wrong))
                         + "\nRun `python tools/patches.py make`.")
    print(f"  Patches and src/ agree ({len(result)} files).")


def lint():
    for target in PATCH_DIRS:
        hunks = 0
        for rel, path in _patch_files(target):
            with open(path, "rb") as f:
                hunks += len(parse_patch(f.read(), rel))
        print(f"  {target}: {len(_patch_files(target))} patches, {hunks} hunks parse.")


def main():
    parser = argparse.ArgumentParser(description="Build src/ from the game and the patches, or the patches from src/.")
    parser.add_argument("command", choices=("apply", "make", "check", "lint"))
    parser.add_argument("--game", metavar="PATH", help="Balatro.exe, Balatro.love, the official APK or a folder")
    parser.add_argument("--allow-untested-game", action="store_true",
                        help="apply to a game version the patches were not made for")
    args = parser.parse_args()
    try:
        if args.command == "lint":
            lint()
            return
        game = args.game or default_game()
        if args.command == "apply":
            if src_state() == "conflict":
                raise PatchError("The patches changed and src/ has edits of its own. Run "
                                 "`python tools/patches.py make` on the old patches first.")
            apply_to_src(game, args.allow_untested_game)
        elif args.command == "make":
            make(game)
        else:
            check(game)
    except PatchError as e:
        sys.exit(f"ERROR: {e}")


if __name__ == "__main__":
    main()

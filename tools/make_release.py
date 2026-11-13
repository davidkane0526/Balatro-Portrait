#!/usr/bin/env python3
"""Gather what a GitHub release of the mod carries, and check it first.

    python tools/make_release.py            # -> dist/release-<version>/

A release has the Zygisk module ZIP, SHA256SUMS.txt and the release notes;
GitHub adds the "Source code" archives from the tag itself. Nothing here is
uploaded: the folder is what `gh release create` gets, and the command to run
is printed at the end.

Refuses to go on when:
- the version differs between src/portrait_config.lua, zygisk/module/module.prop,
  zygisk/update.json and the top CHANGELOG entry,
- the Zygisk ZIP is missing, older than any Lua file in src/ or the module's
  own sources, or carries another version,
- the ZIP's module is missing one of the files of our own it has to preload,
- git tracks a game file under src/, or patches/portrait/ no longer gives src/.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZYGISK = os.path.join(ROOT, "zygisk")
MODULE_ZIP = os.path.join(ZYGISK, "dist", "balatro_portrait.zip")


def fail(msg):
    sys.exit(f"ERROR: {msg}")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def versions():
    found = {}
    m = re.search(r'^\s*version\s*=\s*"([^"]+)"', read("src/portrait_config.lua"), re.M)
    found["src/portrait_config.lua"] = m and m.group(1)
    m = re.search(r"^version=(.+)$", read("zygisk/module/module.prop"), re.M)
    found["zygisk/module/module.prop"] = m and m.group(1).strip()
    found["zygisk/update.json"] = json.loads(read("zygisk/update.json")).get("version")
    m = re.search(r"^## \[?v([0-9][^\] ]*)", read("CHANGELOG.md"), re.M)
    found["CHANGELOG.md"] = m and m.group(1)
    if len(set(found.values())) != 1 or None in found.values():
        fail("versions disagree:\n" + "\n".join(f"  {k}: {v}" for k, v in found.items()))
    return found["src/portrait_config.lua"]


def changelog_section(version):
    text = read("CHANGELOG.md")
    m = re.search(rf"^## \[?v{re.escape(version)}\b.*?$\n(.*?)(?=^## |^---$|^# )", text, re.M | re.S)
    if not m:
        fail(f"no CHANGELOG section for v{version}")
    return m.group(1).strip() + "\n"


def newest_mtime(paths):
    newest, which = 0, None
    for base in paths:
        for dirpath, dirnames, files in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in ("resources", "localization", "build", "deps", "dist")]
            for name in files:
                if name.endswith((".lua", ".cpp", ".py", ".sh", ".prop", ".txt")) and name != "assets_gen.h":
                    p = os.path.join(dirpath, name)
                    t = os.path.getmtime(p)
                    if t > newest:
                        newest, which = t, p
    return newest, which


def check_patches():
    tracked = subprocess.run(["git", "ls-files", "src"], cwd=ROOT, stdout=subprocess.PIPE, text=True).stdout.split("\n")
    game = [f for f in tracked if f and not re.match(r"src/(portrait_[^/]*\.lua|smali/)", f)]
    if game:
        fail(f"git tracks the game's own code: {', '.join(game[:5])}")
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import patches
    play = os.environ.get("BALATRO_APK") or os.path.join(ROOT, ".headless", "play.apk")
    if not os.path.isfile(play):
        fail("the Play copy is needed to check its patches: put base.apk at .headless/play.apk "
             "or point $BALATRO_APK at it")
    try:
        patches.check(patches.default_game())
        patches.check(play)
    except patches.PatchError as e:
        fail(str(e))


def check_module_zip(version):
    if not os.path.isfile(MODULE_ZIP):
        fail("zygisk/dist/balatro_portrait.zip is missing: run zygisk/build_pkg.ps1")
    newest, which = newest_mtime([os.path.join(ROOT, "src"), os.path.join(ZYGISK, "src"),
                                  os.path.join(ZYGISK, "module")])
    for extra in [os.path.join(ZYGISK, "gen_assets.py"), os.path.join(ZYGISK, "patcher.lua")] + \
            [os.path.join(base, name) for base, _, names in os.walk(os.path.join(ROOT, "patches", "portrait-mobile"))
             for name in names]:
        if os.path.getmtime(extra) > newest:
            newest, which = os.path.getmtime(extra), extra
    zipped = os.path.getmtime(MODULE_ZIP)
    if newest > zipped:
        fail(f"the Zygisk ZIP is older than {os.path.relpath(which, ROOT)}: run zygisk/build_pkg.ps1 again")

    own = sorted(n[:-4] for n in os.listdir(os.path.join(ROOT, "src"))
                 if n.startswith("portrait_") and n.endswith(".lua"))
    with zipfile.ZipFile(MODULE_ZIP) as z:
        prop = z.read("module.prop").decode()
        if f"version={version}" not in prop:
            fail(f"the Zygisk ZIP's module.prop is not version {version}: run zygisk/build_pkg.ps1 again")
        for script in ("customize.sh", "sync_mods.sh", "service.sh", "action.sh"):
            if b"\r\n" in z.read(script):
                fail(f"{script} in the ZIP has CRLF line ends; Android's shell will not run it")
        sos = [n for n in z.namelist() if n.startswith("zygisk/") and n.endswith(".so")]
        if "zygisk/arm64-v8a.so" not in sos or len(sos) < 5:
            fail(f"the Zygisk ZIP is missing variants: {sos}")
        for n in sos:
            data = z.read(n)
            for mod in own + ["portrait_game_patches"]:
                if f'package.preload["{mod}"]'.encode() not in data:
                    fail(f"{n} does not preload {mod}: the game would not start under the module")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    version = versions()
    check_patches()
    check_module_zip(version)

    out = os.path.join(ROOT, "dist", f"release-{version}")
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    shutil.copy2(MODULE_ZIP, out)
    with open(os.path.join(out, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"{sha256(MODULE_ZIP)}  balatro_portrait.zip\n")

    notes = changelog_section(version)
    notes += (
        "\n## Downloads\n\n"
        "- **balatro_portrait.zip**: the Zygisk module for rooted Android "
        "(Magisk, KernelSU or APatch with Zygisk). Flash it, answer the two "
        "volume-key questions, reboot, open the official Balatro. Mods on it "
        "are experimental.\n"
        "- **Source code (zip / tar.gz)**: everything needed to build the "
        "portrait APK (no root) or the iPhone IPA from your own copy of the "
        "game. Unzip it and run `python build.py`; on the phone use Termux "
        "and `bash termux-build.sh`.\n"
        "- **SHA256SUMS.txt**: checksum of the module ZIP.\n\n"
        "There is no ready-made APK or IPA: it would contain the game. "
        "Which route is yours, step by step: "
        "[README](https://github.com/LoreanXavier/balatro-portrait-mobile#install).\n"
    )
    with open(os.path.join(out, "NOTES.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(notes)

    rel = os.path.relpath(out, ROOT).replace(os.sep, "/")
    print(f"release {version} -> {rel}/")
    for name in sorted(os.listdir(out)):
        print(f"  {name}  {os.path.getsize(os.path.join(out, name)):,} bytes")
    print("\nTo publish (after the tag is pushed):")
    print(f"  gh release create v{version} {rel}/balatro_portrait.zip {rel}/SHA256SUMS.txt "
          f"--title v{version} --notes-file {rel}/NOTES.md")


if __name__ == "__main__":
    main()

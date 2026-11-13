#!/usr/bin/env python3
"""Run the portrait build on the PC, unattended, and report what happened.

    python tools/headless/run.py                      # smoke scenario, default phone
    python tools/headless/run.py --device all         # every phone size in DEVICES
    python tools/headless/run.py --scenario my.lua    # your own scenario
    python tools/headless/run.py --source love        # test the built Game.love instead of src/

No phone, emulator or Steam client is needed. The LOVE engine is taken from
your own Balatro.exe (the exe is LOVE with the game zipped onto its end, so
the part before the zip is a plain LOVE runtime), the game runs from a staging
copy of src/ in a window sized like a phone and parked off screen, and a Lua
harness drives it from a scenario script. Each run leaves screenshots, a log
and report.json under .headless/out/<device>/; the exit code is 0 only when
every device passed.

The window is real: LOVE has no renderer without one. "Headless" here means
nothing needs a person, a screen or a phone, which is what an agent or CI-ish
loop needs.
"""

import argparse
import copy
import json
import re
import os
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from patches import find_balatro  # noqa: E402
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(ROOT, ".headless")
ENGINE_DIR = os.path.join(WORK, "engine")
STAGE_DIR = os.path.join(WORK, "stage")
OUT_DIR = os.path.join(WORK, "out")
# LOVE keeps a non-fused game's saves here, one folder per identity.
PROFILE_ROOT = os.path.join(os.environ.get("APPDATA", ""), "LOVE")

# What --scenario all runs. boot is left out: smoke boots too, and boot is the
# one that keeps the 12 s intro.
SUITE = ["smoke", "menus", "run", "layouts", "stress", "swipe", "crt", "mod_folder", "keyboard", "haptics", "blind_screen", "stats_crash"]

# Logical window sizes (dp / points), the space the layout code works in, the
# OS the game is told it runs on, and the iOS safe-area insets (top, bottom)
# from tests/ios_inset_fixtures.txt.
DEVICES = {
    "phone":      ((412, 915), "Android", None),    # Pixel 7 class, 20:9
    "narrow":     ((360, 800), "Android", None),    # small Android, where most clipping shows
    "tall":       ((384, 854), "Android", None),    # 20:9 at a low density
    "tablet":     ((800, 1280), "Android", None),   # portrait tablet
    "fold":       ((720, 880), "Android", None),    # a foldable opened, nearly square
    "small":      ((320, 640), "Android", None),    # the smallest phones still in use
    "long":       ((360, 840), "Android", None),    # 21:9
    "razr":       ((411, 1005), "Android", None),   # moto razr 2023, a 22:9 foldable (#11)
    "iphone-se":  ((375, 667), "iOS", (20, 0)),     # 16:9, home button
    "iphone15":   ((393, 852), "iOS", (59, 34)),    # Dynamic Island
    "iphone-max": ((430, 932), "iOS", (59, 34)),
    "desktop":    ((1280, 720), None, None),        # landscape Windows: the vanilla layout
}

# What love.exe needs next to it. luasteam/steam_api are left out on purpose,
# the harness stubs Steam.
ENGINE_DLLS = ["love.dll", "lua51.dll", "SDL2.dll", "OpenAL32.dll", "mpg123.dll",
               "msvcp120.dll", "msvcr120.dll", "https.dll"]

def prepare_engine(balatro_exe):
    """Cut the LOVE runtime off the front of Balatro.exe, once per game update."""
    stamp_path = os.path.join(ENGINE_DIR, "stamp.json")
    st = os.stat(balatro_exe)
    stamp = {"exe": balatro_exe, "size": st.st_size, "mtime": int(st.st_mtime)}
    love_exe = os.path.join(ENGINE_DIR, "love.exe")
    if os.path.isfile(love_exe) and os.path.isfile(stamp_path):
        with open(stamp_path) as f:
            if json.load(f) == stamp:
                return love_exe

    with zipfile.ZipFile(balatro_exe) as z:
        # zipfile already corrects header offsets for data in front of the
        # archive, so the smallest one is where the zip starts in the exe.
        start = min(i.header_offset for i in z.infolist())
    os.makedirs(ENGINE_DIR, exist_ok=True)
    with open(balatro_exe, "rb") as src, open(love_exe, "wb") as dst:
        dst.write(src.read(start))

    game_dir = os.path.dirname(balatro_exe)
    for dll in ENGINE_DLLS:
        p = os.path.join(game_dir, dll)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(ENGINE_DIR, dll))
        elif dll in ("love.dll", "lua51.dll", "SDL2.dll"):
            sys.exit(f"ERROR: {dll} is missing next to {balatro_exe}")
    with open(stamp_path, "w") as f:
        json.dump(stamp, f)
    print(f"  engine: love.exe ({start} bytes) cut from {balatro_exe}")
    return love_exe


def die_with_children():
    """Windows closes this job when the runner ends in any way, and closing it
    ends every game the runner started: none is left holding the engine's files."""
    import ctypes
    from ctypes import wintypes

    class Basic(ctypes.Structure):
        _fields_ = [("user_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
                    ("flags", wintypes.DWORD), ("min_ws", ctypes.c_size_t), ("max_ws", ctypes.c_size_t),
                    ("processes", wintypes.DWORD), ("affinity", ctypes.c_size_t),
                    ("priority", wintypes.DWORD), ("scheduling", wintypes.DWORD)]

    class Extended(ctypes.Structure):
        _fields_ = [("basic", Basic), ("io", ctypes.c_ulonglong * 6), ("process_memory", ctypes.c_size_t),
                    ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t),
                    ("peak_job", ctypes.c_size_t)]

    KILL_ON_JOB_CLOSE, EXTENDED_LIMITS = 0x2000, 9
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateJobObjectW.restype = wintypes.HANDLE
    k32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    k32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    k32.GetCurrentProcess.restype = wintypes.HANDLE
    k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    job = k32.CreateJobObjectW(None, None)
    limits = Extended()
    limits.basic.flags = KILL_ON_JOB_CLOSE
    if not (job and k32.SetInformationJobObject(job, EXTENDED_LIMITS, ctypes.byref(limits), ctypes.sizeof(limits))
            and k32.AssignProcessToJobObject(job, k32.GetCurrentProcess())):
        print("  warning: games may outlive this runner if it is killed")


def _sync_tree(src, dst):
    """Copy src over dst, skipping files whose size and mtime already match."""
    copied = 0
    for base, dirs, files in os.walk(src):
        rel = os.path.relpath(base, src)
        target = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(target, exist_ok=True)
        for name in files:
            if name.endswith(".bak"):
                continue
            s, d = os.path.join(base, name), os.path.join(target, name)
            ss = os.stat(s)
            if os.path.exists(d):
                ds = os.stat(d)
                if ds.st_size == ss.st_size and int(ds.st_mtime) == int(ss.st_mtime):
                    continue
            shutil.copy2(s, d)
            copied += 1
    return copied


def play_apk():
    """The Play copy that --source zygisk starts from."""
    apk = os.environ.get("BALATRO_APK") or os.path.join(WORK, "play.apk")
    if not os.path.isfile(apk):
        sys.exit("ERROR: --source zygisk needs the official APK. Copy base.apk from your Play\n"
                 "       install to .headless/play.apk, or point $BALATRO_APK at it.")
    return apk


def _squash_head(main_head):
    return b" ".join(l.split(b"--")[0].strip() for l in main_head.splitlines()).strip()


def _lua_quote(data):
    return b'"' + data.replace(b"\\", b"\\\\").replace(b'"', b'\\"') + b'"'


def stage_game(source, balatro_exe=None):
    """Build the folder LOVE runs: the game plus the harness hooked into it."""
    if source == "vanilla":
        # The game as shipped, from the zip inside Balatro.exe: the baseline
        # for telling a mod's own failures from the portrait build's.
        game_dir = os.path.join(STAGE_DIR, "vanilla")
        if os.path.isdir(game_dir):
            shutil.rmtree(game_dir)
        with zipfile.ZipFile(balatro_exe) as z:
            z.extractall(game_dir)
        print("  stage: vanilla game from Balatro.exe -> .headless/stage/vanilla")
    elif source == "zygisk":
        # The official app with the Zygisk module in: the Play copy as shipped,
        # and conf.lua swapped for the chunk the module carries. It builds the
        # game into portrait_game/ in the save folder; zygisk_head.lua and
        # zygisk_tail.lua stand in for the native side around it.
        apk = play_apk()
        game_dir = os.path.join(STAGE_DIR, "zygisk")
        if os.path.isdir(game_dir):
            shutil.rmtree(game_dir)
        with zipfile.ZipFile(apk) as z:
            for name in z.namelist():
                if name.startswith("assets/") and not name.endswith("/"):
                    path = os.path.join(game_dir, *name.split("/")[1:])
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, "wb") as f:
                        f.write(z.read(name))
        sys.path.insert(0, os.path.join(ROOT, "zygisk"))
        import gen_assets
        payload, _ = gen_assets.build_payload(readabletro=True, crt_disable=False)
        with open(os.path.join(HERE, "zygisk_head.lua"), "rb") as f:
            head = f.read()
        with open(os.path.join(HERE, "zygisk_tail.lua"), "rb") as f:
            tail = f.read()
        with open(os.path.join(HERE, "main_head.lua"), "rb") as f:
            main_head = _squash_head(f.read())
        os.replace(os.path.join(game_dir, "conf.lua"), os.path.join(game_dir, "bpm_play_conf.lua"))
        with open(os.path.join(game_dir, "conf.lua"), "wb") as f:
            f.write(head + payload + b"\nBPM_MAIN_HEAD = " + _lua_quote(main_head) + b"\n" + tail)
        shutil.copy2(os.path.join(HERE, "harness.lua"), os.path.join(game_dir, "bpm_headless.lua"))
        print(f"  stage: {os.path.basename(apk)} + the Zygisk chunk -> .headless/stage/zygisk")
        return game_dir
    elif source == "src" or os.path.isdir(source):
        # A directory: another checkout's src/ (say, the last release, to tell
        # what a change did).
        src_dir = os.path.join(ROOT, "src") if source == "src" else os.path.abspath(source)
        # resources/ and localization/ are extracted from the game, not tracked.
        for extracted in ("resources", "localization"):
            if source != "src" and not os.path.isdir(os.path.join(src_dir, extracted)):
                shutil.copytree(os.path.join(ROOT, "src", extracted), os.path.join(src_dir, extracted))
        if not (os.path.isfile(os.path.join(src_dir, "game.lua")) and os.path.isdir(os.path.join(src_dir, "resources"))):
            sys.exit("ERROR: src/ has no game in it. Run `python build.py --skip-apk` once so it\n"
                     "       builds it from your Balatro copy and patches/portrait/.")
        game_dir = os.path.join(STAGE_DIR, "game" if source == "src" else "alt")
        n = _sync_tree(src_dir, game_dir)
        print(f"  stage: src/ -> .headless/stage/game ({n} files updated)")
    else:
        love_file = os.path.join(ROOT, "Game.love")
        if not os.path.isfile(love_file):
            sys.exit("ERROR: Game.love not found. Run `python build.py --skip-apk` first.")
        game_dir = os.path.join(STAGE_DIR, "love")
        if os.path.isdir(game_dir):
            shutil.rmtree(game_dir)
        with zipfile.ZipFile(love_file) as z:
            z.extractall(game_dir)
        print("  stage: Game.love extracted to .headless/stage/love")

    # main.lua and conf.lua are always rewritten from the source so the hooks
    # never stack up across runs.
    origin = (os.path.join(ROOT, "src") if source == "src"
              else os.path.abspath(source) if os.path.isdir(source) else game_dir)
    if source == "vanilla":
        with open(os.path.join(game_dir, "main.lua"), "rb") as f:
            vanilla_main = f.read()
    if source == "vanilla":
        main_lua = vanilla_main
    else:
        with open(os.path.join(origin, "main.lua"), "rb") as f:
            main_lua = f.read()
    with open(os.path.join(origin, "conf.lua"), "rb") as f:
        conf_lua = f.read()
    with open(os.path.join(HERE, "conf_tail.lua"), "rb") as f:
        conf_tail = f.read()
    with open(os.path.join(HERE, "main_head.lua"), "rb") as f:
        main_head = f.read()
    head = _squash_head(main_head)
    lines = main_lua.split(b"\n")
    with open(os.path.join(game_dir, "main.lua"), "wb") as f:
        # Kept on one line so the game's own line numbers in tracebacks still
        # match src/main.lua: the blank line 2 when there is one, so line 1
        # stays as Lovely patches (Steamodded's preflight) expect it.
        if len(lines) > 1 and not lines[1].strip():
            lines[1] = head
            f.write(b"\n".join(lines) + b"\nrequire('bpm_headless')\n")
        else:
            f.write(head + b" " + main_lua + b"\nrequire('bpm_headless')\n")
    with open(os.path.join(game_dir, "conf.lua"), "wb") as f:
        f.write(conf_lua + b"\n" + conf_tail)
    shutil.copy2(os.path.join(HERE, "harness.lua"), os.path.join(game_dir, "bpm_headless.lua"))
    return game_dir


def resolve_scenario(name):
    if os.path.isfile(name):
        return os.path.abspath(name)
    p = os.path.join(HERE, "scenarios", name + ("" if name.endswith(".lua") else ".lua"))
    if os.path.isfile(p):
        return p
    known = sorted(f[:-4] for f in os.listdir(os.path.join(HERE, "scenarios")) if f.endswith(".lua"))
    sys.exit(f"ERROR: no scenario '{name}'. Built in: {', '.join(known)}")


HIDDEN_DESKTOP = "bpm-headless"
_desktops = {}


def _open_hidden_desktop(name):
    """Create (once per run of this script) the never-shown desktop `name`.

    The handle stays open until the script exits: a desktop is destroyed when
    its last handle closes, and closing it while another job's game is still
    starting on it made that game fail to initialise (0xC0000142). Parallel
    jobs each get their own desktop for the same reason.
    """
    import ctypes
    from ctypes import wintypes
    if name in _desktops:
        return
    u32 = ctypes.WinDLL("user32", use_last_error=True)
    GENERIC_ALL = 0x10000000
    u32.CreateDesktopW.restype = wintypes.HANDLE
    u32.CreateDesktopW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_void_p,
                                   wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
    desk = u32.CreateDesktopW(name, None, None, 0, GENERIC_ALL, None)
    if not desk:
        raise OSError(ctypes.get_last_error(), f"CreateDesktopW({name}) failed")
    _desktops[name] = desk


def _spawn_on_hidden_desktop(cmd, env, cwd, log_file, timeout, desktop=HIDDEN_DESKTOP):
    """Start cmd on a separate, never-shown Windows desktop and wait for it.

    A window on another desktop is not on the user's screen, not in their
    taskbar or Alt+Tab, and cannot take focus, but the GPU still renders it,
    so screenshots work. This is the same mechanism Windows uses for the
    logon and UAC screens.
    """
    import ctypes
    from ctypes import wintypes
    import msvcrt

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    u32 = ctypes.WinDLL("user32", use_last_error=True)

    _open_hidden_desktop(desktop)

    class STARTUPINFOW(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR),
                    ("lpDesktop", wintypes.LPWSTR), ("lpTitle", wintypes.LPWSTR),
                    ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD),
                    ("dwXSize", wintypes.DWORD), ("dwYSize", wintypes.DWORD),
                    ("dwXCountChars", wintypes.DWORD), ("dwYCountChars", wintypes.DWORD),
                    ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                    ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD),
                    ("lpReserved2", ctypes.c_void_p), ("hStdInput", wintypes.HANDLE),
                    ("hStdOutput", wintypes.HANDLE), ("hStdError", wintypes.HANDLE)]

    class PROCESS_INFORMATION(ctypes.Structure):
        _fields_ = [("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE),
                    ("dwProcessId", wintypes.DWORD), ("dwThreadId", wintypes.DWORD)]

    STARTF_USESTDHANDLES = 0x100
    CREATE_UNICODE_ENVIRONMENT = 0x400
    CREATE_NO_WINDOW = 0x08000000
    HANDLE_FLAG_INHERIT = 1

    out_handle = msvcrt.get_osfhandle(log_file.fileno())
    k32.SetHandleInformation(wintypes.HANDLE(out_handle), HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)

    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(si)
    si.lpDesktop = desktop
    si.dwFlags = STARTF_USESTDHANDLES
    si.hStdOutput = si.hStdError = out_handle
    pi = PROCESS_INFORMATION()

    env_block = ctypes.create_unicode_buffer("\0".join(f"{k}={v}" for k, v in env.items()) + "\0\0")
    cmdline = ctypes.create_unicode_buffer(subprocess.list2cmdline(cmd))
    k32.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
                                   wintypes.BOOL, wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR,
                                   ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION)]
    if not k32.CreateProcessW(None, cmdline, None, None, True,
                              CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                              env_block, cwd, ctypes.byref(si), ctypes.byref(pi)):
        raise OSError(ctypes.get_last_error(), "CreateProcessW failed")
    k32.WaitForSingleObject.restype = wintypes.DWORD
    if k32.WaitForSingleObject(pi.hProcess, int(timeout * 1000)) != 0:
        k32.TerminateProcess(pi.hProcess, 3)
        k32.WaitForSingleObject(pi.hProcess, 5000)
        code = -1
    else:
        exit_code = wintypes.DWORD()
        k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(exit_code))
        code = ctypes.c_int32(exit_code.value).value
    k32.CloseHandle(pi.hThread)
    k32.CloseHandle(pi.hProcess)
    return code


import queue
_slots = queue.Queue()


MODS_CACHE = os.path.join(WORK, "mods-cache", "x")
LOVELY_ENGINE_DIR = os.path.join(WORK, "engine-lovely")


def _mod_source(name):
    """The extracted folder of a mod in the cache, by name prefix
    ("smods-26", "talisman", "cryptid"): the one folder inside its download."""
    hits = sorted(d for d in os.listdir(MODS_CACHE) if d.lower().startswith(name.lower()))
    if not hits:
        sys.exit(f"ERROR: no mod matching '{name}' in {os.path.relpath(MODS_CACHE, ROOT)} "
                 f"(have: {', '.join(sorted(os.listdir(MODS_CACHE)))})")
    root = os.path.join(MODS_CACHE, hits[-1])
    inner = [d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))]
    return os.path.join(root, inner[0]) if len(inner) == 1 else root


def prepare_lovely_engine(love_exe):
    """The engine with Lovely (its winmm.dll) beside it, kept apart from the plain
    engine so runs without mods stay vanilla."""
    src = _mod_source("lovely-win")
    dll = next(f for f in os.listdir(src) if f.lower().endswith(".dll"))
    # Only what changed: a game from another runner may have these files open.
    _sync_tree(ENGINE_DIR, LOVELY_ENGINE_DIR)
    dst = os.path.join(LOVELY_ENGINE_DIR, dll)
    if not os.path.isfile(dst) or os.path.getsize(dst) != os.path.getsize(os.path.join(src, dll)):
        shutil.copy2(os.path.join(src, dll), dst)
    return os.path.join(LOVELY_ENGINE_DIR, "love.exe")


def stage_mods(names, tag):
    """A fresh mod folder for one run (Lovely --mod-dir): never the player's
    %APPDATA%/Balatro/Mods."""
    mod_dir = os.path.join(WORK, "moddir", tag)
    if os.path.isdir(mod_dir):
        shutil.rmtree(mod_dir)
    os.makedirs(mod_dir)
    for name in names:
        src = _mod_source(name)
        shutil.copytree(src, os.path.join(mod_dir, os.path.basename(src)))
    return mod_dir


def run_one(love_exe, game_dir, scenario, device, spec, args):
    size, device_os, insets = spec
    if args.os != "auto":
        device_os = None if args.os == "Windows" else args.os
    out = os.path.join(OUT_DIR, args.out, device) if args.out else os.path.join(OUT_DIR, device)
    # One profile per scenario, device and --out: runs side by side, in this
    # runner or another one, must never see each other's saves (a Continue
    # would load the other run's game, a language set by one showed in the other).
    tag = re.sub(r"[^A-Za-z0-9_-]+", "_", f"{os.path.basename(args.scenario).split('.')[0]}-{device}-{args.out or 'default'}")
    profile = os.path.join(PROFILE_ROOT, f"balatro-portrait-headless-{tag}")
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    env = dict(os.environ)
    env.update({
        "BPM_HL_OUT": out,
        "BPM_HL_SCENARIO": scenario,
        "BPM_HL_W": str(size[0]),
        "BPM_HL_H": str(size[1]),
        "BPM_HL_DEVICE": device,
        "BPM_HL_TIMEOUT": str(args.timeout),
        "BPM_HL_VISIBLE": "1" if args.visible else "0",
        # OpenAL Soft's null backend: no sound out of the speakers, and no
        # failure on a machine without an audio device.
        "ALSOFT_DRIVERS": "null" if not args.sound else env.get("ALSOFT_DRIVERS", ""),
        "BPM_HL_IDENTITY": os.path.basename(profile),
        "BPM_HL_OS": device_os or "",
        "BPM_HL_INSETS": f"{insets[0]},{insets[1]}" if insets else "",
        "BPM_HL_LANG": args.lang or "",
    })
    if args.gamespeed and args.gamespeed != 1:
        env["BPM_HL_GAMESPEED"] = str(args.gamespeed)
    if args.realtime:
        env["BPM_HL_REALTIME"] = "1"
    # The boot scenario is the one that tests the intro; every other run
    # starts at the title.
    if args.splash or os.path.basename(args.scenario).split(".")[0] == "boot":
        env["BPM_HL_SPLASH"] = "1"

    # Every run starts from an empty profile, so a run left over from the last
    # test cannot turn "New Run" into "Continue". Never the real Balatro save.
    if not args.keep_profile and os.path.isdir(profile):
        shutil.rmtree(profile)

    t0 = time.time()
    lines = [f"\n=== {device} {size[0]}x{size[1]} {device_os or 'Windows'}"
             + (f" insets {insets[0]}/{insets[1]}" if insets else "")
             + (f" lang {args.lang}" if args.lang else "") + f" :: {args.scenario}"]
    log_path = os.path.join(out, "stdout.log")
    cmd = [love_exe, game_dir]
    if args.mods:
        mod_dir = stage_mods(args.mods, tag)
        cmd += ["--mod-dir", mod_dir, "--disable-console"]
        env["BPM_HL_MODS"] = ",".join(args.mods)
        lines[0] += f" mods {','.join(args.mods)}"
    if args.visible:
        with open(log_path, "w", encoding="utf-8", errors="replace") as log:
            try:
                proc = subprocess.run(cmd, env=env, cwd=os.path.dirname(love_exe), stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, timeout=args.timeout + 30)
                code = proc.returncode
                log.write(proc.stdout.decode("utf-8", "replace"))
            except subprocess.TimeoutExpired as e:
                code = -1
                log.write((e.stdout or b"").decode("utf-8", "replace") + "\n[runner] killed: hard timeout\n")
    else:
        slot = _slots.get()
        try:
            with open(log_path, "wb") as log:
                code = _spawn_on_hidden_desktop(cmd, env, os.path.dirname(love_exe), log, args.timeout + 30,
                                                desktop=f"{HIDDEN_DESKTOP}-{slot}")
        finally:
            _slots.put(slot)
        if code == -1:
            with open(log_path, "a", encoding="utf-8") as log:
                log.write("\n[runner] killed: hard timeout\n")
    with open(log_path, encoding="utf-8", errors="replace") as log:
        text = log.read()
    # Profiles are per --out now, so they are not left to pile up; nor are the
    # mod folders, a full copy of every mod per run.
    if not args.keep_profile:
        shutil.rmtree(profile, ignore_errors=True)
        shutil.rmtree(os.path.join(WORK, "moddir", tag), ignore_errors=True)

    report_path = os.path.join(out, "report.json")
    report = None
    if os.path.isfile(report_path):
        with open(report_path, encoding="utf-8") as f:
            report = json.load(f)

    ok = code == 0 and report is not None and report.get("ok")
    checks = report.get("checks", []) if report else []
    passed = sum(1 for c in checks if c.get("ok"))
    issues = len(report.get("issues", [])) if report else 0
    milestones = [m["name"] for m in report.get("milestones", [])] if report else []
    lines.append(f"  {'PASS' if ok else 'FAIL'}  exit={code}  checks {passed}/{len(checks)}  issues {issues}  "
                 f"shots {len(report.get('shots', [])) if report else 0}  {time.time() - t0:.1f}s")
    if report:
        for c in checks:
            if not c.get("ok"):
                lines.append(f"    FAIL {c.get('msg')}")
        if not args.quiet_warnings:
            for w in report.get("warnings", []):
                lines.append(f"    warn {w}")
        for i in report.get("issues", []):
            lines.append(f"    ISSUE {i}")
        for e in report.get("errors", []):
            lines.append("    ERROR " + e.strip().replace("\n", "\n          "))
    else:
        tail = "\n".join(text.strip().splitlines()[-15:])
        lines.append("    no report.json written; last output:\n      " + tail.replace("\n", "\n      "))
    if milestones:
        lines.append("    reached: " + " > ".join(milestones))
    lines.append(f"  -> {os.path.relpath(out, ROOT)}")
    if not (ok and getattr(args, "brief", False)):
        print("\n".join(lines), flush=True)
    return {"device": device, "size": size, "os": device_os or "Windows", "ok": bool(ok), "exit": code,
            "out": os.path.relpath(out, ROOT), "report": report}


def main():
    # Text from the game (a Japanese label in an issue line) must not stop the
    # run on a console that has no such characters.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scenario", default="smoke",
                    help="built-in name (tools/headless/scenarios), a .lua path, a comma list, or 'all'")
    ap.add_argument("--device", default="phone",
                    help=f"one of {', '.join(DEVICES)}, 'all', a comma list, or WxH")
    ap.add_argument("--source", default="src",
                    help="src (default), love (the built Game.love), vanilla (the unmodded game "
                         "from Balatro.exe, a baseline for mod tests), zygisk (the unmodded game "
                         "with the Zygisk module's chunks swapped in) or another src/ folder")
    ap.add_argument("--balatro", metavar="PATH", help="Balatro.exe (default: Steam library guess or $BALATRO_EXE)")
    ap.add_argument("--timeout", type=int, default=400, help="seconds per run (default 400)")
    ap.add_argument("--gamespeed", type=float, default=4,
                    help="game speed during runs (default 4, the game's own fastest setting; 8 drops "
                         "taps; 1 = as a player sees it). Waits in scenarios follow the game clock, "
                         "taps and swipes keep their own pace")
    ap.add_argument("--realtime", action="store_true",
                    help="follow the wall clock instead of stepping time frame by frame (slower)")
    ap.add_argument("--splash", action="store_true", help="play the intro instead of skipping it")
    ap.add_argument("--visible", action="store_true", help="put the window on screen to watch it")
    ap.add_argument("--sound", action="store_true", help="keep audio on")
    ap.add_argument("--os", choices=["auto", "Windows", "Android", "iOS"], default="auto",
                    help="OS the game is told it runs on (default: the device's)")
    ap.add_argument("--lang", help="game language for the run, e.g. de, ru, ja, zh_CN")
    ap.add_argument("--jobs", type=int, default=0,
                    help="devices to run at the same time (default: all of them, up to 8)")
    ap.add_argument("--out", default="", help="subfolder of .headless/out for this run, so runs do not overwrite each other")
    ap.add_argument("--quiet-warnings", action="store_true", help="do not print layout warnings")
    ap.add_argument("--mods", default="",
                    help="comma list of mods from .headless/mods-cache to load through Lovely, e.g. "
                         "smods-26,talisman,jokerdisplay (each run gets a fresh mod folder)")
    ap.add_argument("--keep-profile", action="store_true",
                    help="keep the test profile from the last run instead of starting empty")
    args = ap.parse_args()

    if sys.platform != "win32":
        sys.exit("ERROR: the runner takes LOVE from the Windows Balatro.exe, so it only runs on Windows for now.")

    exe = find_balatro(args.balatro)
    if not exe:
        sys.exit("ERROR: Balatro.exe not found. Pass --balatro PATH or set BALATRO_EXE.")
    die_with_children()

    if args.device == "all":
        devices = list(DEVICES.items())
    else:
        devices = []
        for d in args.device.split(","):
            d = d.strip()
            if d in DEVICES:
                devices.append((d, DEVICES[d]))
            elif "x" in d and all(p.isdigit() for p in d.split("x", 1)):
                w, h = d.split("x", 1)
                devices.append((d, ((int(w), int(h)), "Android" if int(h) > int(w) else None, None)))
            else:
                sys.exit(f"ERROR: unknown device '{d}'")

    love_exe = prepare_engine(exe)
    args.mods = [m.strip() for m in args.mods.split(",") if m.strip()]
    if args.mods:
        love_exe = prepare_lovely_engine(love_exe)
    game_dir = stage_game(args.source, exe)

    # Every (scenario, device) pair is one job in a single pool, so the
    # machine stays busy until the last one ends instead of waiting for the
    # slowest device of each scenario in turn.
    names = []
    for n in args.scenario.split(","):
        n = n.strip()
        names += SUITE if n == "all" else [n]
    jobs = []
    for name in names:
        a = copy.copy(args)
        a.scenario = name
        a.out = os.path.join(args.out, name) if len(names) > 1 else args.out
        # A copy under .headless: LuaJIT's io.open goes through the ANSI file
        # API, which cannot open paths past 260 characters (temp folders get
        # there). One per runner process and scenario, so runs never swap them.
        scenario = os.path.join(STAGE_DIR, f"scenario-{os.getpid()}-{len(jobs)}.lua")
        shutil.copyfile(resolve_scenario(name), scenario)
        jobs += [(a, scenario, d, spec) for d, spec in devices]

    if args.jobs <= 0:
        args.jobs = max(1, min(len(jobs), 8, (os.cpu_count() or 4) // 2))
    for i in range(args.jobs):
        _slots.put(i)
    t0 = time.time()
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: dict(run_one(love_exe, game_dir, j[1], j[2], j[3], j[0]), scenario=j[0].scenario), jobs))

    os.makedirs(os.path.join(OUT_DIR, args.out), exist_ok=True)
    with open(os.path.join(OUT_DIR, args.out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump([{k: v for k, v in r.items() if k != "report"} for r in results], f, indent=2)

    failed = [f"{r['scenario']}/{r['device']}" for r in results if not r["ok"]]
    print(f"\n{len(results) - len(failed)}/{len(results)} runs passed in {time.time() - t0:.0f}s"
          + (f" (failed: {', '.join(failed)})" if failed else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

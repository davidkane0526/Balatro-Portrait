#!/usr/bin/env python3
"""Run the whole test matrix in one pool and say what failed.

    python tools/headless/suite.py            # everything, before a release
    python tools/headless/suite.py --quick    # a few minutes, while working
    python tools/headless/suite.py --jobs 8

Every source, mod set, language, scenario and device is one job in a single
pool, longest first, so the machine stays busy until the last run ends. A run
that passes leaves nothing behind; one that fails keeps its folder under
.headless/out/suite/. The exit code is 0 only when every planned run passed.
"""

import argparse
import concurrent.futures
import os
import shutil
import sys
import time

import run as R

LANGS = ["de", "fr", "nl", "ru", "ja", "zh_CN", "zh_TW", "ko", "es_ES", "es_419", "pt_BR", "it", "pl", "id"]
PHONES = ["narrow", "phone", "iphone-se", "tablet"]
ZYGISK_PHONES = ["narrow", "phone", "tablet"]
LANG_PHONES = ["narrow", "iphone-se", "tablet"]
MOD_SETS = ["smods-26", "smods-1", "smods-26,talisman", "smods-26,jokerdisplay", "smods-26,amulet,cryptid"]
ZYGISK_MOD_SETS = ["smods-26", "smods-26,talisman", "smods-26,amulet,cryptid"]
LANG_SCENARIOS = ["layouts", "stress", "menus", "swipe", "blind_screen"]

# Rough length of a run, to start the long ones first.
WEIGHT = {"run": 10, "layouts": 7, "stress": 7, "mods": 6, "swipe": 5, "menus": 3, "smoke": 2, "haptics": 2, "blind_screen": 3, "crt": 1, "mod_folder": 1, "mod_menus": 1, "keyboard": 1, "stats_crash": 1}


def group(name, scenarios, devices, source="src", mods="", lang=""):
    return {"name": name, "scenarios": scenarios, "devices": devices, "source": source,
            "mods": [m for m in mods.split(",") if m], "lang": lang}


def full_matrix():
    groups = [group("src", R.SUITE, list(R.DEVICES)),
              group("zygisk", R.SUITE, PHONES, source="zygisk")]
    groups += [group("zygisk-" + m, R.SUITE + ["mods"], ZYGISK_PHONES, source="zygisk", mods=m) for m in ZYGISK_MOD_SETS]
    groups += [group(m, R.SUITE + ["mods"], PHONES, mods=m) for m in MOD_SETS]
    groups += [group(lang, LANG_SCENARIOS, LANG_PHONES, lang=lang) for lang in LANGS]
    # Taps on cards: a few sizes, and each language once for the option's label.
    groups += [group("tap", ["tap_tooltip"], PHONES)]
    groups += [group("tap-zygisk", ["tap_tooltip"], ["phone"], source="zygisk")]
    # A sound played many times at once, and one that cannot be opened (#10).
    groups += [group("sound", ["sound_burst"], ["phone"]), group("sound-zygisk", ["sound_burst"], ["phone"], source="zygisk")]
    # #11: a dragged card's description, and Game Over's buttons, on the reporter's screen.
    groups += [group("issue11", ["drag_tooltip", "game_over_buttons"], ["razr"]), group("issue11-zygisk", ["drag_tooltip", "game_over_buttons"], ["razr"], source="zygisk")]
    groups += [group("tap-" + m, ["tap_tooltip"], ["phone"], mods=m) for m in ("smods-26", "smods-26,amulet,cryptid")]
    groups += [group("tap-" + lang, ["tap_tooltip"], ["small"], lang=lang) for lang in LANGS]
    groups += [group("mod_menus", ["mod_menus"], PHONES, mods="smods-26")]
    groups += [group("mod_menus-zygisk", ["mod_menus"], ZYGISK_PHONES, source="zygisk", mods="smods-26", lang="es_ES")]
    groups += [group("mod_menus-" + lang, ["mod_menus"], LANG_PHONES, mods="smods-26", lang=lang) for lang in LANGS]
    return groups


def hunt_matrix():
    # The sweep of every screen for text out of place: read it with audit.py.
    hunt = ["hunt_menus", "hunt_cards", "hunt_run"]
    groups = [group("hunt", hunt, PHONES)]
    groups += [group("hunt-" + lang, hunt, LANG_PHONES, lang=lang) for lang in LANGS]
    groups += [group("hunt-smods-26", hunt, ["narrow", "tablet"], mods="smods-26")]
    groups += [group("hunt-smods-26-" + lang, ["hunt_run"], ["narrow"], mods="smods-26", lang=lang) for lang in ("es_ES", "de", "ru")]
    groups += [group("hunt-sizes", hunt, ["fold", "small", "long"])]
    groups += [group("hunt-sizes-" + lang, hunt, ["fold", "small"], lang=lang) for lang in ("de", "ru", "ja")]
    groups += [group("hunt-states", ["hunt_states", "monkey"], ["narrow", "phone", "iphone-se", "tablet", "fold", "small"])]
    groups += [group("hunt-states-" + m, ["hunt_states", "monkey"], ["narrow"], mods=m) for m in ("smods-26", "smods-26,talisman")]
    groups += [group("hunt-monkey-" + m, ["monkey"], ["phone", "tablet"], mods=m) for m in ("smods-26", "smods-26,amulet,cryptid")]
    groups += [group("hunt-zygisk", ["hunt_states", "monkey"], ["phone"], source="zygisk")]
    return groups


def quick_matrix():
    return [group("src", R.SUITE, ["narrow", "phone", "tablet"]),
            group("zygisk", ["smoke", "menus"], ["phone"], source="zygisk"),
            group("smods-26,talisman", ["menus", "mods"], ["phone"], mods="smods-26,talisman"),
            group("mod_menus-es_ES", ["mod_menus"], ["narrow"], mods="smods-26", lang="es_ES"),
            group("ru", ["menus"], ["narrow"], lang="ru"),
            group("ja", ["menus"], ["narrow"], lang="ja")]


def plan(groups, args):
    jobs = []
    for g in groups:
        for name in g["scenarios"]:
            for device in g["devices"]:
                a = argparse.Namespace(
                    scenario=name, out=os.path.join("suite", g["name"].replace(",", "+"), name),
                    timeout=args.timeout, gamespeed=4, realtime=args.realtime, splash=False, visible=False,
                    sound=False, os="auto", lang=g["lang"], mods=g["mods"], keep_profile=False,
                    quiet_warnings=True, brief=True)
                jobs.append((a, g, device))
    jobs.sort(key=lambda j: -(WEIGHT.get(j[0].scenario, 3) * (2 if j[1]["mods"] else 1)))
    return jobs


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--quick", action="store_true", help="a small matrix instead of the whole one")
    ap.add_argument("--jobs", type=int, default=max(1, min(8, (os.cpu_count() or 4) // 2)),
                    help="games at the same time (default up to 8; more was no faster over a whole run)")
    ap.add_argument("--timeout", type=int, default=400, help="seconds per run (default 400)")
    ap.add_argument("--realtime", action="store_true", help="follow the wall clock (much slower)")
    ap.add_argument("--balatro", metavar="PATH", help="Balatro.exe (default: Steam library guess or $BALATRO_EXE)")
    ap.add_argument("--hunt", action="store_true", help="sweep every screen for text out of place, and keep the reports")
    ap.add_argument("--only", help="only the groups whose name contains this, e.g. zygisk, smods-1 or ru")
    ap.add_argument("--list", action="store_true", help="print the planned runs and stop")
    args = ap.parse_args()

    groups = hunt_matrix() if args.hunt else quick_matrix() if args.quick else full_matrix()
    if args.only:
        groups = [g for g in groups if args.only in g["name"]]
    jobs = plan(groups, args)
    if not jobs:
        sys.exit(f"ERROR: no group matches '{args.only}'")
    if args.list:
        for a, g, device in jobs:
            print(f"{g['name']} {a.scenario} {device}")
        print(f"{len(jobs)} runs")
        return

    exe = R.find_balatro(args.balatro)
    if not exe:
        sys.exit("ERROR: Balatro.exe not found. Pass --balatro PATH or set BALATRO_EXE.")
    R.die_with_children()
    plain = R.prepare_engine(exe)
    lovely = R.prepare_lovely_engine(plain)
    stages = {source: R.stage_game(source, exe) for source in {g["source"] for _, g, _ in jobs}}

    out_root = os.path.join(R.OUT_DIR, "suite")
    shutil.rmtree(out_root, ignore_errors=True)
    scenarios = {}
    for a, _, _ in jobs:
        if a.scenario not in scenarios:
            scenarios[a.scenario] = os.path.join(R.STAGE_DIR, f"scenario-{os.getpid()}-{a.scenario}.lua")
            shutil.copyfile(R.resolve_scenario(a.scenario), scenarios[a.scenario])
    for i in range(args.jobs):
        R._slots.put(i)

    def one(job):
        a, g, device = job
        result = R.run_one(lovely if a.mods else plain, stages[g["source"]], scenarios[a.scenario],
                           device, R.DEVICES[device], a)
        if result["ok"] and not args.hunt:
            shutil.rmtree(os.path.join(R.OUT_DIR, a.out, device), ignore_errors=True)
        return result["ok"]

    t0 = time.time()
    failed = []
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        running = {pool.submit(one, j): j for j in jobs}
        for n, done in enumerate(concurrent.futures.as_completed(running), 1):
            a, g, device = running[done]
            try:
                ok = done.result()
            except Exception as e:  # a run that never reported is a failure, not a skip
                print(f"  {g['name']} {a.scenario} {device}: {e!r}", flush=True)
                ok = False
            if not ok:
                failed.append(f"{g['name']}/{a.scenario}/{device}")
            if n % 25 == 0 or n == len(jobs):
                print(f"  {n}/{len(jobs)} done, {len(failed)} failed, {time.time() - t0:.0f}s", flush=True)

    for path in scenarios.values():
        os.remove(path)
    passed = len(jobs) - len(failed)
    print(f"\n{passed}/{len(jobs)} runs passed in {time.time() - t0:.0f}s")
    if failed:
        print("failed:\n  " + "\n  ".join(sorted(failed)))
        print(f"their folders are under {os.path.relpath(out_root, R.ROOT)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

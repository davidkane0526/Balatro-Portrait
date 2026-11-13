#!/usr/bin/env python3
"""Gather the text audit of a batch of headless runs: what ran out of its panel,
across a panel or into other text, once per screen, with where it was seen.

    python tools/headless/audit.py [folder under .headless/out] [--kind spill,cross]
"""
import argparse
import collections
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", nargs="?", default="suite")
    ap.add_argument("--kind", default="")
    ap.add_argument("--limit", type=int, default=400)
    a = ap.parse_args()
    kinds = set(filter(None, a.kind.split(",")))
    base = os.path.join(ROOT, ".headless", "out", a.folder)
    found = collections.defaultdict(lambda: {"where": set(), "sample": None})
    runs = 0
    for path in glob.glob(os.path.join(base, "**", "report.json"), recursive=True):
        runs += 1
        with open(path, encoding="utf-8", errors="replace") as f:
            try:
                report = json.load(f)
            except ValueError:
                continue
        where = os.path.relpath(os.path.dirname(path), base).replace("\\", "/")
        for note in report.get("audit", []) or []:
            if kinds and note["kind"] not in kinds:
                continue
            tag = re.sub(r"\d+$", "", note["tag"])
            key = (note["kind"], tag, re.sub(r"[\d.,]+", "#", note["text"]))
            found[key]["where"].add(where)
            found[key]["sample"] = note
    print(f"{runs} runs, {len(found)} distinct notes")
    rows = sorted(found.items(), key=lambda kv: (kv[0][0], -len(kv[1]["where"])))
    for key, v in rows[: a.limit]:
        n = v["sample"]
        print(f"{key[0]:9} {key[1]:32.32} {len(v['where']):4}  {n['text'][:34]!r:38} {n['detail'][:44]}  e.g. {sorted(v['where'])[0][:44]}")


if __name__ == "__main__":
    main()

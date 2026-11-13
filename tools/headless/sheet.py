#!/usr/bin/env python3
"""Contact sheet of a run's screenshots, for reviewing a whole scenario at once.

    python tools/headless/sheet.py .headless/out/phone            # -> .headless/out/phone/sheet.png
    python tools/headless/sheet.py .headless/out --across phone,narrow,iphone15
        # one row per screenshot name, one column per device: the same screen side by side

Needs Pillow.
"""

import argparse
import glob
import os
import re
import sys

from PIL import Image, ImageDraw


def _label(img, text):
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, img.width, 18], fill=(0, 0, 0))
    draw.text((4, 3), text, fill=(255, 255, 255))
    return img


def _thumb(path, width):
    im = Image.open(path).convert("RGB")
    h = round(im.height * width / im.width)
    return im.resize((width, h), Image.LANCZOS)


def single(folder, width, cols):
    shots = sorted(glob.glob(os.path.join(folder, "[0-9][0-9]_*.png")))
    if not shots:
        sys.exit(f"no screenshots in {folder}")
    thumbs = [_label(_thumb(p, width), os.path.basename(p)[:-4]) for p in shots]
    h = max(t.height for t in thumbs)
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (width + 6), rows * (h + 6)), (24, 24, 24))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % cols) * (width + 6), (i // cols) * (h + 6)))
    out = os.path.join(folder, "sheet.png")
    sheet.save(out)
    return out


def across(root, devices, width):
    names = {}
    for d in devices:
        for p in glob.glob(os.path.join(root, d, "[0-9][0-9]_*.png")):
            key = re.sub(r"^\d\d_", "", os.path.basename(p)[:-4])
            names.setdefault(key, {})[d] = p
    keys = sorted(names, key=lambda k: min(os.path.basename(p) for p in names[k].values()))
    cells = {}
    row_h = {}
    for k in keys:
        for d in devices:
            if d in names[k]:
                cells[(k, d)] = _label(_thumb(names[k][d], width), f"{d}: {k}")
        row_h[k] = max([c.height for (kk, _), c in cells.items() if kk == k] or [0])
    sheet = Image.new("RGB", (len(devices) * (width + 6), sum(row_h.values()) + 6 * len(keys)), (24, 24, 24))
    y = 0
    for k in keys:
        for j, d in enumerate(devices):
            if (k, d) in cells:
                sheet.paste(cells[(k, d)], (j * (width + 6), y))
        y += row_h[k] + 6
    out = os.path.join(root, "sheet_" + "_".join(devices) + ".png")
    sheet.save(out)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("folder")
    ap.add_argument("--across", help="comma list of device folders under FOLDER")
    ap.add_argument("--width", type=int, default=220)
    ap.add_argument("--cols", type=int, default=6)
    args = ap.parse_args()
    if args.across:
        print(across(args.folder, args.across.split(","), args.width))
    else:
        print(single(args.folder, args.width, args.cols))


if __name__ == "__main__":
    main()

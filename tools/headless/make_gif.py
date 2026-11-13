#!/usr/bin/env python3
"""Turn frames recorded by the harness (record_start / record_stop) into GIFs.

    python tools/headless/make_gif.py .headless/out/showcase/showcase/phone docs/images
    python tools/headless/make_gif.py <run folder> <out folder> --width 300 --clips one_thumb,focus

Each rec_<clip>.txt lists a clip's frames with the time each was drawn; the
frames are played back for exactly as long as they were on screen, so the GIF
moves at the game's own pace. Needs ffmpeg on PATH.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile


def clip_frames(run_dir, clip):
    frames = []
    with open(os.path.join(run_dir, f"rec_{clip}.txt"), encoding="utf-8") as f:
        for line in f:
            name, _, t = line.strip().rpartition(" ")
            if name:
                frames.append((os.path.abspath(os.path.join(run_dir, name)), float(t)))
    frames.sort(key=lambda x: x[1])
    return frames


def make_gif(run_dir, clip, out_path, width, fps):
    frames = clip_frames(run_dir, clip)
    if len(frames) < 2:
        sys.exit(f"ERROR: clip {clip} has {len(frames)} frames")
    with tempfile.TemporaryDirectory() as tmp:
        listing = os.path.join(tmp, "frames.txt")
        with open(listing, "w", encoding="utf-8") as f:
            for (path, t), nxt in zip(frames, frames[1:] + [None]):
                dur = (nxt[1] - t) if nxt else 1.5  # hold the last frame
                f.write(f"file '{path.replace(os.sep, '/')}'\nduration {dur:.4f}\n")
            f.write(f"file '{frames[-1][0].replace(os.sep, '/')}'\n")
        vf = (f"fps={fps},scale={width}:-1:flags=lanczos,split[a][b];"
              "[a]palettegen=max_colors=128:stats_mode=diff[p];"
              "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle")
        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing,
               "-vf", vf, "-loop", "0", out_path]
        subprocess.run(cmd, check=True)
    span = frames[-1][1] - frames[0][1]
    print(f"{clip}: {len(frames)} frames, {span:.1f}s -> {out_path} ({os.path.getsize(out_path) // 1024} KB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--clips", help="comma list (default: every recorded clip)")
    ap.add_argument("--width", type=int, default=300)
    ap.add_argument("--fps", type=int, default=15)
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("ERROR: ffmpeg is not on PATH")
    clips = args.clips.split(",") if args.clips else sorted(
        n[4:-4] for n in os.listdir(args.run_dir) if n.startswith("rec_") and n.endswith(".txt"))
    os.makedirs(args.out_dir, exist_ok=True)
    for clip in clips:
        make_gif(args.run_dir, clip, os.path.join(args.out_dir, f"{clip}.gif"), args.width, args.fps)


if __name__ == "__main__":
    main()

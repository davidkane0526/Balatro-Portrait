"""The patch applier on made-up files: no game needed.

    python tests/patches_test.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import patches  # noqa: E402


def text(*lines):
    return "".join(f"{line}\n" for line in lines).encode()


BASE = text("a", "b", "c", "d", "e", "f", "g", "h", "i", "j")
PATCH = b"""--- a/x.lua
+++ b/x.lua
@@ -3,7 +3,7 @@
 c
 d
 e
-f
+F
 g
 h
 i
"""
WANT = BASE.replace(b"f\n", b"F\n")
hunks = patches.parse_patch(PATCH)


def check(name, got, want):
    if got != want:
        sys.exit(f"FAIL {name}: {got!r} != {want!r}")
    print(f"ok   {name}")


check("Steam copy", patches.game_target({"version.jkr": b"1.0.1o-FULL\n1.0.1o\nPROD_PC_Console"}), "steam")
check("Play copy", patches.game_target({"version.jkr": b"1.0.1o-FULL [M]\n1.0.1o\nPROD_mobile"}), "mobile")

check("exact", patches.apply_hunks(BASE, hunks), (WANT, [], []))

moved = text("new1", "new2") + BASE
check("moved lines", patches.apply_hunks(moved, hunks), (text("new1", "new2") + WANT, [], []))

changed_edge = BASE.replace(b"c\n", b"C\n")
check("context changed at the edge", patches.apply_hunks(changed_edge, hunks),
      (WANT.replace(b"c\n", b"C\n"), [1], []))

changed_core = BASE.replace(b"f\n", b"other\n")
check("the changed line itself differs", patches.apply_hunks(changed_core, hunks), (changed_core, [], [1]))

# Two hunks: the second is found after the first and keeps its drift.
two = patches.parse_patch(b"""@@ -1,2 +1,3 @@
 a
+a2
 b
@@ -9,2 +10,2 @@
 i
-j
+J
""")
check("drift between hunks", patches.apply_hunks(BASE, two)[0],
      text("a", "a2", "b", "c", "d", "e", "f", "g", "h", "i", "J"))

# A repeated block goes to the copy nearest the line the patch names.
repeated = text("x", "y", "z", "m", "x", "y", "z")
near = patches.parse_patch(b"""@@ -5,3 +5,3 @@
 x
-y
+Y
 z
""")
check("nearest of two matches", patches.apply_hunks(repeated, near)[0],
      text("x", "y", "z", "m", "x", "Y", "z"))

no_newline = patches.parse_patch(rb"""@@ -1,2 +1,2 @@
 a
-b
\ No newline at end of file
+B
\ No newline at end of file
""")
check("no newline at the end", patches.apply_hunks(b"a\nb", no_newline)[0], b"a\nB")

print("all passed")

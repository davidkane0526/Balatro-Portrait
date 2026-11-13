# Headless test runner (Windows)

Runs the portrait build on the PC with nobody at the keyboard: no phone, no
emulator, no Steam client, and nothing on your screen. A scenario script plays
the game by touch, takes screenshots and checks the layout; the exit code says
whether it passed.

```sh
python tools/headless/run.py                         # smoke scenario, 412x915 phone
python tools/headless/run.py --device all --jobs 4   # every size in DEVICES, four at a time
python tools/headless/run.py --device 360x780        # any size
python tools/headless/run.py --scenario boot         # just boot to the title
python tools/headless/run.py --scenario my_test.lua  # your own scenario
python tools/headless/run.py --source love           # the built Game.love instead of src/
python tools/headless/run.py --scenario menus --lang de   # one language
python tools/headless/sheet.py .headless/out/phone   # contact sheet of a run's screenshots
python tools/headless/run.py --scenario all --mods smods-26,talisman   # with mods (see below)
python tools/headless/run.py --scenario mods --mods smods-26 --source vanilla  # unmodded game as a baseline
python tools/headless/run.py --scenario all --source zygisk   # the game as the Zygisk module makes it
python tools/headless/suite.py --quick               # 24 runs, about a minute, while working
python tools/headless/suite.py                       # all 574 runs, before a release
python tools/headless/suite.py --only smods-1        # one group of the matrix
```

`--source zygisk` extracts the Play copy from `.headless/play.apk` (or
`$BALATRO_APK`) and swaps conf.lua for the chunk `zygisk/gen_assets.py` embeds in
the module (Readabletro on, CRT kept). That chunk builds the game from the Play
copy on every run, and files of our own are reachable only through the module's
preloads. It tests the Lua side of the module; the native hooks still need a
rooted phone.

Every `screen_check` also measures the open menu's panel against the screen
edges and records an issue when it sits closer than 0.2 tiles to either one.

## Speed

Time follows frames, not the wall clock: each frame is 1/30 s, nothing sleeps,
and the game runs as fast as the machine draws it. Every run gets the same steps,
and taps, swipes and timeouts keep their pace. `--realtime` follows the wall clock
instead, which takes two to four times as long per run. Runs also play at game
speed 4 (the fastest the game's own setting offers; `--gamespeed 1` plays at a
player's pace), waits follow the game clock or wait for the screen to settle, and
the intro is skipped (the `boot` scenario keeps it).

`suite.py` runs every source, mod set, language, scenario and device as one job in
a single pool, longest first. All 574 runs took 28 minutes on a Ryzen 7 7800X3D
with an RTX 3090 and 32 GB of RAM, against 69 for the same matrix one group after
another in real time. A run that passes leaves nothing behind; one that fails keeps
its folder under `.headless/out/suite/`. Each job has its own profile, so parallel
runs never share a save.

Keep `--jobs` at 8 or lower. Each game commits far more memory than its own
process shows, because the graphics driver's share counts too: 8 games reached 68%
of the commit limit on that machine (32 GB of RAM, 16 GB page file), and 14 were no
faster and ran out of memory.

If the runner is killed, Windows ends every game it started.

Built-in scenarios: `boot`, `smoke` (title to a played hand and a discard),
`menus` (every menu from the title), `run` (a bot plays a seeded run through
shop, packs, vouchers, boss blinds and both swipe gestures, then saves,
quits and continues), `layouts` (the three layout styles side by side,
each through a hand, Cash Out and the shop, then switched live), `stress`
(each style with 12 jokers, 6 consumables, a 12-card hand, 8 tags, a long
boss, money in the billions and a naneinf score, through to the shop; with
`--lang` it covers the longest labels and other fonts).

Devices: `phone`, `narrow`, `tall`, `tablet` run the Android code paths;
`iphone-se`, `iphone15`, `iphone-max` the iOS ones with that phone's
safe-area insets; `desktop` is landscape Windows. `--os` overrides it,
`--out NAME` keeps a run in its own folder.

Needs `src/resources` (one `python build.py` run) and a Steam copy of Balatro;
the runner looks in the usual Steam folders, or pass `--balatro PATH`.

## Mods

`--mods a,b,c` loads mods through Lovely: each name is the start of a folder
in `.headless/mods-cache/x/` (one per download: `lovely-win`, `smods-26.1002.0`,
`talisman-v2.7`, ...). The engine copy with Lovely lives in
`.headless/engine-lovely`, so runs without mods stay vanilla, and each run gets
a fresh mod folder in `.headless/moddir/` (Lovely's log and patched files land
there). The `mods` scenario checks Steamodded itself; the others run as usual
with the mods loaded. A mod's first-launch intro is clicked through by
`wait_title`.

## How it stays off screen

- **Engine:** `Balatro.exe` is the LOVE runtime with the game zipped onto its
  end. The runner cuts off the part before the zip and keeps it as
  `.headless/engine/love.exe`, with the game's own DLLs beside it.
- **Desktop:** the game is started on a separate Windows desktop
  (`CreateDesktop`) that is never switched to. Its window, and any error box,
  live there: nothing appears on your screen, in the taskbar or in Alt+Tab, and
  it cannot steal focus. The GPU still renders it, so screenshots are real.
  `--visible` runs it on your desktop instead, to watch.
- **Window size:** the game re-applies its desktop video settings at boot; the
  harness pins every mode change to the size under test.
- **Profile:** saves go to `%APPDATA%\LOVE\balatro-portrait-headless-<scenario>-<device>-<out>`,
  wiped before and after each run (`--keep-profile` keeps it). The real `%APPDATA%\Balatro`
  save is never touched. Steam is stubbed, sound goes to OpenAL's null device
  (`--sound` keeps it), and Jimbo's tutorial is skipped (`BPM_HL_TUTORIAL=1`
  keeps it).

Nothing under `tools/headless/` ends up in a build: the hooks are added to a
staging copy in `.headless/stage/`.

## Output

`.headless/out/<device>/` holds the numbered screenshots, `stdout.log` and
`report.json` (checks, warnings, errors, screen and room size).
`.headless/out/summary.json` lists every device of the last run.

## The game code

`src/` is built from your Balatro copy and the patches, so a fresh checkout
needs `python tools/patches.py apply` (or `python build.py --skip-apk`) before a
run. Edit `src/` as usual, then save the work into both sets:

```powershell
python tools/patches.py make                          # src/ -> patches/portrait/
python tools/patches.py make --game .headless/play.apk # src/ -> patches/portrait-mobile/
python tools/patches.py check                         # the patches still give src/
```

## README clips

The `showcase` scenario plays the clips the README shows and records them at a
fixed step, so a slow capture does not come out as slow motion. Turn the frames
into GIFs with `make_gif.py`:

```powershell
python tools/headless/run.py --scenario showcase --device phone --gamespeed 4 --out showcase
python tools/headless/make_gif.py .headless/out/showcase/phone docs/images --width 260
```

## Writing a scenario

A scenario is plain Lua that runs one step per frame, with the game's globals
(`G`, `love`, ...) and these helpers:

| Helper | |
|---|---|
| `wait(s)`, `frames(n)` | let the game run |
| `wait_until(fn, timeout, label)` | wait for a condition, fail on timeout |
| `wait_state('SELECTING_HAND')`, `wait_stage('RUN')` | wait for a game state / stage |
| `tap(x, y)`, `swipe(x1, y1, x2, y2, s)` | touch input; pixels, or 0..1 of the window |
| `tap_ui{id=..}` / `tap_ui{button=..}` / `tap_ui{text=..}` | wait for that element to settle, then tap it |
| `tap_node(node)`, `find(q)`, `rect(node)` | tap a card or element, look one up |
| `dump_ui()` | log every tappable element on the current screen |
| `check(cond, msg)`, `check_on_screen(q, label)`, `on_screen(node)` | assertions |
| `layout_report(tag)` | warn about visible boxes that poke out of the window |
| `shot(name)` | screenshot |
| `key(k)`, `highlight(area, n)`, `log(...)`, `screen()` | misc |

`layout_report` is a hint, not a verdict: the blind panels hang off the bottom
of the screen on purpose, as in the desktop game.

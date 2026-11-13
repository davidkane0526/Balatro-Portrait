# Reboot plan: Balatro Portrait Mobile 1.0.0

Status 2026-11-03. Source: v2.8.0 (27bf84c), Balatro 1.0.1o-FULL (the newest
build; the free 1.1 update is announced, no date).

## Why a reboot, not a v2.9

1. **The repository ships the game's own code.** `src/` holds full copies of
   35 Balatro Lua files (about 37,000 lines of LocalThunk's code) with the
   portrait changes mixed in; the mod's own work is about 3,600 added lines
   plus `portrait_config.lua`. The LICENSE scope note says so, but publishing
   the code is still redistribution, and it is the most likely reason a host
   takes the repository down. The new repository must hold only our changes.
2. **Balatro 1.1 will break every file at once.** Whole-file copies cannot be
   rebased onto a new game version; patches with context can, and they say
   exactly which hunk no longer applies.
3. **Old account, old links.** The remote, README badges, release links, the
   Termux one-liner and issue links all point at the suspended account.

## 1.0.0 architecture

- **Patches, not copies.** `patches/portrait/*.patch` (unified diffs against
  vanilla 1.0.1o, one per game file) plus new files of our own
  (`portrait_config.lua`, helpers). `build.py` extracts vanilla from the
  player's copy (as today), verifies the game version, applies the patches
  (strict context first, then fuzzy with a report) and packs `Game.love`.
  `tools/make_patches.py` regenerates the patches from a working tree, so
  day-to-day editing stays the same.
- **Game version gate.** `version.jkr` is read before patching; an unknown
  version builds only with `--allow-untested-game`, and the report lists the
  hunks that needed fuzz.
- **The same patch set for every target**: rootless APK, Termux, iOS IPA.
  Zygisk stays its own module.

## Testing (from this session, plus what Hallway already proved)

`tools/headless/run.py` runs the game on the PC on a desktop of its own that
is never shown: Android / iOS code paths, iPhone safe-area insets from
`tests/ios_inset_fixtures.txt`, eight screen sizes, parallel jobs, a fresh
profile per run. Scenarios: `smoke`, `menus`, `run` (a bot plays a seeded run
through shop, packs, vouchers, boss blinds, swipe gestures, save and continue).

To add, ported from Hallway / SH3:

| Hallway tool | For the mod |
|---|---|
| walkthrough.py milestones + `forbid` lines | expected milestone list per scenario; forbid "LONG DT", Lua errors |
| hallway_identity_check.py | screenshot A/B between two builds; a patch refactor must be pixel-identical |
| menu_layout_check.py / aspect_check.py | every text box logged, asserted inside its panel, per language and size |
| localization_test / multilingual_menu_check | all 15 languages through `menus`, key parity, overflow |
| deterministic clock (`--seed`, fixed tick) | fixed dt + seed so screenshots reproduce exactly |
| run_headless.py provenance | `run.json` with the Game.love hash and the patch set hash |
| crash_report.h | crash file with log tail and state, offered for sharing on next launch |
| updates.md | an in-game notice when a newer mod release exists (opt out in Options) |
| ci/release.py, package.py | one `build.py release`: APK, IPA, Zygisk ZIP, SHA256SUMS |
| gpu.yml self-hosted job | the headless suite on every push, screenshots attached to the run |

## Findings so far

From the headless suite (smoke, menus, run, layouts on 8 sizes, Android and
iOS paths). Each becomes an issue in the new repository.

| # | What | Where | State |
|---|---|---|---|
| F1 | On short rooms (tablets, 16:10) Cash Out, and in the shop Next Round, Reroll and the shop's jokers, could not be tapped: those panels rose onto the joker shelf, whose card area is drawn over them and took the taps | game.lua: round_eval, shop, blind_select offsets | fixed on this branch: `portrait_shelf_floor()` keeps their top edge under the shelf |
| F7 | Options > Settings crashed in a landscape window ("attempt to index local 'node' (a boolean value)"): three portrait-only rows were `G.F_PORTRAIT and create_…` without `or nil` | UI_definitions settings_tab | fixed on this branch |
| F8 | On tablets the shop's bottom row (vouchers, packs) was off screen: the F1 floor pushed the panel under a shelf placed for phones | portrait_jokers_y | fixed on this branch: on a short room the shelves start right under the HUD |
| F10 | An overflowed score (naneinf) made the flame intensity infinite, then NaN: solid colour blocks drawn over the HUD counters | button_callbacks flame_handler | fixed on this branch: capped where a score near 1e308 puts it |
| F11 | DynaText applies its width limit only when made, so counters that grow later (money in the billions, naneinf) push their panel off screen | engine/text.lua (vanilla) | worked around in One-Thumb / Focus: counters re-fit as they change |
| F12 | Tags stack up from the joker shelf in one column; past seven on a tablet they ran onto the HUD | add_tag, Tag:remove | fixed on this branch: the rest stack down from the first tag |
| F13 | When a box's content is wider than its maxw the engine lays it out a second time, and on a new box that second pass initialised the elements again: the copies stayed in G.MOVEABLES after the box went. Under a long translation the Classic button bar did this; the copies kept moving the bar and through it the removed hand: crash on the next run (de, fr, ru, ...) | engine/ui.lua calculate_xywh | fixed on this branch; the suite now fails on any element left from a removed box (`leak_check`) |
| F14 | Classic: in fr, ru, id the sort column pushed Play and Discard past the screen edges | UI_definitions create_UIBox_buttons | fixed on this branch: the column is held to the width English needs |
| F15 | With a mod that adds a run-select page (Cryptid), Steamodded forces its own run select, laid out for desktop: SELECTED, Random Deck, Quick Start and Back run off both edges | Steamodded src/utils/run_select.lua | fixed on this branch: as many grid columns as the room fits, preview under the grid, nav bar in two rows (`portrait_hook_smods_run_select`) |
| F16 | Cryptid's game-over patch closes the box it opens after the vanilla "Main Menu" label line; the portrait line (scale 0.7) did not match, so UI_definitions.lua no longer compiled and the game would not start with Cryptid | UI_definitions game over | fixed on this branch: the line is vanilla again, the row sets the size |
| F17 | Portrait puts a speech bubble under its character, where buttons go too: on Cryptid's intro the Next button sat on the bubble's text | card_character.lua add_button | fixed on this branch: the button goes under the bubble |
| F18 | Steamodded's play/discard limit ("Limit: 7") never showed: its patch targets the vanilla button rows | every button bar | fixed on this branch: each bar adds the row |
| F19 | 25 of Steamodded's Lovely patches found nothing to patch in the portrait build (1 on vanilla), the same in v2.8.0 | see `--mods smods-26` lovely log | reviewed one by one: text shaders and the infotip fix apply again (portrait lines made vanilla); card limit counter, blind name, locked-deck text guard, side buttons for modded areas, the mod badge and the hand limit are done in the portrait code; the rest are desktop-only (Steam, Linux, window) or superseded by the portrait code (HUD blind, mobile window, flame shader) |
| F20 | Cryptid's intro took no taps: the frame lock set as the title opens is lifted by an event made before the pause, and Cryptid pauses inside that tenth of a second, so the lock stayed | engine/controller.lua | fixed on this branch: that event runs while paused (`pause_force`) |
| F21 | Cryptid's intro character drawn at half height: bound to ROOM_ATTACH, whose drawn size had not caught up with the portrait room when the intro paused the game | main.lua love.resize | fixed on this branch: ROOM_ATTACH's drawn size follows at once |
| F22 | A tutorial overlay without a room-sized row (Cryptid's) left the top of a tall room undimmed; its gameset panel sat on the speech bubble, its Next on a gameset button | portrait_layouts.lua | fixed on this branch: overlays grown to cover, bubble / panel / button stacked, the character lifted over another box's buttons |
| F23 | With a boss's two debuff lines (and Steamodded's mod badge) the One-Thumb and Focus blind panels ran past the top of the HUD | portrait_layouts.lua | fixed on this branch: the blind's slot keeps room for both |
| F24 | The game sizes a hand's name by its length in bytes (three per character in Japanese / Chinese) and chips / mult by their digits for its own narrow panel: "ストレートフラッシュ" and 99,999,999,999 came out at a third of their size, 6 px | portrait_layouts.lua `fitted` | fixed on this branch: these keep their own size and only shrink to fit their meter |
| F25 | One-Thumb's score line put name, level and both meters on one row; with Dutch or Japanese tiles beside it the chips were 6.6 px at 99,999,999,999 | portrait_layouts.lua | fixed on this branch: the hand's name over its chips x mult, both the full width |
| F26 | The shop's place was worked out against `G.ROOM.T.h`, but the room starts `G.ROOM.T.y` down the screen: on a tablet in Focus the packs were off the bottom | portrait_layouts.lua `portrait_screen_bottom` | fixed on this branch (the harness's button-bar check had the same mistake) |
| F27 | Long labels in narrow rows: "Durchlauf mit Code" pushed Back off a 360 px screen, "MISE INITIALE" widened the blind collection past it, Classic's "Weggooimogelijkheden" shrank to 3 px, a long boss reward shrank "Reward:" with it | UI_definitions.lua | fixed on this branch: two lines, or the header borrows the next column's width |
| F28 | Classic's hand preview grew with a long hand name ("Старшая карта") but stayed where it was aligned at its old width, off the right edge | button_callbacks.lua hand_preview_visibility | fixed on this branch: centred again when its width changes |
| F29 | Steamodded 1.0.0-beta keeps its slot count in `card_limits.total_slots`, not `display_slots`: every card area's counter read "52/nil" | cardarea.lua | fixed on this branch: whichever of the two the installed Steamodded has |
| F30 | The new layouts sized labels for the English pixel font; Russian's Noto draws a line a tenth shorter, so its labels came out under 9 px on an iPhone SE, and "Параметры" / "Сортировать" overflowed their buttons once grown | portrait_layouts.lua | fixed on this branch: labels grown to the English line height, Focus's side and sort buttons widen for a long label |
| F31 | Two runner processes at once shared a test profile per scenario and device: one wiped or re-languaged the other's | tools/headless/run.py | fixed on this branch: a profile per `--out` too, removed after the run |
| F35 | Swipe Only showed Classic's strip in every style: One-Thumb lost Options, the new styles kept their bar's height of empty room, and the panels hung from the wrong hand height | create_UIBox_buttons, portrait_panel_drop | fixed on this branch: each style has its own thin row and `swipe_hand_base_offset`; the room Play and Discard leave goes to the hand (cards 15% larger, `swipe_only.hand_card_scale`), and selecting cards fades in Play / Discard cues beside the counter; the `swipe` scenario covers it |
| F36 | Zygisk ran no mods | zygisk/src/module.cpp | added, experimental: `liblovely` linked into the module, started only when Mods has a mod; `--source zygisk --mods` tests the Lua side, a rooted phone must test the hook |
| F39 | The repository carried 33 of the game's files | src/ | fixed on this branch: `patches/portrait/` (20 unified diffs against 1.0.1o, about 2,900 of the game's lines as context and removals against 37,000) and `tools/patches.py` (apply, make, check, lint). src/ is now built locally and only our own files in it are tracked. `patches/portrait-mobile/` gives the same src/ from the Play copy, so Termux and the Zygisk module need no Steam files and the module carries patches instead of the game. The old git history still holds the game's files: the new repository must start from a fresh history |
| F37 | A style switch with the shop or blind select open left the panel 0.35 too low in every style: `set_screen_positions` puts the hand short of its rest and the panel was placed from there | portrait_reflow_panels | fixed on this branch: the hand goes to `portrait_hand_rest_y()` first; found by Refresh Blinds running 3 px off a tablet in Focus |
| F38 | A menu tall enough to fill the room ran off the bottom: the room starts below the top of the screen, so Cryptid's run setup put Back 3 px past a tablet's edge | portrait_fit_overlay | fixed on this branch: such a menu goes up by what it is over, as far as the top leaves room |
| F9 | On tablets the played cards landed on the resting hand, and the boss's debuff alert drawn over them took card taps while it showed | set_screen_positions, attention_text | fixed on this branch: the stage stops above the hand; alerts never take taps in portrait |
| F2 | Every `love.resize` on Android/iOS calls `love.window.setMode` (via `_force_android_portrait_hints`), which rebuilds the window; 2 s per call on the PC. On a phone: a hitch on every resume / rotation / keyboard | main.lua | open, needs a device check; fix: set the hints once at load |
| F3 | A resize on Android/iOS closes whatever overlay is open (`G.OVERLAY_MENU:remove()`), so coming back from the notification shade drops you out of Options or the Collection | main.lua love.resize | open (code reading), device check |
| F4 | Collection > Enhancements / Seals / Editions: the explanation line is drawn under the panel, on top of the title buttons behind it | UI_definitions overlay_infotip | fixed on this branch: a dark backing in portrait keeps it readable there |
| F5 | Collection > Booster Packs on 360 dp: the panel touches both screen edges | UI_definitions | fixed on this branch, see F32 (first closed as "not a bug", wrongly: measured, it ran past them) |
| F32 | Menus sized for landscape ran off a 20:9 Android screen: the Collection, Editions, Booster Packs and Spectral pages 2 to 7 px past both edges; Run Info, Profile and the Blinds collection 2 to 5 px from them | button_callbacks overlay_menu / change_tab | fixed on this branch: `portrait_fit_overlay` measures each menu as it opens and squeezes frame padding, card rows, then minimum widths until 0.25 is clear on both sides; the suite's `panel_margin_check` records any menu panel under 0.2 from an edge |
| F33 | Under the Zygisk module `require "portrait_layouts"` had nothing to load: the module only swaps chunks the official APK has, and that file is new | zygisk/gen_assets.py | fixed on this branch: every `portrait_*.lua` is folded into conf.lua as a preload; `run.py --source zygisk` stages the game the way the module makes it and runs the suite on it |
| F34 | The suite ran the pixel font only; APKs build with Readabletro by default. Its TypoQuik line is 28% taller, its digits 15% wider: One-Thumb's 99,999,999,999 round score ran 0.31 off the right edge, and on a tablet One-Thumb / Focus's taller HUD pushed the joker shelf onto the play area and score line | portrait_layouts.lua | fixed on this branch: labels and values scaled back to the pixel font's line, the round score held to its column's width; `--source zygisk` (Readabletro on) is part of the regression |
| F6 | Continuing a run saved at blind select prints "ERROR LOADING GAME: Card area 'shop_*' not instantiated" | vanilla game.lua:2314 | vanilla behaviour, harmless |

Checked and fine: every menu reachable from the title on 4 sizes; a full
seeded run by touch (both swipe gestures, shop, joker, booster, voucher,
reroll, sell, boss blind, game over); save, quit to title and Continue
(ante, money and jokers restored); iPhone safe-area insets (SE, 15, Pro Max).

## Layout styles (in game, Options > Settings > Game > Layout)

Applied on the spot, mid-run too (`src/portrait_layouts.lua`). Classic is
unchanged. One-Thumb and Focus follow the same written rules:

- one column: HUD, both shelves, hand, score line and buttons share one width
  and one left edge (`portrait_frame`);
- three text sizes (label, value, and the large numbers the game sizes), no
  text under 9 px in normal play on any tested phone;
- one surface style (dark rounded panel, tiles in the blind colour);
- spare height shared between the shelves and the stage, never one hole.

- **One-Thumb**: short HUD (blind, round score, ante, round, money, Run Info);
  a score line above the hand (hands left, the hand with chips x mult,
  discards left) that stays up while the hand scores; Discard and Play as
  the biggest targets, Options / Rank / Suit under them.
- **Focus**: a full-width HUD read top to bottom: blind and target with Run
  Info / Options, the round score with a bar filling towards the target, the
  hand with chips x mult, the five run stats, with no second copy of the
  hand above the cards; one flat bar under the hand.

Measured by the suite, not by eye: `frame_check` (edges), `overlap_check`
(HUD / shelves / stage / controls), `smallest_text`, `offscreen_check`,
`leak_check`. Labels too long for their tile go on two lines
(`portrait_label_lines`), split at a space or, for one long word, hyphenated;
all 15 languages are run through `stress` and `layouts`.
`layouts` plays each style through a hand, Cash Out and the shop and switches
live; `stress` loads each with 12 jokers over the slot limit, 6 consumables,
a 12-card hand, 8 tags, a long boss, $9,999,999,999, ante 39, round 999,
scores of 99,999,999,999 and naneinf, then plays through the shop.

## Mod support, tested

`run.py --mods` loads mods through Lovely (Windows build) from
`.headless/mods-cache`, each run with a fresh mod folder, never the
player's. `--source vanilla` runs the unmodded game as a baseline, and
`--source <dir>` another src/ (the last release, say). The `mods` scenario
checks that every mod loads, the Mods list fits, and that Steamodded's
play/discard limits show and work in each layout, through to the shop.

| Mods | smoke, menus, run, layouts, stress, mods (narrow + phone) |
|---|---|
| Steamodded 26.1002.0 | all pass |
| Steamodded 1.0.0-beta-1814a | all pass |
| + Talisman 2.7 | all pass (scores to e1000) |
| + JokerDisplay 2.0.8 | all pass |
| + Amulet 3.6.1 + Cryptid 0.5.17d | run, layouts, stress, mods pass; smoke and menus stop at F15 and at Cryptid's grouped collection |

## Release steps

1. New GitHub account / organisation and repository name (owner's decision).
2. Convert `src/` to patches (done: they give `src/` back byte for byte).
3. Fix the findings, pick the UI direction, implement it behind an option.
4. Headless suite green on all devices and languages; a real-phone pass.
5. Tag v1.0.0; release notes that explain the reboot and the new home.

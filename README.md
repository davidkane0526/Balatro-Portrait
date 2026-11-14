# Balatro Portrait

Custom portrait-mode development repository for Balatro, based on the upstream **Balatro Portrait Mobile v1.0.7** source.

## Repository baseline

- Upstream baseline: [LoreanXavier/balatro-portrait-mobile v1.0.7](https://github.com/LoreanXavier/balatro-portrait-mobile/releases/tag/v1.0.7)
- Primary validation device: iPhone 11
- Default branch: `main` only
- The upstream build system, portrait patches, source configuration, tests, tooling, documentation and Readabletro assets are imported.
- Upstream CI workflows are intentionally not copied; this repository will add only the checks needed for this fork.
- Fork development version: `1.0.11`.

## Uploaded iOS game package compatibility

The supplied `Balatro-plus-v1-4-9.ipa` was inspected locally:

| Field | Value |
|---|---|
| iOS app version | `1.0.17` |
| Bundle identifier | `com.playstack.balatroarcade` |
| Internal Balatro version | `1.0.1o` |
| Internal build target | `PROD_mobile` |
| Source layout | Lua files under `Payload/Balatro.app/game/` |

The uploaded IPA is a Balatro+ source variant. It has the same `1.0.1o` / `PROD_mobile` markers, but its collaboration credits and mobile feature flags differ from the upstream vanilla source. The patcher now detects this variant, skips only the UI hunks that are already present, and rebases the mobile feature flags without dropping the newer collaboration entries.

**Local integration verification completed:**
- All 27 mobile patch files apply to the supplied IPA: 33 Lua source files, zero failed or fuzzed hunks.
- The build pipeline extracts resources and localization from `Payload/<app>.app/game/`.
- `Game.love` builds successfully with 310 files (approximately 96 MB).
- All 49 Lua files in the built archive pass syntax parsing.
- An unsigned portrait IPA was built using the pinned vanilla LÖVE iOS shell.

The generated IPA uses bundle ID `org.htf65jud.balatro`, while the uploaded source IPA uses `com.playstack.balatroarcade`. **It installs as a separate app and does not overwrite the source Balatro+ app.** It must be re-signed with Sideloadly or AltStore. Actual installation and gameplay on an iPhone remain to be tested. The IPA and proprietary game files are not committed to this repository.

For a locally owned IPA, the build command is:

```bash
python build.py --balatro /path/to/Balatro.ipa --ios --ios-vanilla --readabletro --keep-crt --skip-apk --force
```

## UI implementation in v1.0.9

- Play and Discard panels are narrower and shorter, with centered content.
- The Sort panel is wider, with wider sort pills.
- The action row is moved slightly lower.
- The Classic top HUD is scaled by 120%, with a screen-width clamp.
- Hand cards are enlarged by 10%, while the usable hand width is tightened to increase overlap.

The first layout pass is committed and has passed patch-application and Lua syntax checks. It still requires visual and interaction testing on the iPhone 11 before being treated as final.

## UI refinements in v1.0.10

- iOS Classic Play/Sort/Discard now uses `action_row_offset_ios = 1.55`, while Swipe Only, Android and nonportrait layouts retain their previous offsets.
- The New Run / Continue / Challenges tabs, deck description, panel and Start Game button are slightly larger. Each size is configurable through `mobile_ui.run_setup_*` values.
- `python tests/ui_layout_test.py` validates parameter constraints. The existing Windows headless runner (`tools/headless/run.py --scenario menus --device iphone15`) can flag clipped menus and text when run with an owned game copy.
- The new size values need real-device screenshot and touch validation before being considered final.

## Chinese font crash fix in v1.0.11

- The mobile patch now selects the already-bundled `GoNotoCJKCore.ttf` for Simplified Chinese. The rendering raster size was reduced from `TILESIZE*7` to `TILESIZE*7/3` and `FONTSCALE` adjusted from `0.12` to `0.36`, keeping the nominal rendered text scale equal (`7*0.12 = (7/3)*0.36`).
- This corrects the reported font raster overflow while preserving Chinese text. The fix is part of the **source patch** so future IPA builds cannot silently drop it.
- An actual iPhone shop test is still necessary to confirm runtime behavior.

## Deferred UI option

- A two-row hand remains a separate optional mode if the single-row layout cannot meet the size target. Preserve selection, dragging, sorting and play/discard behavior.

## Development rules

- Keep exactly one working branch: `main`.
- Do not create additional branches unless explicitly authorized.
- Preserve upstream attribution and license notices.
- Do not commit the Balatro IPA, proprietary game source, or proprietary game assets. Build from a legally owned local game copy.
- Increment the project version and update the changelog whenever a user-facing release change is made.

# Balatro Portrait Zygisk Module

Experimental root-only runtime module for the official Google Play Balatro:
portrait mode, and Lovely / Steamodded mods.

This path does not patch or re-sign the APK. The official app stays installed
with its Play signature, and the module builds the portrait code from the app's
own files when `com.playstack.balatro.android` starts.

## Status

- arm64-v8a only
- Requires root with Zygisk support: Magisk with Zygisk on, or KernelSU /
  APatch with ReZygisk or Zygisk Next
- Targets the official Play package: `com.playstack.balatro.android`
- Does not redistribute Balatro game assets
- Experimental: Play updates may change `liblove.so`/SDL symbols and break hooks,
  or change the game's Lua so the patches no longer fit (see How It Works)

## Build

Requirements:

- Python 3
- CMake + Ninja
- Android NDK r27c or newer (1.0.0 was built with r28b)
- Git
- Rust with rustup (`aarch64-linux-android` is added for you), for Lovely

The module needs no copy of the game to build:

```powershell
cd zygisk
$env:ANDROID_NDK_HOME = "C:\path\to\android-ndk"
.\build_pkg.ps1
```

The script fetches the pinned dependencies into `zygisk/deps/`, applies the
local shadowhook patch, builds all install variants, and writes:

```text
zygisk/dist/balatro_portrait.zip
```

## Install

1. Install the official Google Play Balatro and launch it once.
2. Download `balatro_portrait.zip` from GitHub Releases, or build it locally
   with the command above.
3. Install `balatro_portrait.zip` from your root manager.
4. During install, choose:
   - Readabletro on/off
   - CRT disable on/off
5. Reboot.
6. Launch the official Balatro app.

If your root manager does not provide Magisk's `chooseport` helper, the
installer falls back to reading volume keys directly with `getevent`. If both
methods are unavailable, it uses the default variant: Readabletro on, CRT
disable off.

## Mods

Experimental: the Lua side is tested with `--source zygisk --mods ...` (see
below), the native hook has not run on a phone yet.

Put each mod folder in `/sdcard/BalatroMods/`, then press the module's Action
button in the root manager or reboot. `sync_mods.sh` copies them into
`files/save/ASET/Mods` with the app's owner and label, and removes what you
took out of the drop folder. Lovely's log is in `Mods/lovely/log/`.

Lovely is linked in from its `liblovely` crate. The module starts it on the
first chunk only if that folder holds a mod, resolves the Lua API from
`liblove.so`, and turns mods off (not the game) if a symbol is missing.

## Release Artifact

The release ZIP does not include the game APK, Balatro's packaged assets or its
code. It contains the native Zygisk module, hook support library, our own Lua,
`patches/portrait-mobile/`, and optional Readabletro resources.

## How It Works

- Hooks `luaL_loadbuffer` and `luaL_loadbufferx` in `liblove.so` and swaps
  `conf.lua` for one embedded chunk. `patcher.lua` in it applies
  `patches/portrait-mobile/` to the app's own Lua, once per module or game
  update, and writes the result to `portrait_game/` in the save folder.
- Every other chunk loads from `portrait_game/` when it is there, and goes
  through Lovely when there are mods. Removing the module removes the swap: the
  folder stays behind unused and the game is as shipped.
- The Play game is a separate build with its own touch, save and platform code.
  The patches turn it into the code the mod is tested on, so the module behaves
  like the APK, mods included, and the app's cloud save and Play Games calls are
  not used.
- A Play update that only moves code still applies. One that changes a line the
  patches touch leaves `portrait_game/` empty and the game runs as shipped, with
  the reason in `portrait_patch_error.txt` in the save folder.
- Hooks `Android_JNI_SetOrientation` and calls
  `SDLActivity.setRequestedOrientation(1)` without forwarding the original
  landscape request.
- Preloads `portrait_config`, `portrait_layouts` (files the official APK does
  not have), portrait shaders, and the optional Readabletro files from embedded
  Lua before the game loads.

## Testing Without A Phone

`python tools/headless/run.py --source zygisk --scenario all` stages the Play
copy from `.headless/play.apk` (or `$BALATRO_APK`), swaps in the chunk this
module embeds (Readabletro on, CRT kept), lets it build the game, and runs the
suite on that. It checks the Lua side; the native hooks still need a rooted
phone.

## Why Not Rootless Runtime Injection?

Rootless Android cannot inject into another installed app process or replace
its in-memory Lua chunks without either modifying the APK on disk or using a
debuggable/instrumented target. Modifying the official paid APK requires
re-signing, and the Play build is protected by integrity checks. The rootless
path for normal users is therefore the APK builder in the repository root; this
Zygisk path is the power-user alternative for people who want to keep the
official Play install.

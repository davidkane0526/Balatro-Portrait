# Mod Support

Balatro Portrait Mobile has two Android paths. They use different package names,
so their mod folders are different.

## Path A: Rootless APK builder

The normal path for most players.

- Package name: `com.unofficial.balatro`
- Mod runtime: Lovely is always embedded in Android builds
- Root: not required
- Mod folder: `ASET/Mods/` inside the app storage
- Direct root path:

```text
/data/user/0/com.unofficial.balatro/files/save/ASET/Mods/
```

### Bundle Steamodded at build time (easiest)

Most mods need Steamodded, and the build can fetch and bundle it for you:

```sh
python build.py --steamodded           # the release this build is tested with
python build.py --steamodded latest    # the newest release (may not be tested yet)
python build.py --steamodded <tag>     # a specific release
```

The tested release is the one the headless suite runs against
(`python tools/headless/run.py --scenario all,mods --mods smods-...`); the
README lists which mods were run with it.

It installs itself on the first launch. Restart the game once and Steamodded is
active.

Mods from a build before 1.0.1 were in `game/Mods/`. They move to `ASET/Mods/` by
themselves on the first launch and load from the second.

### Install mods with Balatro Mod Manager

[Balatro Mod Manager for Android](https://github.com/danitsdev/balatro-mod-manager-android)
installs, updates and removes mods from Thunderstore on the phone. Open the game
once, then in the manager pick the Balatro app's folder, the one with `ASET` in it.

### Install mods without root

1. Build and install the APK from `python build.py`.
2. Launch the game once so the folder structure is created.
3. Install [Material Files](https://play.google.com/store/apps/details?id=me.zhanghai.android.files).
4. Material Files menu -> **Add storage...** -> **External storage**.
5. In the Android picker, choose the **Balatro** app and tap **Use this folder**.
6. Open `ASET/Mods/`.
7. Copy mod folders there.
8. Restart Balatro.

This Material Files flow comes from Lovely Mobile Maker's FAQ and avoids root.

### Install mods with root

Copy mod folders to:

```text
/data/user/0/com.unofficial.balatro/files/save/ASET/Mods/
```

## Path B: Experimental Zygisk module

The root-only path for the official Google Play app.

- Package name: `com.playstack.balatro.android`
- Root and Zygisk: required
- APK patching/re-signing: not used
- Current scope: portrait injection, orientation lock, shader/resource payload
- Modding: experimental. Lovely is built into the module and starts when the
  app's Mods folder has mods in it

Put mods in `/sdcard/BalatroMods/`, then press the module's Action button in
the root manager or reboot. The module copies them into the official app's mod
folder with the app's owner and SELinux label (a root file manager does not):

```text
/data/user/0/com.playstack.balatro.android/files/save/ASET/Mods/
```

Lovely's log is in `Mods/lovely/log/` there, and `adb logcat -s BalatroPortrait`
shows whether it started. With an empty folder Lovely never runs.

## Mod folder structure

```text
Mods/
├── Steamodded/
│   ├── src/
│   ├── lovely/
│   └── ...
├── YourMod/
│   └── YourMod.lua
└── lovely/
    └── log/
```

## Troubleshooting

**"I can't see the Balatro app in Add storage."** Launch the game at least once
first. The app list is inside the Android document picker's menu, not the
Material Files sidebar. Pick the right package: `com.unofficial.balatro` for the
rootless builder, `com.playstack.balatro.android` for the Zygisk app.

**"Mods folder doesn't exist."** Launch the game once after installing. The
rootless builder creates `ASET/Mods/` on the first run.

**"Game crashes after adding mods."** Not every PC mod works on Android.
Shader-heavy mods can crash; remove the mod's `resources/shaders/` folder if it
ships desktop shaders. Check `ASET/Mods/lovely/log/` for Lovely logs.

**"Mod doesn't load / game runs vanilla."** Make sure the mod folder is directly
inside `ASET/Mods/`, not nested one level deeper, and that you are on the
rootless builder path.

## Notes

- `build.py` always uses the Lovely base APK for Android.
- iOS builds are vanilla; Lovely is Android-only.
- The Zygisk path keeps the official install intact and is documented separately
  from the rootless Lovely APK path.

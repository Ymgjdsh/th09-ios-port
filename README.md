<p align="center">
  <img src="ios/app-icon/Assets.xcassets/AppIcon.appiconset/Icon-180.png" alt="Touhou 9 icon" width="180">
</p>

# TH09 iOS Port

A cross-platform port of 東方花映塚　～ Phantasmagoria of Flower View 1.50a by Team Shanghai Alice using SDL3 and OpenGL ES.

This is the native iOS target of the Touhou 9 decompilation. The game logic is rebuilt as named C++, the renderer and input layer are shared with the portable branch, and the iOS layer is a small UIKit host around them.

Compared to the portable branch, this branch:

- Supports iOS 14.0 and later on iPhone and iPad
- Includes touch screen controls for the menus and the battlefield (controls see below)
- Uses SDL3 as opposed to SDL2
- Draws gamepad-style controls inside the full-screen game image
- Adds persistent settings, a developer mode and a cheat code

This is a (sometimes) drop-in replacement for the original Touhou 9 binary that plays identically to the original, but is more portable to other platforms outside of Windows. There are a few bugs/incompatibilities though, namely:

- The build needs a Japanese 1.50a data archive and font, so it cannot be built from this repository alone.
- Music is re-encoded to Ogg Vorbis. Decoded lengths and loop points are preserved, but the samples are not bit-identical to the original.
- Text rendering uses the original font through SDL_ttf and is close to, but not guaranteed to be pixel-identical with the Windows version.
- Online play is not implemented.

## Building

### Dependencies

- cmake
- SDL3 and SDL_ttf, pinned by `ios/tools/fetch_deps.sh`
- OpenGL ES 3.0+
- A compiler that supports C++17
- macOS with Xcode 14 or newer

```sh
bash ios/tools/fetch_deps.sh
```

#### Assets

The original game data, music, font and icon are not tracked. Create `ios/assets` from a Japanese 1.50a copy you own:

```sh
python3 ios/tools/prepare_assets.py \
    --game-dir /path/to/japanese-1.50a \
    --font /path/to/msgothic.ttc \
    --output ios/assets
```

This produces `manifest.json`, `th09.dat`, `fonts/` and 19 Ogg tracks, and needs numpy and soundfile. `ios/README.md` lists every input.

#### iOS

```sh
bash ios/build_ios.sh device Release
bash ios/build_ios.sh simulator Debug
```

Signing is disabled by default; the device build is unsigned. Use `-- -DTH09_ENABLE_CODE_SIGNING=ON -DTH09_DEVELOPMENT_TEAM=YOUR_TEAM` to sign through your own Xcode setup.

#### Packaging

```sh
python3 ios/tools/package_ipa.py --app build/ios-device/Release-iphoneos/th09.app
```

The ad-hoc signature is not an Apple distribution authorization, so the IPA still needs a compatible installer or re-signing with your own identity and profile.

## Controls

Keyboard controls are identical to the original game. For touch users:

- Move by dragging on the battlefield, or with the eight-way joystick. Settings choose hybrid, drag-only or joystick-only movement.
- `Z` shoots and charges, `X` is the bomb action, `S` holds slow movement, and the pause icon sends Escape.
- On the menus, swipe to move the cursor and tap to select; tap with two fingers to go back.
- During dialogue, tap to continue and hold to skip.
- The gear icon opens Settings: automatic shooting, movement mode, two-finger slow, double-tap bomb, developer mode, the cheat code `ymgjdsh` and diagnostic log export.

## Todo

- Verify frame pacing, thermal behaviour and long-session stability on physical iOS 14 devices.
- Keep comparing text rendering and audio output against the original Windows build.

## Credits

- The [th09 decompilation](https://github.com/YomotsuHisami/th09), used as a reference for the game logic, structure and naming.

- The earlier [decompilation for th06](https://github.com/GensokyoClub/th06), [th07](https://github.com/GensokyoClub/th07) and [th08](https://github.com/GensokyoClub/th08), used as a source of shared types, file names, source organization and archive formats.

- The eagler-th07 `Touch.cpp` (CC0) touch policy, adapted into `portable/input/TouchController.hpp`.

- KSS for the MIT-licensed th08 codec reference used by the archive decoder.

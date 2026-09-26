# TH09 iOS Port

A cross-platform port of 東方花映塚　～ Phantasmagoria of Flower View 1.50a by Team Shanghai Alice, built on SDL3 and OpenGL ES.

This is the native iOS target of the TH09 portable reconstruction. The game logic is rebuilt as named C++ in `th09_web/cpp/game`, the renderer and input layer are shared through `portable/`, and a small Objective-C++ host in `ios/` supplies the UIKit window, overlay controls, settings and lifecycle handling. No original executable, x86 emulation, browser or WebAssembly runtime is involved when the game runs on a device.

Compared with the browser build it shares sources with, this target:

- Builds an arm64 iOS application supporting iOS 14.0 and later, in either landscape orientation.
- Renders the complete 640×480 playfield on the whole screen and overlays gamepad-style controls inside the game image.
- Provides touch movement by dragging on the playfield or with an eight-way joystick, with selectable movement modes.
- Keeps a persistent settings panel: automatic shooting, movement mode, two-finger slow, double-tap bomb, developer mode, cheat code and diagnostic log export.
- Records saves, configuration and replays atomically under `Documents/TH09`, and pauses on background, audio interruption or any presented sheet.
- Ships performance instrumentation (rendered FPS, logic rate, draw/audio/submit/upload/present milliseconds) that can be exported from Settings.

This is a source-only repository. The original executable, game data, music, the Microsoft font, derived retail resources, icons, signing material and private test reports are not tracked. A runnable app must be assembled locally from files you are legally entitled to use.

There are known limitations and incompatibilities:

- Resource preparation needs a Japanese 1.50a data archive and font, so the build cannot be reproduced from this repository alone.
- Music is re-encoded to Ogg Vorbis. Decoded frame counts, sample rates and loop points are preserved, but the samples are not bit-identical to the original PCM.
- Japanese text uses the original font through SDL_ttf; glyph metrics are close to, but not guaranteed to be pixel-identical to, the Windows renderer.
- Online versus play is not part of this target. Local two-human play, controllers and the original keyboard modes remain available.
- Simulator and diagnostics results are not physical-device acceptance results. See `ios/PORTING_STATUS.md`.

## Building

### Dependencies

- macOS with Xcode 14 or newer and the iOS 16 SDK (the deployment target stays at iOS 14.0)
- CMake 3.24 or newer
- Python 3.10 or newer for resource preparation and packaging
- SDL3 `release-3.2.24` and SDL_ttf `release-3.2.2` with its vendored FreeType, fetched at pinned revisions

```sh
bash ios/tools/fetch_deps.sh
```

The helper clones into `ios/deps` by default and refuses to disturb an existing checkout of a different revision. Set `TH09_DEPS_DIR` to build against a separate dependency tree.

### Private game resources

The ignored `ios/assets` directory is a local build input, not a public asset distribution. Prepare it from a Japanese 1.50a copy and a font you are entitled to use:

```sh
python3 ios/tools/prepare_assets.py \
    --game-dir /private/path/japanese-1.50a \
    --font /private/path/msgothic.ttc \
    --output ios/assets
```

Asset preparation additionally requires `numpy` and `soundfile`. Its inputs include `th09.dat` and `thbgm.dat` from the selected original directory, the manifest-verified extracted `thbgm.fmt`, and the exact original `blend.bin` table; do not approximate that table. The helper generates the CP932 mapping and encodes the private Vorbis tracks while preserving the original PCM lengths and loop metadata. The resulting tree contains `manifest.json`, `th09.dat`, `fonts/` and 19 Ogg tracks. The packager hashes all 23 game resource files and rejects missing or unlisted assets. `TH09_ASSET_DIR` can point at an equivalent tree outside this repository.

Generate the app icon from the original Japanese executable before configuring the project:

```sh
python3 -m pip install pefile Pillow
python3 ios/tools/extract_icon.py --exe /private/path/th09.exe
```

This preserves the original 32×32 icon and produces the iPhone/iPad sizes without redrawing. Generated icons stay in the ignored `ios/app-icon/` directory; `TH09_ICON_CATALOG` can select an equivalent catalog.

### iOS

Run these commands from the repository root:

```sh
bash ios/build_ios.sh device Release
bash ios/build_ios.sh simulator Debug
```

The device default is arm64 and the simulator default is x86_64; set `TH09_IOS_ARCH=arm64` for an Apple Silicon simulator. Useful environment overrides are `TH09_DEPS_DIR`, `TH09_ASSET_DIR`, `TH09_BUILD_DIR`, `TH09_IOS_ARCH` and `TH09_JOBS`. Additional CMake options follow `--`.

Signing is disabled by default, so a successful device build yields an unsigned application. To use a local Xcode signing setup, add `-- -DTH09_ENABLE_CODE_SIGNING=ON -DTH09_DEVELOPMENT_TEAM=YOUR_TEAM`.

### Packaging

`ios/tools/package_ipa.py` copies the device app into a temporary `Payload/th09.app`, applies the requested signature and writes a private JSON report next to the IPA. It refuses simulators, non-arm64 or encrypted executables, a minimum OS other than 14.0, unexpected versions, diagnostics builds, development-harness content, executables/wasm payloads, private keys and asset hash mismatches.

```sh
python3 ios/tools/package_ipa.py --app build/ios-device/Release-iphoneos/th09.app
```

The default ad-hoc signature is not an Apple development or distribution authorization; it needs a compatible installer or re-signing with a suitable identity and profile. For certificate signing, supply `--sign-identity`, `--provisioning-profile` and `--entitlements` with local files. Keep packaged IPAs and their reports private.

### Diagnostics build

`TH09_IOS_SMOKE` is off by default. A diagnostics build uses a separate bundle identifier and a separate output directory:

```sh
TH09_BUILD_DIR=build/ios-smoke bash ios/build_ios.sh simulator Debug -- -DTH09_IOS_SMOKE=ON
```

It is not the game release and the IPA packager rejects it.

## Controls

Keyboard input is identical to the original game: arrow keys move, Z shoots and confirms (hold to charge), X is the bomb/cancel action, Shift is slow movement, Escape pauses and Ctrl skips dialogue.

On iOS the touch layer provides:

- A translucent eight-way joystick on the lower left with a dead zone, plus direct dragging on the playfield. Settings select hybrid, drag-only or joystick-only movement.
- Round Z, X and S buttons on the lower right. Z shoots and charges, X is the bomb action, S holds slow movement.
- Gear and pause icons at the upper right. The gear opens Settings, the pause icon sends Escape.
- Menu and dialogue taps, two-finger slow movement and double-tap bomb, each toggleable where it applies.

Settings currently expose automatic shooting, movement mode, two-finger slow, double-tap bomb, developer mode, the cheat code `ymgjdsh` (which unlocks all story, versus, extra and music records and saves immediately) and diagnostic log export. Game language stays Japanese. The app does not transmit anything automatically.

## Repository layout

- `ios/`: CMake project, UIKit host, overlay controls, diagnostics, smoke driver and build/packaging tools.
- `portable/`: shared SDL/GLES3 renderer, frame cadence, keyboard map and touch controller.
- `th09_web/cpp/`: the game itself (`game/`) and the SDL platform layer (`sdl/`), plus third-party license copies.
- `th09_web/tests/world-snapshot.hpp`: development-harness state comparison used by optional builds.

## 中文速览

本仓库是东方花映塚日文 1.50a 的 iOS 原生移植源码：C++ 游戏逻辑、SDL3/GLES3 渲染层与 UIKit 触控外壳。仓库只包含代码、构建脚本和第三方声明，不含原版 EXE、数据包、音乐、字体、图标、签名材料或测试报告。

构建顺序：`ios/tools/fetch_deps.sh` 取得固定版本的 SDL3 与 SDL_ttf；用 `ios/tools/prepare_assets.py` 从你合法持有的原版日文 1.50a 资源生成 `ios/assets`；用 `ios/tools/extract_icon.py` 从原版 EXE 提取图标；最后执行 `bash ios/build_ios.sh device Release`。更完整的说明见 `ios/README.md`，逐项验证范围和限制见 `ios/PORTING_STATUS.md`。

## Todo

- Verify frame pacing, thermal behaviour and long-session stability on physical iOS 14 hardware.
- Broaden accepted device coverage beyond the current iOS 14 reference device.
- Keep comparing text rendering and audio output against the original Windows build.

## Credits

- The [TH06](https://github.com/GensokyoClub/th06), [TH07](https://github.com/GensokyoClub/th07) and [TH08](https://github.com/GensokyoClub/th08) decompilations, used as references for shared types, file formats, naming and source organisation.
- The eagler-th07 `Touch.cpp` (CC0) touch policy, adapted into `portable/input/TouchController.hpp`.
- KSS for the MIT-licensed TH08 codec reference used while rebuilding archive decoding.
- SDL3, SDL_ttf and FreeType, linked statically; stb_image, stb_vorbis and miniaudio in `portable/sdl/third_party`.

Original game, characters, graphics, dialogue, music and effects belong to Team Shanghai Alice / ZUN. The source code here grants no licence to those assets. Third-party components are listed in `th09_web/THIRD-PARTY-NOTICES.txt` with their licence copies.

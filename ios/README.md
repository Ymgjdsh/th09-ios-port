# TH09 native iOS target

This directory builds an iOS app from the repository's portable TH09 C++/SDL implementation. The application version is **0.1.2, build 3**. The source game's revision is **Japanese 1.50a**; it is not the app's version number.

The intended release is a Japanese, offline game for iOS 14.0 and later, on iPhone and iPad in either landscape orientation. UIKit provides the touch controls and SDL's iOS display callback drives the game. There is no native language switch or online-play service. No Windows executable, emulator, browser, or WebAssembly runtime belongs in the app.

## Status and limits

See `PORTING_STATUS.md` for the current tested build and results. An Xcode project or IPA file alone does not establish that a game is playable or installable. Physical-device acceptance remains separate from simulator evidence:

| Item | Current acceptance status |
| --- | --- |
| Xcode arm64 device build targeting iOS 14.0 | Passed; device Mach-O, resources, original icon and ad-hoc signature checked |
| x86_64 simulator build and launch | Passed with Xcode 14 / iOS 16; see PORTING_STATUS.md |
| Installation on a physical iPad mini 5 (iPad11,1) with iOS 14.1 | Passed through a compatible installer; other devices and OS versions untested |
| Japanese title, menus, fonts, gameplay, all characters/stages | Simulator title and bounded Easy Story passed; all characters/stages remain untested |
| Music loops, sound effects, interruptions, background/resume | Pending |
| Touch movement and simultaneous buttons | Joystick and buttons exercised on the reference device; playfield dragging and the selectable movement modes still need acceptance on 0.1.2 |
| Configuration/score persistence and replay save/load | Simulator readback and 900-frame recording/playback equivalence passed; device acceptance pending |
| Long-session stability, thermal behavior, frame pacing | Pending |

Simulator or diagnostics results must be reported separately from physical-device gameplay acceptance. The IPA packager performs structural, hash, and signature checks only; it does not run the game or certify installation. Update this table only with the actual tested device/OS, build hash, result, and private evidence location.

## Local inputs and dependencies

Run `bash ios/tools/fetch_deps.sh` to prepare the pinned dependency revisions.
It refuses to replace an existing checkout with a different revision. Set
`TH09_DEPS_DIR` to choose a separate dependency directory.

Build on macOS with Xcode, an iOS SDK, CMake 3.24 or newer, and Python 3.10 or newer for the IPA packager. Local source trees must contain these pinned dependencies:

| Dependency | Local folder under TH09_DEPS_DIR | Pin/configuration |
| --- | --- | --- |
| SDL | SDL/ | release-3.2.24, static |
| SDL_ttf | SDL_ttf/ | release-3.2.2, static |
| FreeType | SDL_ttf/external/freetype/ | Vendored revision selected by SDL_ttf's pinned source |

Populate SDL_ttf's vendored FreeType sources as part of dependency preparation. HarfBuzz and PlutoSVG are disabled. Configuration uses local dependencies and does not download sources. The default dependency root is ios/deps; TH09_DEPS_DIR overrides it. Keep dependency licenses and third-party notices with redistributed source or binaries as appropriate.

## Private game resources

The public repository is source-only. It must not contain the original game executable, original data/music, the Microsoft font, derived retail resources, private signing keys, profiles, IPA files, or private test reports. The ignored ios/assets directory is a local build input, not a public asset distribution.

Prepare the asset tree from a Japanese 1.50a copy and font that you are entitled to use:

    python3 ios/tools/prepare_assets.py --game-dir /private/path/japanese-1.50a --font /private/path/msgothic.ttc --output ios/assets

Asset preparation additionally requires numpy and soundfile in that Python environment. Its inputs include th09.dat and thbgm.dat from the selected original directory, the manifest-verified extracted th09_web/reference/assets/thbgm.fmt, and the exact original th09_web/assets/sdl-native/blend.bin table. Restore that original blend table before preparation; do not approximate it. Use the optional --font-tables directory argument when the required table resides outside its default location. The helper generates the CP932 mapping and encodes the private Vorbis tracks while preserving the original PCM lengths and loop metadata. These are preparation prerequisites, not a claim that the assets or resulting app have passed acceptance.

The resulting private input layout is:

    ios/assets/
      manifest.json
      th09.dat
      fonts/cp932.bin
      fonts/blend.bin
      fonts/msgothic.ttc
      music/<19 original track stems>.ogg

The runtime reads the bundled assets directly and keeps writes in Documents. TH09_ASSET_DIR can point to an equivalent private tree outside this repository.

Generate the OGG tracks from the original music and its thbgm.fmt layout. Preserve each decoded PCM frame count, channel count, sample rate, and the original intro/loop positions. Encoding to Vorbis is lossy; correct lengths and loop points do not make its samples bit-identical to the original PCM. The portable audio implementation rejects a track whose decoded frame count differs from the original layout. Japanese text additionally requires the 131072-byte CP932 and blend tables and the privately supplied MS Gothic collection. Do not substitute a font or regenerate lookup tables without checking the resulting text and metrics.

After preparing all resources, generate assets/manifest.json with a files object whose keys are canonical relative paths and whose values are SHA256 strings, or objects with sha256 and optional size fields. A files array of objects with path, sha256, and optional size is also accepted. Exclude manifest.json itself. The packager requires all 23 game resource files, hashes every listed file, and rejects both missing and unlisted assets. Keep provenance, conversion reports, and codec checks outside the asset tree in a private ignored report directory.

## Build

Extract the original Japanese EXE icon before configuring the project:

    python3 -m pip install pefile Pillow
    python3 ios/tools/extract_icon.py --exe /private/path/th09.exe

This preserves the original 32×32 icon and generates the iPhone/iPad app icon
sizes without redrawing. Generated icons stay in the ignored `ios/app-icon/`
directory. `TH09_ICON_CATALOG` can select an equivalent private asset catalog.

Run these commands from the repository root:

    bash ios/build_ios.sh device Release
    bash ios/build_ios.sh simulator Debug

The device default is arm64; the simulator default is x86_64. For an Apple Silicon simulator, set TH09_IOS_ARCH=arm64. The packager still rejects an arm64 simulator binary by checking its Mach-O platform, not just its architecture name. The minimum deployment target remains iOS 14.0.

Use TH09_DEPS_DIR, TH09_ASSET_DIR, TH09_BUILD_DIR, TH09_IOS_ARCH, and TH09_JOBS to select local inputs and outputs. Additional CMake options follow --. The build script prints the expected app location, normally build/ios-device/Release-iphoneos/th09.app or build/ios-simulator/Debug-iphonesimulator/th09.app.

Signing is disabled by default, so a successful device build yields an unsigned application. To use an existing local Xcode signing setup, explicitly enable TH09_ENABLE_CODE_SIGNING and supply your own team settings; no identity, account, key, or provisioning secret is stored in this source tree.

The game and platform source files compile with C++17, disabled floating-point contraction/fast math, no strict aliasing, no C++ exceptions, and no RTTI. SDL and SDL_ttf are linked statically, with Apple system frameworks supplied by the iOS SDK.

## Separate diagnostics build

TH09_IOS_SMOKE is OFF by default. A diagnostics build must use a separate output directory:

    TH09_BUILD_DIR=build/ios-smoke bash ios/build_ios.sh simulator Debug -- -DTH09_IOS_SMOKE=ON

This enables the TH09_IOS_SMOKE=1 compile definition and uses the bundle identifier org.th09.native.smoke, display name TH09 Diagnostics, and diagnostics build flavor. It is not the game release and the IPA packager refuses it. Use a clean release configuration with TH09_IOS_SMOKE=OFF for the org.th09.native package; an existing CMake cache retains explicitly selected options.

## Package an IPA privately

The packager copies the device app into a temporary Payload/th09.app before changing its signature. It refuses simulators, non-arm64 or encrypted executables, a minimum OS other than 14.0, unexpected application versions, diagnostics builds, development harness content, EXE/DLL/WASM payloads, private keys, and asset hash mismatches.

On macOS, create an IPA with the default ad-hoc signature:

    python3 ios/tools/package_ipa.py --app build/ios-device/Release-iphoneos/th09.app

The default output is dist/TH09-iOS-0.1.2.ipa, with a private JSON report in dist/reports. The report includes the IPA SHA256, resource-manifest hash, app metadata, and signing details. The report is created with owner-only file permissions and is not embedded in the IPA. Use --output and --report to select other private paths; use --force only when intentionally replacing an earlier output.

**An ad-hoc signature is not an Apple development or distribution authorization.** It requires a compatible installer or re-signing with a suitable identity and profile. It does not make this IPA universally installable on iOS 14 devices. The correct route depends on the specific device, OS, installer, certificate trust, and provisioning.

For certificate signing, explicitly provide all three local inputs:

    python3 ios/tools/package_ipa.py --app build/ios-device/Release-iphoneos/th09.app --sign-identity 'YOUR_LOCAL_SIGNING_IDENTITY' --provisioning-profile /private/path/profile.mobileprovision --entitlements /private/path/entitlements.plist

The identity must already exist in the local keychain. The profile must be unexpired, cover org.th09.native, and include the chosen signing certificate. Entitlements must use the exact application identifier and permitted team/capabilities. A certificate's presence alone does not establish that there is a usable profile or that a device is authorized. No installation, upload, notarization, or public publishing is performed by this script.

Keep dist, original resources, generated audio/font assets, signing material, device identifiers, provisioning details, and acceptance reports private. A distributable source archive should contain code/build instructions/notices only; it must not include the locally assembled IPA or its original payload.

## Controls and local storage

- The translucent eight-way joystick moves the player and navigates menus. Its dead zone prevents small accidental movements; releasing or cancelling it releases all direction keys.
- Dragging directly on the battle image moves the player as well. Settings choose hybrid (drag and joystick), drag-only or joystick-only movement, and the joystick stays visible in every mode.
- Z provides the original shot/charge key; X provides the original bomb/X action. Their behavior follows the game's current mode.
- S holds the original slow-movement key. The pause icon supplies Escape; the gear icon opens settings.
- Automatic shooting is a toggle in Settings; it starts off and yields to manual Z charging.
- Settings also persist movement mode, two-finger slow movement, double-tap bomb, and developer mode. Entering the cheat code `ymgjdsh` unlocks all story, versus, extra and music records and writes `score.dat` immediately; the game language stays Japanese.
- Multiple held buttons and movement touches are supported by the native input layer; verify simultaneous input on actual devices before acceptance.
- Native touch buttons belong to player one in a local two-human match. Set the
  second player's device to the attached controller in the game's key settings;
  two controllers can retain independent device 0 and device 1 assignments.
- Auto creates repeated shot presses. Holding Z takes priority, and releasing Z
  supplies a release frame before Auto resumes, so charged attacks can fire.

The viewport preserves the game's complete 640×480 image and fills the entire 4:3 iPad screen. The joystick and buttons overlay the game inside its safe area; there is no external controls strip. Wider displays retain the full image without stretching or cropping. The app requests landscape and pauses when inactive. Saves, configuration, and replays are stored under Documents/TH09. Documents is exposed through iOS file sharing. Back up wanted saves before deleting the app.

The **齿轮 → 导出诊断日志** control creates a UTF-8 report under `Documents/Logs` and opens the system share sheet. Choose Save to Files to keep the report, then provide it with a description of the problem. The app does not transmit reports automatically. Reports include the app/source version, device model and system version, current game/render/input state, and current and previous startup logs. Each startup log is capped at 1 MiB; private absolute paths are redacted. Save contents, game assets, device identifiers, and account details are not collected. Settings and sharing pause gameplay; cancelling either sheet releases only that pause reason. The Settings control remains available after a handled fatal game error. If the app exits before its controls appear, retrieve `startup.log` and `previous-startup.log` through file sharing.

Performance samples appear every five seconds with rendered FPS, logic rate, callback/logic/draw/audio milliseconds, draw submission, buffer upload and presentation measurements. These timings are nested: draw includes submission and presentation, and submission includes upload. The iOS renderer replaces each batch's stream storage to avoid synchronization from repeated sub-updates to queued buffers. Original game simulation, geometry and draw order remain unchanged. A fresh device run is required to verify improvement over the 0.1.0 diagnostics report, which measured a battle median near 17 FPS against roughly 60 FPS in menus. The 0.1.2 control changes are not yet part of any device performance result.

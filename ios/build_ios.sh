#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: bash ios/build_ios.sh [device|simulator] [Debug|Release] [-- CMake options...]

Defaults: device, Release. Requires macOS, Xcode, and CMake 3.24+.
Device builds use arm64; simulator builds use x86_64 unless TH09_IOS_ARCH is set.
Signing is disabled by default. An unsigned device app cannot be installed as-is.

Environment overrides:
  TH09_DEPS_DIR    Folder containing SDL/ and SDL_ttf/ (default: ios/deps)
  TH09_ASSET_DIR   Resource tree to bundle under assets/ (default: ios/assets)
  TH09_BUILD_DIR   Xcode build folder (default: build/ios-<platform>)
  TH09_IOS_ARCH    Explicit architecture, e.g. arm64 for an Apple Silicon simulator
  TH09_JOBS        Maximum parallel build jobs

Example:
  bash ios/build_ios.sh simulator Debug
  bash ios/build_ios.sh device Release -- -DTH09_ENABLE_CODE_SIGNING=ON -DTH09_DEVELOPMENT_TEAM=YOUR_TEAM
USAGE
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi

platform=${1:-device}
if (( $# > 0 )); then shift; fi
configuration=${1:-Release}
if (( $# > 0 )); then shift; fi
if [[ ${1:-} == -- ]]; then shift; fi

case "$platform" in
    device|iphoneos) platform=device; sdk=iphoneos; default_arch=arm64 ;;
    simulator|iphonesimulator) platform=simulator; sdk=iphonesimulator; default_arch=x86_64 ;;
    *) printf 'Unknown platform: %s\n' "$platform" >&2; usage >&2; exit 2 ;;
esac
case "$configuration" in
    Debug|Release) ;;
    *) printf 'Configuration must be Debug or Release, got: %s\n' "$configuration" >&2; exit 2 ;;
esac

if [[ $(uname -s) != Darwin ]]; then
    printf 'An iOS app must be built on macOS with Xcode installed.\n' >&2
    exit 1
fi
if ! command -v cmake >/dev/null && [[ -x /Applications/CMake.app/Contents/bin/cmake ]]; then
    export PATH="/Applications/CMake.app/Contents/bin:$PATH"
fi
for command in cmake xcrun xcodebuild; do
    command -v "$command" >/dev/null || { printf 'Missing required tool: %s\n' "$command" >&2; exit 1; }
done
xcrun --sdk "$sdk" --show-sdk-path >/dev/null

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
build_dir=${TH09_BUILD_DIR:-"$project_root/build/ios-$platform"}
deps_dir=${TH09_DEPS_DIR:-"$script_dir/deps"}
asset_dir=${TH09_ASSET_DIR:-"$script_dir/assets"}
architecture=${TH09_IOS_ARCH:-$default_arch}
jobs=${TH09_JOBS:-$(sysctl -n hw.ncpu)}

cmake -S "$script_dir" -B "$build_dir" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DTH09_DEPS_DIR="$deps_dir" \
    -DTH09_ASSET_DIR="$asset_dir" \
    -DTH09_ENABLE_CODE_SIGNING=OFF \
    "$@"
cmake --build "$build_dir" --config "$configuration" --target th09 --parallel "$jobs"
printf 'Built %s/th09.app\n' "$build_dir/$configuration-$sdk"

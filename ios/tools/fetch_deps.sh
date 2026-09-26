#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deps=${TH09_DEPS_DIR:-"$root/deps"}
mkdir -p "$deps"
fetch() {
    local name=$1 revision=$2 tag=$3
    if [[ ! -e "$deps/$name" ]]; then
        git clone --depth 1 --branch "$tag" "https://github.com/libsdl-org/$name.git" "$deps/$name"
    fi
    if [[ $(git -C "$deps/$name" rev-parse HEAD) != "$revision" ]]; then
        printf 'Dependency revision mismatch: %s. Keep existing work and select a new TH09_DEPS_DIR.\n' "$name" >&2
        exit 1
    fi
}
fetch SDL a8589a84226a6202831a3d49ff4edda4acab9acd release-3.2.24
fetch SDL_ttf a1ce3670aec736ecbf0936c43f2f0cc53aa61e5b release-3.2.2
git -C "$deps/SDL_ttf" submodule update --init --depth 1 external/freetype
test "$(git -C "$deps/SDL_ttf/external/freetype" rev-parse HEAD)" = 9973564cfa63763a3e4ac67c09147899539b1e07
printf 'Pinned SDL3, SDL_ttf and FreeType dependencies are ready.\n'

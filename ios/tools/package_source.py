#!/usr/bin/env python3
"""Create a native-port source snapshot without private game assets or builds."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error("Choose a new output name; existing snapshots are not overwritten")

files = []
extensions = {".cpp", ".c", ".h", ".hpp", ".inc", ".mm", ".m", ".py", ".sh", ".ps1", ".mjs", ".md", ".txt", ".plist", ".license"}
for folder in ("ios", "portable", "th09_web/cpp"):
    for path in (root / folder).rglob("*"):
        relative = path.relative_to(root)
        if any(part in {"assets", "app-icon", "deps", "artifacts", "__pycache__", ".cache", "build", "node_modules"} for part in relative.parts):
            continue
        if path.is_file() and not path.is_symlink() and path.suffix.lower() in extensions:
            files.append(path)
files += [root / ".gitignore", root / "th09_web/tests/world-snapshot.hpp"]
manifest = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "x", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, "th09-native-source/" + path.relative_to(root).as_posix())
    archive.writestr("th09-native-source/SOURCE-SHA256.json", json.dumps(manifest, indent=2) + "\n")
    archive.writestr("th09-native-source/README.md", "# TH09 native iOS source snapshot\n\nSee ios/README.md and ios/PORTING_STATUS.md.\n\nThis snapshot contains the full C++ game, shared renderer/input code, native iOS entry point, diagnostics, and build/packaging scripts. Fetch the pinned SDL/SDL_ttf dependencies with ios/tools/fetch_deps.sh. Supply your own private ios/assets tree; original game resources, fonts, generated audio, tools, test logs, credentials and app binaries are excluded. This is the native build source, not the separate Web test environment.\n")
print(json.dumps({"files": len(files), "sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(), "bytes": args.output.stat().st_size}))

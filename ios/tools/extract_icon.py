#!/usr/bin/env python3
"""Extract the Japanese retail EXE icon and generate private iOS AppIcon assets."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import pefile
from PIL import Image

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--exe", type=Path, required=True)
parser.add_argument("--output", type=Path, default=root / "ios/app-icon")
args = parser.parse_args()
exe_hash = hashlib.sha256(args.exe.read_bytes()).hexdigest()
if exe_hash != "10350095bcf95edb59e03bee9849a2dc8a7714b4927ad5909c569c550fce6822":
    parser.error("Expected the Japanese TH09 1.50a executable")
pe = pefile.PE(str(args.exe))
icons, groups = {}, []
for kind in pe.DIRECTORY_ENTRY_RESOURCE.entries:
    if kind.id not in (3, 14):
        continue
    for name in kind.directory.entries:
        entry = name.directory.entries[0].data.struct
        data = pe.get_data(entry.OffsetToData, entry.Size)
        if kind.id == 3:
            icons[name.id] = data
        else:
            groups.append((name.id, data))
if not groups:
    parser.error("No group icon found in EXE")
group_id, group = groups[0]
count = struct.unpack_from("<H", group, 4)[0]
header, body = bytearray(group[:6]), bytearray()
offset = 6 + count * 16
for n in range(count):
    row = group[6 + n * 14:20 + n * 14]
    resource = icons[struct.unpack_from("<H", row, 12)[0]]
    header += row[:12] + struct.pack("<I", offset)
    body += resource
    offset += len(resource)
ico = bytes(header + body)
image = Image.open(io.BytesIO(ico))
source_size = max(image.ico.sizes(), key=lambda s: s[0] * s[1])
source = image.ico.getimage(source_size).convert("RGBA")
args.output.mkdir(parents=True, exist_ok=True)
(args.output / "original.ico").write_bytes(ico)
source.save(args.output / "original.png")
# iOS icons must be opaque. Preserve the original pixels, including their
# palette; only transparent pixels receive the game's black background.
opaque = Image.new("RGBA", source.size, "black")
opaque.alpha_composite(source)
opaque = opaque.convert("RGB")
catalog = args.output / "Assets.xcassets"
appicon = catalog / "AppIcon.appiconset"
appicon.mkdir(parents=True, exist_ok=True)
images = []
for idiom, points, scales in [
    ("iphone", 20, (2, 3)), ("iphone", 29, (2, 3)),
    ("iphone", 40, (2, 3)), ("iphone", 60, (2, 3)),
    ("ipad", 20, (1, 2)), ("ipad", 29, (1, 2)),
    ("ipad", 40, (1, 2)), ("ipad", 76, (1, 2)),
    ("ipad", 83.5, (2,)), ("ios-marketing", 1024, (1,)),
]:
    for scale in scales:
        pixels = int(points * scale)
        name = f"Icon-{pixels}.png"
        opaque.resize((pixels, pixels), Image.Resampling.NEAREST).save(appicon / name)
        images.append({"idiom": idiom, "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
info = {"version": 1, "author": "xcode"}
(catalog / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
(appicon / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
report = {"exeSha256": exe_hash, "groupId": group_id, "sourceSize": source_size,
          "icoSha256": hashlib.sha256(ico).hexdigest(), "scaling": "nearest-neighbor; no redrawing",
          "images": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(appicon.glob("*.png"))}}
(args.output / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))

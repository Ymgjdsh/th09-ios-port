#!/usr/bin/env python3
"""Prepare private Japanese TH09 1.50a resources for the native iOS target."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys


ROOT = Path(__file__).resolve().parents[2]
BLEND_SHA256 = "cd7099994c1d25a9526fba4422c518b38fbb4e7ac9940288adc0c0ddef2106eb"
CP932_SHA256 = "30def450df87f3f0765907e7e9d6873f42b891b394ac7b143952b30a5d514919"
MUSIC_STEMS = {
    "th09_00", "th09_01", "th09_00b", "th09_02", "th07_10_b", "th08_12", "th09_05",
    "th07_09", "th09_07", "th09_10", "th09_13", "th09_08_2", "th09_12", "th09_09",
    "th09_11", "th09_00c", "th09_15", "th09_14", "th09_17",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def encoding_table() -> bytes:
    output = bytearray()
    for code in range(65536):
        encoded = bytes([code]) if code < 256 else bytes([code >> 8, code & 255])
        try:
            decoded = encoded.decode("cp932")
            value = ord(decoded) if len(decoded) == 1 else 0x30FB
        except UnicodeDecodeError:
            value = 0x30FB
        output.extend(struct.pack("<H", value))
    require(hashlib.sha256(output).hexdigest() == CP932_SHA256, "Unexpected CP932 codec mapping")
    return bytes(output)


def copy_resource(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() != destination.resolve():
        shutil.copyfile(source, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--font-tables", type=Path, default=ROOT / "th09_web/assets/sdl-native")
    parser.add_argument("--formats", type=Path, default=ROOT / "th09_web/reference/assets/thbgm.fmt")
    parser.add_argument("--output", type=Path, default=ROOT / "ios/assets")
    parser.add_argument("--report", type=Path, default=ROOT / "verification/ios-assets.json")
    args = parser.parse_args()
    try:
        import numpy as np
        import soundfile as sf
    except ImportError as error:
        raise SystemExit("Asset preparation requires numpy and soundfile in this Python environment") from error

    output = args.output.resolve()
    report_path = args.report.resolve()
    require(not report_path.is_relative_to(output), "Keep the private conversion report outside the asset tree")
    target = json.loads((ROOT / "th09_web/target.json").read_text(encoding="utf-8"))
    archive = json.loads((ROOT / "th09_web/reference/archive-manifest.json").read_text(encoding="utf-8"))
    require(sha256(args.game_dir / "th09.exe") == target["sha256"], "Expected Japanese TH09 1.50a executable")
    require(sha256(args.game_dir / "th09.dat") == archive["sourceSha256"], "Original DAT differs from archive oracle manifest")
    require(archive["target"]["sha256"] == target["sha256"], "Archive manifest target mismatch")
    fmt_reference = next(item for item in archive["resources"] if item["name"] == "thbgm.fmt")
    require(sha256(args.formats) == fmt_reference["sha256"], "Music layout differs from archive oracle manifest")
    blend = args.font_tables / "blend.bin"
    require(blend.stat().st_size == 131072 and sha256(blend) == BLEND_SHA256,
            "Missing or changed original font blend table; restore the private original, do not approximate it")
    require(args.font.read_bytes()[:4] == b"ttcf", "Expected the private MS Gothic TrueType collection")

    formats = args.formats.read_bytes()
    tracks = []
    for at in range(0, len(formats) - 51, 52):
        if not formats[at]:
            break
        name, offset, preload, intro, length = struct.unpack_from("<16sIIII", formats, at)
        name = name.split(b"\0")[0].decode("ascii")
        stem = Path(name).stem
        require(name == stem + ".wav" and stem in MUSIC_STEMS, "Unexpected music resource " + name)
        require(struct.unpack_from("<HHIIHH", formats, at + 32) == (1, 2, 44100, 176400, 4, 16),
                "Unexpected PCM format for " + name)
        require(length > 0 and length % 4 == 0 and 0 <= intro < length and intro % 4 == 0,
                "Invalid PCM length or loop for " + name)
        tracks.append(dict(name=name, stem=stem, offset=offset, preload=preload, intro=intro, length=length))
    require(len(tracks) == 19 and {track["stem"] for track in tracks} == MUSIC_STEMS,
            "Expected all 19 original tracks")
    required = {"th09.dat", "fonts/msgothic.ttc", "fonts/cp932.bin", "fonts/blend.bin"} | {
        "music/" + stem + ".ogg" for stem in MUSIC_STEMS
    }
    if output.exists():
        actual = {path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file()}
        require(not actual - required - {"manifest.json"}, "Asset directory has unexpected files")
    output.mkdir(parents=True, exist_ok=True)
    (output / "music").mkdir(exist_ok=True)
    copy_resource(args.game_dir / "th09.dat", output / "th09.dat")
    copy_resource(args.font, output / "fonts/msgothic.ttc")
    copy_resource(blend, output / "fonts/blend.bin")
    (output / "fonts/cp932.bin").write_bytes(encoding_table())

    conversions = []
    with (args.game_dir / "thbgm.dat").open("rb") as source:
        require(source.read(4) == b"ZWAV", "Expected original ZWAV music archive")
        for number, track in enumerate(tracks, 1):
            source.seek(track["offset"])
            pcm = source.read(track["length"])
            require(len(pcm) == track["length"], "Truncated original PCM track")
            samples = np.frombuffer(pcm, dtype="<i2").reshape(-1, 2)
            destination = output / "music" / (track["stem"] + ".ogg")
            temporary = destination.with_suffix(".ogg.tmp")
            with sf.SoundFile(str(temporary), "w", samplerate=44100, channels=2,
                              subtype="VORBIS", format="OGG", compression_level=0.4) as encoded:
                for start in range(0, len(samples), 16384):
                    encoded.write(samples[start:start + 16384].astype(np.float32) / 32768.0)
            # Decode the complete stream: header-only frame counts are not enough.
            with sf.SoundFile(str(temporary)) as decoded:
                require(decoded.samplerate == 44100 and decoded.channels == 2 and decoded.subtype == "VORBIS",
                        "Encoded track has unexpected format")
                frame_count = sum(len(block) for block in decoded.blocks(blocksize=65536, dtype="int16"))
            require(frame_count == len(samples), "Decoded PCM length changed for " + track["name"])
            temporary.replace(destination)
            conversions.append({
                "name": track["name"], "path": destination.relative_to(output).as_posix(),
                "frames": frame_count, "loopFrame": track["intro"] // 4, "sampleRate": 44100,
                "channels": 2, "codec": "vorbis", "lossless": False,
                "pcmSha256": hashlib.sha256(pcm).hexdigest(), "encodedSha256": sha256(destination),
            })
            print(f"{number}/19 {track['name']}: {frame_count} frames, loop at {track['intro'] // 4}", flush=True)

    files = {name: {"sha256": sha256(output / name), "size": (output / name).stat().st_size}
             for name in sorted(required)}
    manifest = {"schemaVersion": 1, "game": "th09", "sourceVersion": "Japanese 1.50a", "files": files}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    report = {
        "createdAt": datetime.now(timezone.utc).isoformat(), "passed": True,
        "targetSha256": target["sha256"], "archiveSha256": archive["sourceSha256"],
        "bgmArchiveSha256": sha256(args.game_dir / "thbgm.dat"), "formatsSha256": sha256(args.formats),
        "blendSha256": BLEND_SHA256, "fontSha256": sha256(args.font),
        "manifestSha256": sha256(output / "manifest.json"), "files": len(files),
        "numpyVersion": np.__version__, "soundfileVersion": sf.__version__,
        "libsndfileVersion": sf.__libsndfile_version__, "tracks": conversions,
        "scope": "Resource identity and full Vorbis decode/length checks; not gameplay or device acceptance",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "files": len(files), "manifestSha256": report["manifestSha256"]}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration) as error:
        print("Asset preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1) from error

#!/usr/bin/env python3
"""Validate and privately package the native device app; macOS tools are required."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile


VERSION = "0.1.2"
BUILD = "3"
BUNDLE_ID = "org.th09.native"
MINIMUM_OS = 14 << 16
FORBIDDEN_SUFFIXES = {
    ".exe", ".dll", ".wasm", ".p12", ".pfx", ".pem", ".key", ".jks", ".keystore",
    ".dylib", ".framework", ".appex", ".xpc", ".xcarchive", ".dsym",
}
FORBIDDEN_DIRECTORIES = {".git", ".github", "node_modules", "tests", "test-results", "reports", "verification"}
HARNESS_NAME = re.compile(r"(^|[_.-])(harness|probes?|smoke|diagnostics|tests?)([_.-]|$)", re.I)
PRIVATE_KEY = re.compile(rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")
HARNESS_MARKERS = (b"th09_probe_", b"th09_title_open", b"th09_smoke_", b"native-smoke-result.json", b"TH09_IOS_SMOKE", b"TH09_SMOKE_BUILD")
MUSIC_STEMS = {
    "th09_00", "th09_01", "th09_00b", "th09_02", "th07_10_b", "th08_12", "th09_05",
    "th07_09", "th09_07", "th09_10", "th09_13", "th09_08_2", "th09_12", "th09_09",
    "th09_11", "th09_00c", "th09_15", "th09_14", "th09_17",
}
REQUIRED_ASSETS = {"th09.dat", "fonts/msgothic.ttc", "fonts/cp932.bin", "fonts/blend.bin"} | {
    "music/" + stem + ".ogg" for stem in MUSIC_STEMS
}


class PackageError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PackageError(message)


def run(*command: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError as error:
        raise PackageError("Required macOS tool is unavailable: " + command[0]) from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip()
        raise PackageError(Path(command[0]).name + " failed: " + detail) from error


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scan_bundle(app: Path) -> None:
    """Reject extraneous executable formats, private keys, and test payloads."""
    require(not app.is_symlink(), "The app bundle cannot be a symbolic link")
    for path in sorted(app.rglob("*")):
        relative = path.relative_to(app).as_posix()
        require(not path.is_symlink(), "Symbolic links are not allowed in this static app: " + relative)
        require(path.suffix.lower() not in FORBIDDEN_SUFFIXES, "Forbidden bundled file: " + relative)
        require(not any(part.lower() in FORBIDDEN_DIRECTORIES for part in path.relative_to(app).parts),
                "Development directory in app: " + relative)
        require(not HARNESS_NAME.search(path.name), "Test or diagnostics payload in app: " + relative)
        if path.is_dir():
            continue
        require(path.is_file(), "Unsupported filesystem entry: " + relative)
        if path.name.lower().endswith(".mobileprovision"):
            require(relative == "embedded.mobileprovision", "Unexpected provisioning profile: " + relative)
        with path.open("rb") as stream:
            prefix = stream.read(4)
            require(prefix[:2] != b"MZ" and prefix != b"\x00asm", "Non-native executable payload: " + relative)
            stream.seek(0)
            carry = b""
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                block = carry + chunk
                require(not PRIVATE_KEY.search(block), "Private key material detected: " + relative)
                if relative == "th09":
                    require(not any(marker in block for marker in HARNESS_MARKERS),
                            "Development entry point or smoke marker in release executable")
                carry = block[-128:]


def manifest_records(document: object) -> dict[str, tuple[str, int | None]]:
    require(isinstance(document, dict), "Asset manifest must be a JSON object")
    entries = document.get("files")
    require(isinstance(entries, (dict, list)), "Asset manifest requires a files object or array")
    records: dict[str, tuple[str, int | None]] = {}
    source = entries.items() if isinstance(entries, dict) else ((entry.get("path"), entry) for entry in entries if isinstance(entry, dict))
    if isinstance(entries, list):
        require(all(isinstance(entry, dict) for entry in entries), "Invalid asset manifest entry")
    for name, value in source:
        require(isinstance(name, str) and name and "\\" not in name, "Invalid asset path in manifest")
        path = PurePosixPath(name)
        require(not path.is_absolute() and str(path) == name and all(part not in ("", ".", "..") for part in path.parts),
                "Unsafe or non-canonical manifest path: " + name)
        require(":" not in name and name != "manifest.json", "Invalid/self-referencing manifest entry: " + name)
        require(name not in records, "Duplicate manifest path: " + name)
        digest = value.get("sha256") if isinstance(value, dict) else value
        size = value.get("size", value.get("bytes")) if isinstance(value, dict) else None
        require(isinstance(digest, str) and bool(re.fullmatch(r"[0-9a-fA-F]{64}", digest)), "Invalid SHA256 for " + name)
        require(size is None or (type(size) is int and size >= 0), "Invalid byte count for " + name)
        records[name] = (digest.lower(), size)
    require(REQUIRED_ASSETS <= records.keys(), "Required game resources are missing from manifest: " + ", ".join(sorted(REQUIRED_ASSETS - records.keys())))
    return records


def validate_assets(app: Path) -> dict:
    root = app / "assets"
    manifest = root / "manifest.json"
    require(manifest.is_file(), "Missing assets/manifest.json")
    try:
        records = manifest_records(json.loads(manifest.read_text(encoding="utf-8")))
    except (ValueError, UnicodeError) as error:
        raise PackageError("Invalid asset manifest JSON") from error
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file() and path != manifest}
    require(actual == records.keys(), "Asset set differs from manifest; unlisted=" + repr(sorted(actual - records.keys())) + "; missing=" + repr(sorted(records.keys() - actual)))
    total = 0
    for name, (digest, size) in sorted(records.items()):
        path = root.joinpath(*PurePosixPath(name).parts)
        length = path.stat().st_size
        require(size is None or size == length, "Asset byte count mismatch: " + name)
        require(sha256(path) == digest, "Asset SHA256 mismatch: " + name)
        total += length
    return {"files": len(records), "bytes": total, "manifest_sha256": sha256(manifest), "sha256_verified": True}


def validate_macho(executable: Path) -> dict:
    """Check the actual arm64 device load commands, not only Info.plist labels."""
    with executable.open("rb") as stream:
        header = stream.read(32)
        require(len(header) == 32, "Truncated Mach-O header")
        magic, cpu, _, file_type, count, command_bytes, _, _ = struct.unpack("<IiiIIIII", header)
        require(magic == 0xFEEDFACF and cpu == 0x0100000C and file_type == 2,
                "Expected one thin arm64 Mach-O executable; fat, simulator, and non-arm64 binaries are rejected")
        require(0 < command_bytes <= 64 * 1024 * 1024 and count <= command_bytes // 8, "Invalid Mach-O command table")
        commands = stream.read(command_bytes)
    require(len(commands) == command_bytes, "Truncated Mach-O load commands")
    offset = 0
    platforms = []
    minimum_versions = []
    encrypted = False
    for _ in range(count):
        require(offset + 8 <= len(commands), "Truncated Mach-O command")
        kind, size = struct.unpack_from("<II", commands, offset)
        require(size >= 8 and offset + size <= len(commands), "Invalid Mach-O command length")
        if kind == 0x32:  # LC_BUILD_VERSION
            require(size >= 24, "Truncated build-version command")
            platform, minimum = struct.unpack_from("<II", commands, offset + 8)
            platforms.append(platform)
            minimum_versions.append(minimum)
        elif kind == 0x25:  # LC_VERSION_MIN_IPHONEOS, older linker format
            require(size >= 16, "Truncated iOS-version command")
            platforms.append(2)
            minimum_versions.append(struct.unpack_from("<I", commands, offset + 8)[0])
        elif kind in (0x21, 0x2C):  # LC_ENCRYPTION_INFO / LC_ENCRYPTION_INFO_64
            require(size >= 20, "Truncated encryption command")
            encrypted |= struct.unpack_from("<I", commands, offset + 16)[0] != 0
        offset += size
    require(offset == len(commands), "Inconsistent Mach-O command table size")
    require(platforms and all(platform == 2 for platform in platforms), "Executable is not built for physical iOS devices")
    require(all(version == MINIMUM_OS for version in minimum_versions), "Executable minimum iOS version must be exactly 14.0")
    require(not encrypted, "An App Store encrypted executable cannot be repackaged")
    return {"architecture": "arm64", "platform": "iOS device", "minimum_os": "14.0", "encrypted": False}


def validate_app(app: Path) -> dict:
    scan_bundle(app)
    info_file = app / "Info.plist"
    run("plutil", "-lint", str(info_file))
    with info_file.open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Only the production org.th09.native app can be packaged")
    require(info.get("TH09BuildFlavor") == "game", "Diagnostics/smoke builds are not release packages")
    require(info.get("CFBundleShortVersionString") == VERSION and str(info.get("CFBundleVersion")) == BUILD,
            "Expected app version 0.1.2, build 3; game revision 1.50a is separate")
    require(info.get("MinimumOSVersion") in ("14.0", "14.0.0"), "Info.plist minimum iOS version must be 14.0")
    require(info.get("CFBundleExecutable") == "th09", "Unexpected app executable name")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Only an iPhoneOS device bundle can be packaged")
    require(info.get("DTPlatformName", "iphoneos") == "iphoneos", "Simulator platform detected")
    require(info.get("CFBundleDevelopmentRegion") == "ja" and info.get("CFBundleLocalizations") == ["ja"], "Expected Japanese-only bundle metadata")
    require(set(info.get("UIDeviceFamily", [])) == {1, 2}, "Expected iPhone and iPad support")
    fingerprint = info.get("TH09SourceFingerprint", "")
    require(isinstance(fingerprint, str) and bool(re.fullmatch(r"[0-9a-f]{64}", fingerprint)),
            "Missing native source fingerprint")
    require((app / "Assets.car").is_file(), "Missing compiled app icon catalog")
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icon = info.get(key, {}).get("CFBundlePrimaryIcon", {})
        require(icon.get("CFBundleIconName") == "AppIcon" and icon.get("CFBundleIconFiles"),
                "Missing original AppIcon metadata: " + key)
        for stem in icon["CFBundleIconFiles"]:
            require(any(app.glob(stem + "*.png")), "Missing compiled icon image: " + stem)
    require((app / "ThirdPartyNotices.txt").is_file(), "Missing bundled third-party notices")
    executable = app / "th09"
    archs = run("lipo", "-archs", str(executable)).stdout.decode().split()
    require(archs == ["arm64"], "lipo reports unsupported architectures: " + ", ".join(archs))
    binary = validate_macho(executable)
    assets = validate_assets(app)
    return {"bundle_id": BUNDLE_ID, "version": VERSION, "build": BUILD, "source_game_revision": "1.50a", "source_fingerprint": fingerprint, "original_app_icon": True, "binary": binary, "assets": assets}


def load_profile(path: Path) -> dict:
    profile = plistlib.loads(run("security", "cms", "-D", "-i", str(path)).stdout)
    expires = profile.get("ExpirationDate")
    require(isinstance(expires, datetime), "Provisioning profile has no expiration date")
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    require(expires > datetime.now(timezone.utc), "Provisioning profile has expired")
    identifier = profile.get("Entitlements", {}).get("application-identifier", "")
    require(isinstance(identifier, str) and "." in identifier and fnmatch.fnmatchcase(BUNDLE_ID, identifier.split(".", 1)[1]),
            "Provisioning profile does not authorize this bundle identifier")
    return profile


def sign_app(app: Path, identity: str, profile_path: Path | None, entitlements_path: Path | None, work: Path) -> dict:
    embedded = app / "embedded.mobileprovision"
    if identity == "-":
        require(profile_path is None and entitlements_path is None, "Ad-hoc signing does not accept provisioning or entitlement overrides")
        embedded.unlink(missing_ok=True)
        profile = None
    else:
        require(profile_path is not None and entitlements_path is not None,
                "Certificate signing requires explicit --provisioning-profile and --entitlements files")
        profile = load_profile(profile_path)
        with entitlements_path.open("rb") as stream:
            entitlements = plistlib.load(stream)
        require(isinstance(entitlements, dict), "Entitlements must be a plist dictionary")
        allowed = profile.get("Entitlements", {})
        expected_app = allowed.get("application-identifier", "").split(".", 1)[0] + "." + BUNDLE_ID
        require(entitlements.get("application-identifier") == expected_app, "Signing entitlements have the wrong application-identifier")
        require(entitlements.get("com.apple.developer.team-identifier") in profile.get("TeamIdentifier", []), "Signing entitlements have the wrong team identifier")
        for key, requested in entitlements.items():
            require(key in allowed, "Entitlement is not present in the provisioning profile: " + key)
            permitted = allowed[key]
            if isinstance(requested, str) and isinstance(permitted, str):
                valid = fnmatch.fnmatchcase(requested, permitted)
            elif isinstance(requested, list) and isinstance(permitted, list):
                valid = all(any(fnmatch.fnmatchcase(item, candidate) if isinstance(item, str) and isinstance(candidate, str) else item == candidate for candidate in permitted) for item in requested)
            else:
                valid = requested == permitted
            require(valid, "Entitlement exceeds the provisioning profile: " + key)
        shutil.copy2(profile_path, embedded)
    command = ["codesign", "--force", "--sign", identity, "--timestamp=none"]
    if entitlements_path is not None:
        command.extend(["--entitlements", str(entitlements_path)])
    command.append(str(app))
    run(*command)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    details = run("codesign", "--display", "--verbose=4", str(app)).stderr.decode("utf-8", errors="replace")
    signing = {"kind": "ad-hoc" if identity == "-" else "certificate", "codesign_verified": True, "details": details.splitlines()}
    if profile is not None:
        prefix = work / "signing-cert-"
        run("codesign", "--display", "--extract-certificates", str(prefix), str(app))
        certificate = Path(str(prefix) + "0")
        require(certificate.is_file() and certificate.read_bytes() in profile.get("DeveloperCertificates", []),
                "The signing certificate is not authorized by the provisioning profile")
        signing["provisioning"] = {"uuid": profile.get("UUID"), "name": profile.get("Name"), "expires": profile["ExpirationDate"].isoformat(), "device_count": len(profile.get("ProvisionedDevices", [])), "all_devices": bool(profile.get("ProvisionsAllDevices", False)), "certificate_matches_profile": True}
        signing["installation_note"] = "Installation depends on the profile, permitted device, certificate trust, and the chosen deployment method; it is not universal."
    else:
        signing["installation_note"] = "Ad-hoc signature only: requires a compatible installer or re-signing with a suitable identity and provisioning profile. This IPA is not universally installable."
    return signing


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Physical-device th09.app built with TH09_IOS_SMOKE=OFF")
    parser.add_argument("--output", type=Path, default=root / "dist" / ("TH09-iOS-" + VERSION + ".ipa"))
    parser.add_argument("--sign-identity", default="-", help="codesign identity; '-' (default) is an ad-hoc signature only")
    parser.add_argument("--provisioning-profile", type=Path)
    parser.add_argument("--entitlements", type=Path)
    parser.add_argument("--report", type=Path, help="Private report path; default is a reports/ directory beside the IPA")
    parser.add_argument("--force", action="store_true", help="Replace an existing output IPA and report")
    args = parser.parse_args()
    require(sys.platform == "darwin", "Packaging requires macOS with codesign, lipo, and plutil (plus security for certificate signing)")
    source = args.app.expanduser().absolute()
    require(source.is_dir() and source.suffix == ".app" and not source.is_symlink(), "--app must identify a real .app directory")
    output = args.output.expanduser().absolute()
    require(output.suffix.lower() == ".ipa", "--output must have an .ipa extension")
    report = args.report.expanduser().absolute() if args.report else output.parent / "reports" / (output.stem + "-package.json")
    require(output != report and source not in output.parents and source not in report.parents, "Outputs must be outside the source app bundle")
    require(args.force or (not output.exists() and not report.exists()), "Output already exists; use --force to replace it")
    with tempfile.TemporaryDirectory(prefix="th09-package-") as temporary:
        work = Path(temporary)
        payload = work / "Payload"
        payload.mkdir()
        app = payload / "th09.app"
        shutil.copytree(source, app, symlinks=True)
        metadata = validate_app(app)
        metadata["signing"] = sign_app(app, args.sign_identity, args.provisioning_profile, args.entitlements, work)
        # Signing may add only the signature and optional explicitly selected profile.
        scan_bundle(app)
        require(validate_assets(app) == metadata["assets"], "Resources changed during signing")
        output.parent.mkdir(parents=True, exist_ok=True)
        staged_output = work / "package.ipa"
        with zipfile.ZipFile(staged_output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(payload.rglob("*")):
                archive.write(path, path.relative_to(work).as_posix())
        with zipfile.ZipFile(staged_output) as archive:
            require(archive.testzip() is None, "IPA archive integrity check failed")
            require(all(name.startswith("Payload/th09.app/") or name == "Payload/th09.app/" for name in archive.namelist()), "Unexpected archive member")
        metadata["artifact"] = {"name": output.name, "bytes": staged_output.stat().st_size, "sha256": sha256(staged_output)}
        metadata["created_utc"] = datetime.now(timezone.utc).isoformat()
        metadata["runtime_validation"] = "Not performed by this packaging tool. Structural and signature checks are not gameplay or installation tests."
        metadata["privacy"] = "Private local build report. Keep out of the public source repository; the IPA contains separately supplied game assets."
        shutil.copy2(staged_output, output)
        report.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        report.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.chmod(report, 0o600)
    print("IPA: " + str(output))
    print("SHA256: " + metadata["artifact"]["sha256"])
    print("Private report: " + str(report))
    print(metadata["signing"]["installation_note"])
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PackageError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print("Packaging refused: " + str(error), file=sys.stderr)
        raise SystemExit(1)

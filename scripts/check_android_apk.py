#!/usr/bin/env python3
"""Validate an Android APK's metadata, signatures, native payload, and alignment."""
import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = "libskyport_flutter_bridge.so"
REQUIRED_LIBRARIES = {BRIDGE, "libflutter.so", "libapp.so"}


def expected_version(pubspec: Path) -> tuple[str, str]:
    match = re.search(r"(?m)^version:\s*([^\s#]+)", pubspec.read_text())
    if not match:
        raise ValueError(f"No version found in {pubspec}")
    version, separator, code = match.group(1).partition("+")
    if not separator or not re.fullmatch(r"[1-9][0-9]*", code) or int(code) > 2_100_000_000:
        raise ValueError(f"{pubspec} requires an explicit Android versionCode in 1..2100000000")
    return version, code


def check_metadata(application_id: str, version_name: str, version_code: str,
                   expected_name: str, expected_code: str) -> None:
    expected = ("dev.skyport.app", expected_name, expected_code)
    actual = (application_id, version_name, version_code)
    if actual != expected:
        raise ValueError(f"APK metadata {actual} does not match expected {expected}")


def check_elf_load_alignment(data: bytes, name: str = "ELF") -> None:
    if len(data) < 16 or data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError(f"{name}: invalid ELF header")
    bits, endian = data[4], "<" if data[5] == 1 else ">"
    if bits == 1:
        header_format, program_format = endian + "HHIIIIIHHHHHH", endian + "IIIIIIII"
        phoff_index, phentsize_index, phnum_index = 4, 8, 9
    else:
        header_format, program_format = endian + "HHIQQQIHHHHHH", endian + "IIQQQQQQ"
        phoff_index, phentsize_index, phnum_index = 4, 8, 9
    header_size = 16 + struct.calcsize(header_format)
    if len(data) < header_size:
        raise ValueError(f"{name}: truncated ELF header")
    header = struct.unpack_from(header_format, data, 16)
    phoff, phentsize, phnum = header[phoff_index], header[phentsize_index], header[phnum_index]
    required_size = struct.calcsize(program_format)
    if phentsize < required_size or phoff + phentsize * phnum > len(data):
        raise ValueError(f"{name}: invalid program header table")
    loads = 0
    for index in range(phnum):
        entry = struct.unpack_from(program_format, data, phoff + index * phentsize)
        if entry[0] == 1:  # PT_LOAD
            loads += 1
            alignment = entry[-1]
            if alignment < 16384:
                raise ValueError(f"{name}: PT_LOAD alignment {alignment} is below 16384")
    if not loads:
        raise ValueError(f"{name}: no PT_LOAD segments")


def check_native(apk: Path, abi: str, debug: bool = False) -> None:
    prefix = f"lib/{abi}/"
    try:
        with zipfile.ZipFile(apk) as archive:
            names = {name for name in archive.namelist() if name.startswith(prefix)}
            required = REQUIRED_LIBRARIES - {"libapp.so"} if debug else REQUIRED_LIBRARIES
            missing = required - {Path(name).name for name in names}
            if missing:
                raise ValueError(f"APK missing {abi} native libraries: {', '.join(sorted(missing))}")
            if debug and "assets/flutter_assets/kernel_blob.bin" not in archive.namelist():
                raise ValueError("Debug APK missing Dart kernel payload")
            for name in sorted(names):
                if name.endswith(".so"):
                    check_elf_load_alignment(archive.read(name), name)
    except zipfile.BadZipFile as error:
        raise ValueError(f"Not a valid APK/ZIP: {apk}") from error


def find_build_tools(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_dir():
            raise ValueError(f"Build-tools directory does not exist: {path}")
        return path
    for variable in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        sdk = os.environ.get(variable)
        if sdk:
            candidates = sorted((Path(sdk) / "build-tools").glob("*"), reverse=True)
            for candidate in candidates:
                if all((candidate / tool).is_file() for tool in ("zipalign", "apksigner")):
                    return candidate
    raise ValueError("Android build-tools not found; set ANDROID_SDK_ROOT/ANDROID_HOME or pass --build-tools")


def executable(path: str | None, name: str) -> str:
    found = path if path and Path(path).is_file() else shutil.which(path or name)
    if not found:
        raise ValueError(f"Cannot find {name}; pass its path or add it to PATH")
    return found


def run(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--abi", default="arm64-v8a")
    parser.add_argument("--pubspec", type=Path, default=ROOT / "app/pubspec.yaml")
    parser.add_argument("--build-tools", help="Android SDK build-tools directory")
    parser.add_argument("--apkanalyzer", help="apkanalyzer executable (defaults to PATH)")
    parser.add_argument("--debug", action="store_true", help="Check a debug APK's Dart kernel instead of AOT library")
    args = parser.parse_args()
    try:
        apk = args.apk.resolve(strict=True)
        build_tools = find_build_tools(args.build_tools)
        analyzer = executable(args.apkanalyzer, "apkanalyzer")
        expected_name, expected_code = expected_version(args.pubspec)
        application_id = run([analyzer, "manifest", "application-id", str(apk)])
        version_name = run([analyzer, "manifest", "version-name", str(apk)])
        version_code = run([analyzer, "manifest", "version-code", str(apk)])
        check_metadata(application_id, version_name, version_code, expected_name, expected_code)
        check_native(apk, args.abi, args.debug)
        run([str(build_tools / "zipalign"), "-c", "-P", "16", "-v", "4", str(apk)])
        signer = run([str(build_tools / "apksigner"), "verify", "--print-certs", str(apk)])
        fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F:]+)", signer)
        print(f"APK_OK applicationId={application_id} versionName={version_name} versionCode={version_code} abi={args.abi}")
        for index, fingerprint in enumerate(fingerprints, 1):
            print(f"Signer #{index} SHA-256: {fingerprint}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        print(f"APK_CHECK_FAILED: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

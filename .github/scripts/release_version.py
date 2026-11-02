#!/usr/bin/env python3
"""Read the manually committed version+N; require an Android code in 1..2100000000."""
import argparse
from pathlib import Path
import re


_NUMBER = r"(?:0|[1-9][0-9]*)"
_IDENTIFIER = rf"(?:{_NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
_VERSION = rf"{_NUMBER}\.{_NUMBER}\.{_NUMBER}(?:-{_IDENTIFIER}(?:\.{_IDENTIFIER})*)?"
_MAX_BUILD_NUMBER = 2_100_000_000


def release_version(manifest: str, tag: str = "") -> str:
    matches = re.findall(r"^version:[ \t]*([^\s#]+)[ \t]*(?:#.*)?$", manifest, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("Expected exactly one unquoted version in app/pubspec.yaml")
    match = re.fullmatch(rf"({_VERSION})\+([1-9][0-9]*)", matches[0])
    if not match:
        raise ValueError(f"Invalid Flutter version: {matches[0]}")
    build_number = int(match[2])
    if not 0 < build_number <= _MAX_BUILD_NUMBER:
        raise ValueError(f"Android versionCode must be between 1 and {_MAX_BUILD_NUMBER}")
    version = match[1]
    if tag and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match committed version v{version}")
    return version


def _build_number(manifest: str) -> int:
    return int(re.search(r"^version:[ \t]*[^\s#]+\+([0-9]+)", manifest, re.MULTILINE)[1])



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="")
    parser.add_argument("--build-number", action="store_true", help="print Android versionCode instead")
    args = parser.parse_args()
    try:
        manifest = Path("app/pubspec.yaml").read_text()
        version = release_version(manifest, args.tag)
        print(_build_number(manifest) if args.build_number else version)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")

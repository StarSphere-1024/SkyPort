#!/usr/bin/env python3
"""Read the committed Flutter version; never rewrite it for packaging."""
import argparse
from pathlib import Path
import re


_NUMBER = r"(?:0|[1-9][0-9]*)"
_IDENTIFIER = rf"(?:{_NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
_VERSION = rf"{_NUMBER}\.{_NUMBER}\.{_NUMBER}(?:-{_IDENTIFIER}(?:\.{_IDENTIFIER})*)?"


def release_version(manifest: str, tag: str = "") -> str:
    matches = re.findall(r"^version:[ \t]*([^\s#]+)[ \t]*(?:#.*)?$", manifest, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("Expected exactly one unquoted version in app/pubspec.yaml")
    version = matches[0].split("+", 1)[0]
    if not re.fullmatch(rf"{_VERSION}(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", matches[0]):
        raise ValueError(f"Invalid Flutter version: {matches[0]}")
    if tag and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match committed version v{version}")
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="")
    args = parser.parse_args()
    try:
        print(release_version(Path("app/pubspec.yaml").read_text(), args.tag))
    except ValueError as error:
        parser.exit(1, f"{error}\n")

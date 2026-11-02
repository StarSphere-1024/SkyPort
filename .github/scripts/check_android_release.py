#!/usr/bin/env python3
"""Reject Android APK releases that regress versionCode or change signing key."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


_ASSET = re.compile(r"^(?:SkyPort-v.*-android-arm64|SkyPort.*Android.*|Android.*SkyPort.*)\.apk$", re.IGNORECASE)
_PACKAGE = "dev.skyport.app"


def _run(command, env=None):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, env=env).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        raise ValueError(f"Command failed: {command[0]}: {detail}") from error


def _download_asset(gh, repo, asset_id, target):
    try:
        with target.open("wb") as output:
            subprocess.run([gh, "api", f"repos/{repo}/releases/assets/{asset_id}",
                            "--header", "Accept: application/octet-stream"],
                           check=True, stdout=output, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ValueError(f"Cannot download published Android APK asset {asset_id}") from error


def _metadata(apk, analyzer, signer):
    package = _run([analyzer, "manifest", "application-id", str(apk)]).strip()
    raw_code = _run([analyzer, "manifest", "version-code", str(apk)]).strip()
    if not re.fullmatch(r"[1-9][0-9]*", raw_code):
        raise ValueError(f"Invalid APK versionCode: {raw_code!r}")
    code = int(raw_code)
    if code > 2_100_000_000:
        raise ValueError(f"APK versionCode exceeds Android limit: {code}")
    if package != _PACKAGE:
        raise ValueError(f"APK application-id must be {_PACKAGE}, got {package!r}")
    output = _run([signer, "verify", "--print-certs", str(apk)])
    certs = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", output)
    if not certs:
        raise ValueError(f"No signing certificate found in {apk}")
    return code, tuple(sorted(cert.lower().replace(":", "") for cert in certs))


def _releases(gh, repo):
    output = _run([gh, "api", "--paginate", "--slurp", f"repos/{repo}/releases"],
                  env={**os.environ, "GH_TOKEN": os.environ.get("GH_TOKEN", "")})
    try:
        pages = json.loads(output)
        if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise ValueError
        releases = [release for page in pages for release in page]
        if any(not isinstance(release, dict) or not isinstance(release.get("draft"), bool)
               or not isinstance(release.get("assets"), list) for release in releases):
            raise ValueError
        if any(not isinstance(asset, dict) or not isinstance(asset.get("name"), str)
               or not isinstance(asset.get("id"), int)
               for release in releases for asset in release["assets"]):
            raise ValueError
        return releases
    except (TypeError, ValueError, json.JSONDecodeError) as error:
        raise ValueError("GitHub returned invalid release data") from error


def check_android_release(apk, repo=None, apkanalyzer="apkanalyzer", apksigner="apksigner", gh="gh"):
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise ValueError("GH_TOKEN is required")
    repo = repo or os.environ.get("GH_REPO") or os.environ.get("GITHUB_REPOSITORY")
    if not repo or not re.fullmatch(r"[^/]+/[^/]+", repo):
        raise ValueError("Set GH_REPO or GITHUB_REPOSITORY to OWNER/REPO, or pass --repo")
    analyzer = shutil.which(apkanalyzer) if os.path.sep not in apkanalyzer else apkanalyzer
    signer = shutil.which(apksigner) if os.path.sep not in apksigner else apksigner
    if not analyzer or not signer:
        raise ValueError("apkanalyzer and apksigner must be available")
    apk = Path(apk)
    if not apk.is_file():
        raise ValueError(f"Candidate APK does not exist: {apk}")
    candidate_code, candidate_cert = _metadata(apk, analyzer, signer)
    prior_codes, prior_certs = [], []
    with tempfile.TemporaryDirectory() as directory:
        for release in _releases(gh, repo):
            if release.get("draft"):
                continue
            for asset in release.get("assets", []):
                name = asset.get("name", "")
                if not _ASSET.fullmatch(name):
                    continue
                target = Path(directory) / f"{asset['id']}.apk"
                _download_asset(gh, repo, asset["id"], target)
                code, cert = _metadata(target, analyzer, signer)
                prior_codes.append(code)
                prior_certs.append(cert)
    if prior_codes:
        if any(cert != candidate_cert for cert in prior_certs):
            raise ValueError("Android release signing certificate differs from a published APK")
        previous = max(prior_codes)
        if candidate_code <= previous:
            raise ValueError(f"Android versionCode {candidate_code} must exceed published maximum {previous}")
    return candidate_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, help="candidate release APK")
    parser.add_argument("--repo", help="GitHub OWNER/REPO (defaults to GH_REPO/GITHUB_REPOSITORY)")
    parser.add_argument("--apkanalyzer", default="apkanalyzer")
    parser.add_argument("--apksigner", default="apksigner")
    args = parser.parse_args()
    try:
        print(check_android_release(args.apk, args.repo, args.apkanalyzer, args.apksigner))
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()

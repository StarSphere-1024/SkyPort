#!/usr/bin/env python3
"""Install/launch an Android APK, or unpack and exercise a desktop bundle."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time
import zipfile


def run_host(root: Path) -> None:
    executable_name = "skyport.exe" if os.name == "nt" else "skyport"
    library_name = "skyport_flutter_bridge.dll" if os.name == "nt" else "lib/libskyport_flutter_bridge.so"
    executables = [p for p in root.rglob(executable_name)
                   if p.is_file() and not p.is_symlink() and (p.parent / library_name).is_file()]
    if len(executables) != 1:
        raise RuntimeError(f"Expected one bundled {executable_name} with {library_name}, found {executables}")
    executable = executables[0]
    library = executable.parent / library_name
    if os.name != "nt":
        dependencies = subprocess.run(["ldd", str(library)], check=True, capture_output=True, text=True)
        print(dependencies.stdout)
        if "not found" in dependencies.stdout:
            raise RuntimeError("Unresolved bundled Rust bridge dependency")
        executable.chmod(executable.stat().st_mode | 0o111)
    with tempfile.TemporaryDirectory(prefix="skyport-smoke-result-") as directory:
        proof = Path(directory) / "result"
        result = subprocess.run([str(executable), "--kernel-smoke",
                                 f"--kernel-smoke-result={proof}"],
                                cwd=executable.parent, capture_output=True,
                                text=True, timeout=60)
        print(result.stdout)
        print(result.stderr)
        if result.returncode != 0 or not proof.is_file() or proof.read_text().strip() != "SKYPORT_KERNEL_SMOKE_OK":
            raise RuntimeError(f"Packaged host smoke failed with exit {result.returncode}")


def run_android(artifact: Path, device: str) -> None:
    with zipfile.ZipFile(artifact) as archive:
        native = [name for name in archive.namelist()
                  if name.startswith("lib/") and name.endswith("/libskyport_flutter_bridge.so")]
        if not native:
            raise RuntimeError("APK does not contain the Rust bridge")
        for name in native:
            if archive.read(name)[:4] != b"\x7fELF":
                raise RuntimeError(f"Invalid bundled native library: {name}")
    adb = ["adb", "-s", device]
    subprocess.run([*adb, "shell", "am", "force-stop", "dev.skyport.app"], check=True)
    subprocess.run([*adb, "install", "-r", str(artifact)], check=True)
    subprocess.run([*adb, "shell", "am", "start", "-W", "-n",
                    "dev.skyport.app/.MainActivity"], check=True)
    time.sleep(3)
    process = subprocess.run([*adb, "shell", "pidof", "dev.skyport.app"],
                             capture_output=True, text=True, check=True)
    if not process.stdout.strip():
        raise RuntimeError("Android application exited during startup")
    print(f"APK_LAUNCH_SMOKE_OK: device={device}, pid={process.stdout.strip()}, "
          f"bridge={native}; USB I/O and rendered UI require separate verification")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--device", help="ADB serial; required for APK installation")
    args = parser.parse_args()
    artifact = args.artifact.resolve()
    if artifact.suffix.lower() == ".apk":
        if not args.device:
            parser.error("--device is required for APK installation")
        run_android(artifact, args.device)
        return
    if artifact.is_dir():
        run_host(artifact)
        return
    with tempfile.TemporaryDirectory(prefix="skyport-package-") as directory:
        root = Path(directory)
        if artifact.suffix == ".deb":
            subprocess.run(["dpkg-deb", "--extract", str(artifact), str(root)], check=True)
        elif artifact.suffix == ".rpm":
            subprocess.run(["bsdtar", "-xf", str(artifact), "-C", str(root)], check=True)
        elif artifact.suffix.lower() == ".appimage":
            artifact.chmod(artifact.stat().st_mode | 0o111)
            subprocess.run([str(artifact), "--appimage-extract"], cwd=root, check=True, stdout=subprocess.DEVNULL)
        elif artifact.suffix == ".zip":
            with zipfile.ZipFile(artifact) as archive:
                archive.extractall(root)
        else:
            parser.error(f"Unsupported artifact: {artifact}")
        run_host(root)


if __name__ == "__main__":
    main()

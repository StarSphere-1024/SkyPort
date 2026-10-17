#!/usr/bin/env python3
"""Exercise the resolved RPM generator's install stage from either build directory."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class RpmInstallTest(unittest.TestCase):
    def test_staged_payload_survives_rpm_working_directory_change(self):
        with tempfile.TemporaryDirectory(prefix="skyport-rpm-regression-") as directory:
            temporary = Path(directory)
            root = temporary / "staging with spaces"
            root.mkdir()
            program = root / "generate.dart"
            program.write_text("""
import 'dart:convert';
import 'dart:io';
import 'package:flutter_app_packager/src/makers/rpm/make_rpm_config.dart';
void main() {
  final config = MakeRPMConfig(displayName: 'SkyPort', license: 'AGPL-3.0-only');
  stdout.write(jsonEncode({'name': config.appName, ...config.toFilesString()}));
}
""")
            result = subprocess.run(
                [os.environ.get("DART_BIN", "dart"),
                 f"--packages={ROOT / 'app/.dart_tool/package_config.json'}", str(program)],
                cwd=ROOT / "app", check=True, capture_output=True, text=True,
            )
            generated = json.loads(result.stdout)
            name = generated["name"]
            install = generated["SPEC"].split("%install\n", 1)[1].split("\n%post\n", 1)[0]
            staged = root / "BUILD"
            (staged / name / "lib").mkdir(parents=True)
            payload = b"\x00skyport\xff\n"
            (staged / name / name).write_bytes(payload)
            (staged / name / "lib/bridge.so").write_bytes(b"bridge")
            (staged / f"{name}.desktop").write_text(generated["DESKTOP"])
            (staged / f"{name}.png").write_bytes(b"icon")
            (staged / f"{name}.appdata.xml").write_bytes(b"<component/>")
            package_build = staged / "package-version-build"
            package_build.mkdir()
            for index, working_directory in enumerate((staged, package_build)):
                with self.subTest(working_directory=working_directory):
                    destination = temporary / f"destination-{index}"
                    script = install
                    for macro, value in {
                        "%{_topdir}": str(root), "%{buildroot}": str(destination),
                        "%{_bindir}": "/usr/bin", "%{_datadir}": "/usr/share", "%{name}": name,
                    }.items():
                        script = script.replace(macro, value)
                    subprocess.run(["bash", "-e", "-c", script], cwd=working_directory, check=True)
                    self.assertEqual((destination / f"usr/share/{name}/{name}").read_bytes(), payload)
                    self.assertEqual((destination / f"usr/share/{name}/lib/bridge.so").read_bytes(), b"bridge")
                    self.assertEqual((destination / f"usr/share/applications/{name}.desktop").read_text(), generated["DESKTOP"])
                    self.assertEqual((destination / f"usr/share/pixmaps/{name}.png").read_bytes(), b"icon")
                    self.assertEqual((destination / f"usr/share/metainfo/{name}.appdata.xml").read_bytes(), b"<component/>")
                    self.assertEqual(os.readlink(destination / f"usr/bin/{name}"), f"/usr/share/{name}/{name}")


if __name__ == "__main__":
    unittest.main()

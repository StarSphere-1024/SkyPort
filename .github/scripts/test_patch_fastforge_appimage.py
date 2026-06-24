#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("patch_fastforge_appimage.py")
SPEC = importlib.util.spec_from_file_location("patch_fastforge_appimage", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


CONFIG_FIXTURE = """
    final fields = {
      'Exec': 'LD_LIBRARY_PATH=usr/lib $appName %u',
    };
    final actionFields = {
      'Exec':
            'LD_LIBRARY_PATH=usr/lib $appName ${action.arguments.join(' ')} %u',
    };
  String get appRunContent {
    return '''
#!/bin/bash

cd "$(dirname "$0")"
export LD_LIBRARY_PATH=usr/lib
exec ./$appName
''';
  }
"""

MAKER_FIXTURE = """import 'dart:io';

import 'package:flutter_app_packager/src/api/app_package_maker.dart';
import 'package:flutter_app_packager/src/makers/appimage/make_appimage_config.dart';
import 'package:path/path.dart' as path;
import 'package:shell_executor/shell_executor.dart';

class AppPackageMakerAppImage extends AppPackageMaker {
  Future<MakeResult> _make(
    Directory appDirectory, {
    required Directory outputDirectory,
    required MakeAppImageConfig makeConfig,
  }) async {
    final referencedSharedLibs =
              await _getSharedDependencies(so.path).then(
            (d) => d.difference(libFlutterGtkDeps)
              ..removeWhere(
                (lib) => lib.contains('libflutter_linux_gtk.so'),
              ),
          );

      var outputMakeConfig = MakeConfig().copyWith(makeConfig)
        ..packageFormat = 'AppImage';

    await $(
      'appimagetool',
      [
        '--no-appstream',
      ],
      environment: {
        'ARCH': 'x86_64',
      },
    );
  }
}
"""


class PatchFastforgeAppImageTest(unittest.TestCase):
    def test_config_removes_ld_library_path(self) -> None:
        patched = MODULE.patch_config_text(CONFIG_FIXTURE)

        self.assertNotIn("LD_LIBRARY_PATH", patched)
        self.assertIn("'Exec': '$appName %u'", patched)
        self.assertIn("'$appName ${action.arguments.join(' ')} %u'", patched)

    def test_maker_filters_host_graphics_and_runtime_libraries(self) -> None:
        patched = MODULE.patch_maker_text(MAKER_FIXTURE)

        self.assertIn("bool _usesHostSharedObject(String libPath)", patched)
        self.assertIn("'libstdc++.so.6'", patched)
        self.assertIn("'libgcc_s.so.1'", patched)
        self.assertIn("'libEGL.so'", patched)
        self.assertIn("'libGL.so'", patched)
        self.assertIn("'libGLESv2.so'", patched)
        self.assertIn("'libgbm.so'", patched)
        self.assertIn("'libdrm.so'", patched)
        self.assertIn("_usesHostSharedObject(lib)", patched)
        self.assertIn("usrLibDirectory.listSync()", patched)
        self.assertIn("entity.deleteSync();", patched)
        self.assertIn("Platform.environment['ARCH'] ?? 'x86_64'", patched)

    def test_patch_paths_updates_explicit_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "make_appimage_config.dart"
            maker = Path(tmp) / "app_package_maker_appimage.dart"
            config.write_text(CONFIG_FIXTURE)
            maker.write_text(MAKER_FIXTURE)

            changed = MODULE.patch_paths([config, maker])

            self.assertEqual(changed, 2)
            self.assertNotIn("LD_LIBRARY_PATH", config.read_text())
            self.assertIn("_usesHostSharedObject", maker.read_text())


if __name__ == "__main__":
    unittest.main()

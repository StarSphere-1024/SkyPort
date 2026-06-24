#!/usr/bin/env python3
"""Patch fastforge's AppImage maker for SkyPort release builds.

fastforge/flutter_app_packager copies plugin dependencies into AppDir/usr/lib and
its generated AppRun prepends that directory to LD_LIBRARY_PATH. On Fedora this
lets bundled C++ runtime libraries override the host Mesa/EGL driver stack, which
can crash Flutter before the first window is shown.
"""

from __future__ import annotations

import sys
from pathlib import Path

HOST_PROVIDED_SHARED_OBJECT_NAMES = (
    "libstdc++.so.6",
    "libgcc_s.so.1",
)

HOST_PROVIDED_SHARED_OBJECT_PREFIXES = (
    "libEGL.so",
    "libGL.so",
    "libGLESv1_CM.so",
    "libGLESv2.so",
    "libgbm.so",
    "libdrm.so",
)

CONFIG_REPLACEMENTS = {
    "'Exec': 'LD_LIBRARY_PATH=usr/lib $appName %u'": "'Exec': '$appName %u'",
    "'LD_LIBRARY_PATH=usr/lib $appName ${action.arguments.join(' ')} %u'": (
        "'$appName ${action.arguments.join(' ')} %u'"
    ),
    "export LD_LIBRARY_PATH=usr/lib\n": "",
}

HOST_FILTER_DART = """
const _hostProvidedSharedObjectNames = {
  'libstdc++.so.6',
  'libgcc_s.so.1',
};

const _hostProvidedSharedObjectPrefixes = {
  'libEGL.so',
  'libGL.so',
  'libGLESv1_CM.so',
  'libGLESv2.so',
  'libgbm.so',
  'libdrm.so',
};

bool _usesHostSharedObject(String libPath) {
  final name = path.basename(libPath);
  return _hostProvidedSharedObjectNames.contains(name) ||
      _hostProvidedSharedObjectPrefixes.any((prefix) => name.startsWith(prefix));
}
"""

DEPENDENCY_FILTER_OLD = """              ..removeWhere(
                (lib) => lib.contains('libflutter_linux_gtk.so'),
              ),"""

DEPENDENCY_FILTER_NEW = """              ..removeWhere(
                (lib) =>
                    lib.contains('libflutter_linux_gtk.so') ||
                    _usesHostSharedObject(lib),
              ),"""

CLEANUP_OLD = """      var outputMakeConfig = MakeConfig().copyWith(makeConfig)
        ..packageFormat = 'AppImage';"""

CLEANUP_NEW = """      final usrLibDirectory = Directory(
        path.join(
          makeConfig.packagingDirectory.path,
          '${makeConfig.appName}.AppDir/usr/lib',
        ),
      );
      if (usrLibDirectory.existsSync()) {
        for (final entity in usrLibDirectory.listSync()) {
          if (entity is File && _usesHostSharedObject(entity.path)) {
            entity.deleteSync();
          }
        }
      }

      var outputMakeConfig = MakeConfig().copyWith(makeConfig)
        ..packageFormat = 'AppImage';"""

ARCH_OLD = "'ARCH': 'x86_64'"
ARCH_NEW = "'ARCH': Platform.environment['ARCH'] ?? 'x86_64'"


def _replace_or_confirm(text: str, old: str, new: str, label: str) -> str:
    if new and new in text:
        return text
    if old in text:
        return text.replace(old, new)
    raise RuntimeError(f"Expected AppImage maker text was not found: {label}")


def patch_config_text(text: str) -> str:
    patched = text
    for old, new in CONFIG_REPLACEMENTS.items():
        patched = _replace_or_confirm(patched, old, new, old)
    return patched


def patch_maker_text(text: str) -> str:
    patched = text

    if "bool _usesHostSharedObject(String libPath)" not in patched:
        import_block = "import 'package:shell_executor/shell_executor.dart';\n"
        if import_block not in patched:
            raise RuntimeError("Expected shell_executor import was not found")
        patched = patched.replace(import_block, import_block + HOST_FILTER_DART, 1)

    patched = _replace_or_confirm(
        patched,
        DEPENDENCY_FILTER_OLD,
        DEPENDENCY_FILTER_NEW,
        "dependency host-library filter",
    )
    patched = _replace_or_confirm(
        patched,
        CLEANUP_OLD,
        CLEANUP_NEW,
        "usr/lib host-library cleanup",
    )
    patched = _replace_or_confirm(patched, ARCH_OLD, ARCH_NEW, "ARCH override")
    return patched


def patch_file(path: Path, patcher) -> bool:
    before = path.read_text()
    after = patcher(before)
    if after == before:
        return False
    path.write_text(after)
    return True


def find_packager_files() -> list[tuple[Path, Path]]:
    roots = sorted(Path.home().glob(".pub-cache/hosted/*/flutter_app_packager-*"))
    pairs: list[tuple[Path, Path]] = []
    for root in roots:
        base = root / "lib/src/makers/appimage"
        config = base / "make_appimage_config.dart"
        maker = base / "app_package_maker_appimage.dart"
        if config.exists() and maker.exists():
            pairs.append((config, maker))
    return pairs


def patch_paths(paths: list[Path]) -> int:
    if paths:
        if len(paths) != 2:
            raise RuntimeError(
                "Pass either no paths, or CONFIG_FILE and MAKER_FILE explicitly"
            )
        pairs = [(paths[0], paths[1])]
    else:
        pairs = find_packager_files()

    if not pairs:
        raise RuntimeError("flutter_app_packager AppImage sources were not found")

    changed = 0
    for config_path, maker_path in pairs:
        changed += patch_file(config_path, patch_config_text)
        changed += patch_file(maker_path, patch_maker_text)
        print(f"patched AppImage maker: {maker_path.parent}")
    return changed


def main(argv: list[str]) -> int:
    try:
        patch_paths([Path(arg) for arg in argv])
    except Exception as exc:  # noqa: BLE001 - command line tool should print concise failure.
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

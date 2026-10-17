#!/usr/bin/env python3
"""Fix fastforge RPM source paths for RPM's per-package build directories."""
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


def patch_rpm_sources(maker: Path) -> None:
    text = maker.read_text()
    # The maker stages these files in _topdir/BUILD, not RPM's current builddir.
    for old, new in (
        ('cp -r $appName/*', 'cp -r "%{_topdir}/BUILD/$appName/."'),
        ('cp -r $appBinaryName.desktop', 'cp -r "%{_topdir}/BUILD/$appBinaryName.desktop"'),
        ('cp -r $appBinaryName.png', 'cp -r "%{_topdir}/BUILD/$appBinaryName.png"'),
        ('cp -r $appBinaryName*.xml', 'cp -r "%{_topdir}/BUILD"/$appBinaryName*.xml'),
    ):
        if text.count(old) == 1:
            text = text.replace(old, new, 1)
        elif text.count(new) != 1:
            raise RuntimeError(f"Unsupported RPM maker source: expected {old!r} in {maker}")
    maker.write_text(text)


if __name__ == "__main__":
    config = Path(__file__).resolve().parents[2] / "app/.dart_tool/package_config.json"
    packages = json.loads(config.read_text())["packages"]
    package = next(p for p in packages if p["name"] == "flutter_app_packager")
    package_uri = urljoin(config.as_uri(), package["rootUri"])
    root = Path(url2pathname(urlsplit(package_uri).path))
    maker = root / "lib/src/makers/rpm/make_rpm_config.dart"
    patch_rpm_sources(maker)
    print(f"Patched RPM staging paths: {maker}")

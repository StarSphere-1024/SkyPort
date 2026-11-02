import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.check_android_apk import check_elf_load_alignment, check_native


def elf64(alignment: int) -> bytes:
    data = bytearray(120)
    data[:16] = b"\x7fELF" + bytes((2, 1, 1)) + bytes(9)
    struct.pack_into("<HHIQQQIHHHHHH", data, 16,
                     3, 183, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0)
    struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, 0, 0, 56, 56, alignment)
    return bytes(data)


class AndroidApkCheckTest(unittest.TestCase):
    def test_elf_load_alignment_boundary(self):
        check_elf_load_alignment(elf64(16384))
        with self.assertRaises(ValueError):
            check_elf_load_alignment(elf64(4096))

    def test_rejects_missing_required_native_library(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "app.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                for library in ("libskyport_flutter_bridge.so", "libflutter.so"):
                    archive.writestr(f"lib/arm64-v8a/{library}", elf64(16384))
            with self.assertRaises(ValueError):
                check_native(apk, "arm64-v8a")

    def test_debug_payload_requires_kernel_instead_of_aot_library(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "debug.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                for library in ("libskyport_flutter_bridge.so", "libflutter.so"):
                    archive.writestr(f"lib/x86_64/{library}", elf64(16384))
            with self.assertRaises(ValueError):
                check_native(apk, "x86_64", debug=True)
            with zipfile.ZipFile(apk, "a") as archive:
                archive.writestr("assets/flutter_assets/kernel_blob.bin", b"kernel")
            check_native(apk, "x86_64", debug=True)


if __name__ == "__main__":
    unittest.main()

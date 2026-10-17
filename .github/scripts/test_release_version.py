#!/usr/bin/env python3
import unittest

from release_version import release_version


class ReleaseVersionTest(unittest.TestCase):
    def test_build_number_does_not_change_release_tag(self):
        self.assertEqual(release_version("version: 2.0.0+42\n", "v2.0.0"), "2.0.0")

    def test_prerelease_and_comment(self):
        self.assertEqual(
            release_version("version: 2.1.0-rc.1+7 # candidate\n", "v2.1.0-rc.1"),
            "2.1.0-rc.1",
        )

    def test_missing_duplicate_or_invalid_version_fails(self):
        for manifest in (
            "name: skyport\n",
            "version: 2.0.0\nversion: 3.0.0\n",
            "version: 02.0.0\n",
            "version: 2.0\n",
            "version: 2.0.0-01\n",
            "version: 2.0.0+\n",
            "version: 2.0.0;echo\n",
        ):
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                release_version(manifest)

    def test_tag_must_match_committed_version_exactly(self):
        for tag in ("master", "2.0.0", "v9.9.9", "v2.0.0+42", "v2.0.0\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_version("version: 2.0.0+42\n", tag)


if __name__ == "__main__":
    unittest.main()

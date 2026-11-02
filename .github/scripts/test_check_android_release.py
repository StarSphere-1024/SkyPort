#!/usr/bin/env python3
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_android_release as checker


class AndroidReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / "candidate.apk"
        self.apk.touch()
        self.env = patch.dict(os.environ, {"GH_TOKEN": "token", "GITHUB_REPOSITORY": "owner/repo"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.metadata = patch.object(checker, "_metadata", return_value=(8, ("cert",)))
        self.metadata_mock = self.metadata.start()
        self.addCleanup(self.metadata.stop)
        self.releases = patch.object(checker, "_releases", return_value=[])
        self.releases_mock = self.releases.start()
        self.addCleanup(self.releases.stop)
        self.download = patch.object(checker, "_download_asset")
        self.download_mock = self.download.start()
        self.addCleanup(self.download.stop)
        self.tools = {"apkanalyzer": "/tool/apkanalyzer", "apksigner": "/tool/apksigner"}

    def check(self):
        return checker.check_android_release(self.apk, **self.tools)

    def test_github_enumeration_failure_is_not_treated_as_first_release(self):
        self.releases_mock.side_effect = ValueError("API failed")
        with self.assertRaises(ValueError):
            self.check()

    def test_code_must_exceed_maximum_including_same_tag_release_assets(self):
        self.releases_mock.return_value = [{"draft": False, "assets": [{
            "id": 1, "name": "SkyPort-v1.0.0-android-arm64.apk"
        }]}]
        self.metadata_mock.side_effect = [(8, ("cert",)), (8, ("cert",))]
        with self.assertRaises(ValueError):
            self.check()

    def test_published_certificate_must_match_candidate(self):
        self.releases_mock.return_value = [{"draft": False, "assets": [{
            "id": 1, "name": "SkyPort-v1.0.0-android-arm64.apk"
        }]}]
        self.metadata_mock.side_effect = [(9, ("old-cert",)), (8, ("cert",))]
        with self.assertRaises(ValueError):
            self.check()

    def test_candidate_package_must_match_android_application_id(self):
        self.metadata.stop()
        with patch.object(checker, "_run", side_effect=["other.package", "8"]):
            with self.assertRaises(ValueError):
                checker._metadata(self.apk, "apkanalyzer", "apksigner")

    def test_new_code_exceeds_every_published_code(self):
        self.releases_mock.return_value = [{"draft": False, "assets": [
            {"id": 1, "name": "SkyPort-v1.0.0-android-arm64.apk"},
            {"id": 2, "name": "SkyPort-v1.1.0-android-arm64.apk"},
        ]}]
        self.metadata_mock.side_effect = [(9, ("cert",)), (8, ("cert",)), (7, ("cert",))]
        self.assertEqual(self.check(), 9)

    def test_published_apk_download_failure_blocks_release(self):
        self.releases_mock.return_value = [{"draft": False, "assets": [
            {"id": 1, "name": "SkyPort-v1.0.0-android-arm64.apk"},
        ]}]
        self.download_mock.side_effect = ValueError("download failed")
        with self.assertRaises(ValueError):
            self.check()

    def test_first_release_ignores_draft_and_non_android_assets(self):
        self.releases_mock.return_value = [
            {"draft": True, "assets": [{"id": 1, "name": "SkyPort-v1.0.0-android-arm64.apk"}]},
            {"draft": False, "assets": [{"id": 2, "name": "SkyPort-v1.0.0-linux.AppImage"}]},
        ]
        self.assertEqual(self.check(), 8)


if __name__ == "__main__":
    unittest.main()

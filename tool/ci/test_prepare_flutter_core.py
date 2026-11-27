"""Hosted-only unit coverage for the narrow source adaptation boundary."""

import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_flutter_core as subject


class PreparationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.core = self.root / "core"
        self.sdk = self.root / "sdk"
        self.sdk.mkdir()
        for relative in subject.SOURCE_ROOTS:
            (self.core / relative).mkdir(parents=True)
        (self.core / "pubspec.yaml").write_text("name: qfli_studio_core\n", encoding="utf-8")
        self.view = self.core / subject.VIEW
        self.view.parent.mkdir(parents=True)
        # Keep the genuine native source as the fixture; no hand-copied substitute.
        original = Path(__file__).resolve().parents[2] / subject.VIEW
        self.original = original.read_bytes()
        self.view.write_bytes(self.original)
        self.revision = "a" * 40
        self.environment = patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.sdk_validation = patch.object(subject, "validate_sdk", return_value=self.revision)
        self.sdk_validation.start()
        self.addCleanup(self.sdk_validation.stop)

    def prepare(self, flavor):
        return subject.prepare(self.core, self.sdk, self.revision, flavor)

    def test_official_replaces_only_known_native_view_and_is_idempotent(self):
        untouched = self.core / "lib/keep.dart"
        untouched.write_bytes(b"// Preserve consumer-independent source.\r\n")
        self.assertTrue(self.prepare("official")["changed"])
        self.assertEqual(self.view.read_text(encoding="utf-8"), subject.OFFICIAL_VIEW)
        self.assertEqual(untouched.read_bytes(), b"// Preserve consumer-independent source.\r\n")
        self.assertFalse(self.prepare("official")["changed"])

    def test_ohos_retains_native_view_exact_bytes(self):
        result = self.prepare("ohos")
        self.assertFalse(result["changed"])
        self.assertTrue(result["native_ohos_view_preserved"])
        self.assertEqual(self.view.read_bytes(), self.original)

    def test_ohos_rejects_an_already_stubbed_checkout(self):
        self.prepare("official")
        with self.assertRaisesRegex(ValueError, "Unexpected.*contents"):
            self.prepare("ohos")

    def test_source_drift_fails_without_overwriting(self):
        changed = self.original + b"\n// Unreviewed native source change.\n"
        self.view.write_bytes(changed)
        with self.assertRaisesRegex(ValueError, "Unexpected.*contents"):
            self.prepare("official")
        self.assertEqual(self.view.read_bytes(), changed)

    def test_unknown_fork_api_fails_before_any_change(self):
        offender = self.core / "vendor/xterm/lib/unreviewed.dart"
        offender.write_text("final platform = TargetPlatform.ohos;\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "vendor/xterm/lib/unreviewed.dart:1"):
            self.prepare("official")
        self.assertEqual(self.view.read_bytes(), self.original)

    def test_local_environment_cannot_mutate_source(self):
        with patch.dict(os.environ, {"RUNNER_ENVIRONMENT": "self-hosted"}):
            with self.assertRaisesRegex(ValueError, "GitHub-hosted"):
                self.prepare("official")
        self.assertEqual(self.view.read_bytes(), self.original)


class SdkValidationTest(unittest.TestCase):
    def test_mismatched_sdk_revision_is_rejected(self):
        with patch.object(subject, "git_output", return_value="b" * 40):
            with self.assertRaisesRegex(ValueError, "differs"):
                subject.validate_sdk(Path("unused"), "a" * 40, "official")

    def test_modified_sdk_library_is_rejected(self):
        with patch.object(subject, "git_output", side_effect=["a" * 40, " M packages/flutter/lib/a.dart"]):
            with self.assertRaisesRegex(ValueError, "local modifications"):
                subject.validate_sdk(Path("unused"), "a" * 40, "official")


if __name__ == "__main__":
    unittest.main()

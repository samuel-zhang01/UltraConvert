"""Release gates distinguish development signing from public notarized distribution."""

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import notarize
import package_app


class ReleaseTests(unittest.TestCase):
    def test_development_certificate_is_not_a_public_distribution_identity(self):
        digest = "A" * 40
        with patch.object(
            package_app.subprocess,
            "check_output",
            return_value=f'1) {digest} "Apple Development: Example (TEAM)"',
        ):
            with self.assertRaisesRegex(RuntimeError, "Developer ID Application"):
                package_app.developer_id_identity(digest)

    def test_developer_id_name_or_hash_resolves_only_an_exact_match(self):
        digest, name = "B" * 40, "Developer ID Application: Example (TEAM)"
        with patch.object(
            package_app.subprocess, "check_output", return_value=f'1) {digest} "{name}"'
        ):
            self.assertEqual(package_app.developer_id_identity(name), digest)
            self.assertEqual(package_app.developer_id_identity(digest), digest)
            with self.assertRaises(RuntimeError):
                package_app.developer_id_identity("Example")

    def test_rejected_notarization_stops_the_release(self):
        with patch.object(
            notarize.subprocess,
            "run",
            return_value=SimpleNamespace(
                stdout=json.dumps({"status": "Invalid", "id": "test-submission"})
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                notarize.notarize(Path("test.zip"), "test-profile")

    def test_accepted_notarization_uses_a_keychain_profile(self):
        with patch.object(
            notarize.subprocess,
            "run",
            return_value=SimpleNamespace(
                stdout=json.dumps({"status": "Accepted", "id": "test-submission"})
            ),
        ) as run:
            self.assertEqual(notarize.notarize(Path("test.zip"), "test-profile"), "test-submission")
        args = run.call_args.args[0]
        self.assertIn("--keychain-profile", args)
        self.assertIn("--wait", args)
        self.assertNotIn("--password", args)


if __name__ == "__main__":
    unittest.main()

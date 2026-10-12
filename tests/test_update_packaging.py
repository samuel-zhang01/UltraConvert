"""Updater supply-chain gates without network access or signing credentials."""

import contextlib
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import build_updates
import sparkle


class UpdatePackagingTests(unittest.TestCase):
    def test_changed_cached_dependency_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / "build/dependencies"
            cache.mkdir(parents=True)
            (cache / f"Sparkle-{sparkle.VERSION}.tar.xz").write_bytes(b"modified framework")
            with (
                patch.object(sparkle, "ROOT", root),
                patch.object(sparkle.subprocess, "run") as run,
            ):
                with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                    with sparkle.distribution():
                        self.fail("Modified framework was extracted")
                run.assert_not_called()

    def test_verified_dependency_reuses_pinned_bytes_without_network(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / "build/dependencies"
            cache.mkdir(parents=True)
            archive = cache / f"Sparkle-{sparkle.VERSION}.tar.xz"
            archive.write_bytes(b"pinned bytes")
            with (
                patch.object(sparkle, "ROOT", root),
                patch.object(sparkle, "SHA256", hashlib.sha256(archive.read_bytes()).hexdigest()),
                patch.object(sparkle.urllib.request, "urlopen") as network,
            ):
                self.assertEqual(sparkle.verified_archive(), archive)
                network.assert_not_called()

    def test_wrong_key_cannot_publish_feed(self):
        with tempfile.TemporaryDirectory() as temp:

            @contextlib.contextmanager
            def distribution():
                yield Path(temp)

            with (
                patch.object(sparkle, "distribution", distribution),
                patch.object(build_updates.subprocess, "run") as run,
                patch.object(build_updates.subprocess, "check_output", return_value="wrong-key"),
            ):
                with self.assertRaisesRegex(RuntimeError, "does not match"):
                    build_updates.build_update_assets(
                        Path("Example.app"), Path(temp), "1.8.0", "universal"
                    )
                self.assertEqual(run.call_count, 1)  # Compression only; no feed signed.

    def test_existing_update_archive_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "UltraConvert-1.8.0-update-macos-universal.zip"
            archive.write_bytes(b"published asset")
            with patch.object(build_updates.subprocess, "run") as run:
                with self.assertRaisesRegex(RuntimeError, "already exists"):
                    build_updates.build_update_assets(
                        Path("Example.app"), Path(temp), "1.8.0", "universal"
                    )
                run.assert_not_called()
                self.assertEqual(archive.read_bytes(), b"published asset")


if __name__ == "__main__":
    unittest.main()

"""Source collection must reject unsafe transport and mismatched archive bytes."""

import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import collect_runtime_sources as sources


class SourceCollectionTests(unittest.TestCase):
    def test_non_https_and_embedded_credentials_are_rejected(self):
        for url in (
            "file:///etc/passwd",
            "http://example.com/a",
            "https://user:password@example.com/a",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                sources.https_url(url)

    def test_redirect_cannot_downgrade_or_read_local_files(self):
        for url in ("http://example.com/a", "file:///etc/passwd"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                sources.HTTPSRedirects().redirect_request(None, None, 302, "", {}, url)

    def test_checksum_mismatch_is_never_marked_verified(self):
        with tempfile.TemporaryDirectory() as temp:
            entry = {"url": "https://example.com/source.tar", "sha256": "0" * 64}
            with patch.object(sources.urllib.request, "build_opener") as opener:
                opener.return_value.open.return_value = io.BytesIO(b"unexpected bytes")
                result = sources.download(entry, Path(temp))
            self.assertFalse(result["verified"])
            self.assertIn("checksum mismatch", result["error"])

    def test_verified_cached_source_needs_no_new_download(self):
        with tempfile.TemporaryDirectory() as temp:
            content = b"source archive fixture"
            digest = hashlib.sha256(content).hexdigest()
            entry = {"url": "https://example.com/source.tar", "sha256": digest}
            (Path(temp) / (digest[:16] + "-source.tar")).write_bytes(content)
            with patch.object(
                sources.urllib.request, "build_opener", side_effect=AssertionError("Network used")
            ):
                self.assertTrue(sources.download(entry, Path(temp))["verified"])


if __name__ == "__main__":
    unittest.main()

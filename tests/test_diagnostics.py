"""Setup checks must report partial failures without uploading or converting files."""

import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import diagnostics


class DiagnosticTests(unittest.TestCase):
    def test_missing_engine_is_reported_without_stopping_checks(self):
        with patch.object(diagnostics, "tool", side_effect=FileNotFoundError):
            result = diagnostics.probe("FFmpeg", ("ffmpeg", "-version"))
        self.assertFalse(result["ok"])
        self.assertIn("Missing", result["detail"])

    def test_hung_probe_is_bounded(self):
        with (
            patch.object(diagnostics, "tool", return_value="/fixed/tool"),
            patch.object(
                diagnostics.subprocess, "run", side_effect=subprocess.TimeoutExpired("probe", 8)
            ) as run,
        ):
            result = diagnostics.probe("FFmpeg", ("ffmpeg", "-version"))
        self.assertFalse(result["ok"])
        self.assertEqual(run.call_args.kwargs["timeout"], 8)
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_ape_usage_exit_requires_the_real_banner(self):
        def usage(args, **kwargs):
            kwargs["stdout"].write(b"Monkey's Audio Console Front End (v 13.27)\nUsage\n")
            return SimpleNamespace(returncode=255)

        with (
            patch.object(diagnostics, "tool", return_value="/fixed/mac"),
            patch.object(diagnostics.subprocess, "run", side_effect=usage),
        ):
            self.assertTrue(diagnostics.probe("Monkey's Audio", ("mac",))["ok"])
            self.assertFalse(diagnostics.probe("FFmpeg", ("ffmpeg", "-version"))["ok"])

    def test_broken_packages_are_not_reported_ready(self):
        with patch.object(
            diagnostics.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout=b"")
        ):
            self.assertFalse(diagnostics.check_packages()["ok"])

    def test_missing_or_malformed_workflow_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            workflow = Path(temp) / "Broken.workflow"
            self.assertFalse(diagnostics.check_workflow(workflow)["ok"])
            (workflow / "Contents").mkdir(parents=True)
            (workflow / "Contents/Info.plist").write_text("not a plist")
            self.assertFalse(diagnostics.check_workflow(workflow)["ok"])
            (workflow / "Contents/Info.plist").write_bytes(plistlib.dumps({"NSServices": [42]}))
            self.assertFalse(diagnostics.check_workflow(workflow)["ok"])


if __name__ == "__main__":
    unittest.main()

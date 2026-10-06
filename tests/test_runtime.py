"""A bundled app must resolve only contained tools and reject broken manifests."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import runtime_tools


class BundledRuntimeTests(unittest.TestCase):
    def setUp(self):
        runtime_tools.bundled_runtime.cache_clear()

    def tearDown(self):
        runtime_tools.bundled_runtime.cache_clear()

    def bundle(self, root):
        contents = root / "UltraConvert.app/Contents"
        source = contents / "Resources/Source"
        source.mkdir(parents=True)
        helpers = contents / "Helpers"
        helpers.mkdir()
        tool = helpers / "ffmpeg"
        tool.write_text("fixture")
        tool.chmod(0o755)
        data = {"schema": 1, "tools": {"ffmpeg": "Helpers/ffmpeg"}, "environment_paths": {}}
        manifest = contents / "Resources/runtime-manifest.json"
        manifest.write_text(json.dumps(data))
        return contents, source, data, manifest

    def test_a_bundled_tool_does_not_consult_path_or_homebrew(self):
        with tempfile.TemporaryDirectory() as temp:
            contents, source, _, _ = self.bundle(Path(temp))
            runtime = runtime_tools.bundled_runtime(source)
            with patch.object(runtime_tools, "bundled_runtime", return_value=runtime):
                with patch.object(
                    runtime_tools.shutil, "which", side_effect=AssertionError("PATH was consulted")
                ):
                    self.assertEqual(
                        runtime_tools.tool("ffmpeg"), str((contents / "Helpers/ffmpeg").resolve())
                    )
                    self.assertEqual(runtime_tools.tool("file"), "/usr/bin/file")
                    with self.assertRaises(FileNotFoundError):
                        runtime_tools.tool("missing")
            self.assertNotIn("/opt/homebrew", runtime["environment"]["PATH"])
            self.assertEqual(runtime["environment"]["GDAL_DRIVER_PATH"], "disable")

    def test_missing_absolute_and_traversing_paths_are_rejected(self):
        for path in ("Helpers/missing", "/usr/bin/true", "../../../../usr/bin/true"):
            with self.subTest(path=path), tempfile.TemporaryDirectory() as temp:
                _, source, data, manifest = self.bundle(Path(temp))
                data["tools"]["ffmpeg"] = path
                manifest.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    runtime_tools.bundled_runtime(source)

    def test_symlink_escape_cannot_load_an_external_tool(self):
        with tempfile.TemporaryDirectory() as temp:
            contents, source, _, _ = self.bundle(Path(temp))
            path = contents / "Helpers/ffmpeg"
            path.unlink()
            path.symlink_to("/usr/bin/true")
            with self.assertRaises(ValueError):
                runtime_tools.bundled_runtime(source)

    def test_manifest_cannot_supply_loader_or_python_environment(self):
        with tempfile.TemporaryDirectory() as temp:
            _, source, data, manifest = self.bundle(Path(temp))
            data["environment_paths"] = {"DYLD_INSERT_LIBRARIES": "Helpers/ffmpeg"}
            manifest.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                runtime_tools.bundled_runtime(source)

    def test_absent_manifest_retains_source_installation_path(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertIsNone(runtime_tools.bundled_runtime(Path(temp)))

    def test_nonexecutable_bundled_tool_has_no_external_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            contents, source, _, _ = self.bundle(Path(temp))
            (contents / "Helpers/ffmpeg").chmod(0o644)
            runtime = runtime_tools.bundled_runtime(source)
            with patch.object(runtime_tools, "bundled_runtime", return_value=runtime):
                with self.assertRaises(FileNotFoundError):
                    runtime_tools.tool("ffmpeg")


if __name__ == "__main__":
    unittest.main()

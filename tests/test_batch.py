"""Real batch UX regressions for placement, skip, collisions and reports."""

import errno
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import convert


class BatchTests(unittest.TestCase):
    def setUp(self):
        convert.CANCEL.clear()
        self.temp = tempfile.TemporaryDirectory(prefix="ultraconvert-batch-")
        self.work = Path(self.temp.name).resolve()
        self.sources = []
        for folder in ("first", "second"):
            parent = self.work / folder
            parent.mkdir()
            source = parent / "same-name.json"
            source.write_text('{"label":"' + folder + '"}')
            self.sources.append(source)

    def tearDown(self):
        convert.CANCEL.clear()
        self.temp.cleanup()

    def run_batch(self, *options):
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "src/convert.py"),
                "--reports-dir",
                str(self.work / "reports"),
                *options,
                "--",
                *map(str, self.sources),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.splitlines()[-1])

    def test_here_places_each_result_beside_its_source(self):
        report = self.run_batch("--here", "--to", "yaml")
        self.assertEqual(report["success"], 2)
        self.assertEqual(len(report["outputs"]), 2)
        for result in report["results"]:
            output = Path(result["output"])
            self.assertEqual(output, Path(result["path"]).with_suffix(".yaml"))
            self.assertTrue(output.is_file())
            self.assertFalse(any(p.is_dir() for p in output.parent.iterdir()))
        self.assertEqual(len(report["reports"]), 2)
        for path in report["reports"]:
            saved = json.loads(Path(path).read_text())
            self.assertEqual(saved["success"], 1)
            self.assertEqual(len(saved["results"]), 1)

    def test_chosen_destination_and_name_collisions(self):
        destination = self.work / "chosen"
        report = self.run_batch("--output", str(destination), "--to", "yaml")
        self.assertEqual(len(report["outputs"]), 1)
        self.assertNotEqual(report["results"][0]["output"], report["results"][1]["output"])
        self.assertEqual(Path(report["output"]).parent, destination)

    def test_same_format_skip_is_explicit(self):
        report = self.run_batch("--here", "--to", "json", "--skip-same")
        self.assertEqual(report["success"], 0)
        self.assertEqual(report["skipped"], 2)
        self.assertTrue(all(r["output"] is None for r in report["results"]))
        self.assertTrue(all(s.read_text().startswith('{"label":') for s in self.sources))
        self.assertTrue(all(list(s.parent.iterdir()) == [s] for s in self.sources))

    def test_repeat_batches_do_not_overwrite(self):
        first = self.run_batch("--here", "--to", "yaml")
        second = self.run_batch("--here", "--to", "yaml")
        self.assertTrue(set(first["result_files"]).isdisjoint(second["result_files"]))
        self.assertTrue(all(Path(p).exists() for p in first["result_files"]))
        self.assertTrue(all(Path(p).name == "same-name (2).yaml" for p in second["result_files"]))
        self.assertTrue(set(first["reports"]).isdisjoint(second["reports"]))

    def test_opus_to_mp3_is_one_file_beside_original(self):
        source = self.work / "Voice note 01.opus"
        convert.run(
            ["ffmpeg", "-v", "error", "-i", ROOT / "examples/Tone.wav", "-c:a", "libopus", source]
        )
        original = source.read_bytes()
        self.sources = [source]
        report = self.run_batch("--here", "--to", "mp3")
        output = Path(report["results"][0]["output"])
        self.assertEqual(output, source.with_suffix(".mp3"))
        self.assertEqual(convert.inspect(output)["format"], "mp3")
        self.assertEqual(source.read_bytes(), original)
        self.assertFalse(list(self.work.glob("Converted*")))
        self.assertFalse(list(self.work.glob(".working-*")))
        self.assertFalse((self.work / "conversion-report.json").exists())

    def test_existing_symlink_and_original_are_never_overwritten(self):
        protected = self.work / "protected.txt"
        protected.write_bytes(b"keep this")
        for source in self.sources:
            source.with_suffix(".yaml").symlink_to(protected)
        originals = [s.read_bytes() for s in self.sources]
        report = self.run_batch("--here", "--to", "yaml")
        self.assertTrue(all(Path(p).name == "same-name (2).yaml" for p in report["result_files"]))
        self.assertEqual(protected.read_bytes(), b"keep this")
        self.assertEqual([s.read_bytes() for s in self.sources], originals)
        self.assertTrue(all(s.with_suffix(".yaml").is_symlink() for s in self.sources))

    def test_parallel_same_stems_get_distinct_complete_files(self):
        parent = self.sources[0].parent
        second = parent / "same-name.yml"
        second.write_text("label: yaml\n")
        self.sources = [self.sources[0], second]
        report = self.run_batch("--here", "--to", "yaml", "--jobs", "4")
        self.assertEqual(
            {Path(p).name for p in report["result_files"]}, {"same-name.yaml", "same-name (2).yaml"}
        )
        self.assertEqual(
            {convert.structured.load(Path(p), "yaml")["label"] for p in report["result_files"]},
            {"first", "yaml"},
        )

    def test_no_hardlink_volume_uses_exclusive_copy(self):
        source = self.sources[0]
        occupied = source.with_suffix(".yaml")
        occupied.write_bytes(b"existing")
        with patch.object(convert.os, "link", side_effect=OSError(errno.EOPNOTSUPP, "unsupported")):
            result = convert.convert_one(
                convert.inspect(source), "yaml", source.parent, 0, here=True
            )
        self.assertTrue(result["success"], result["error"])
        self.assertEqual(Path(result["output"]).name, "same-name (2).yaml")
        self.assertEqual(occupied.read_bytes(), b"existing")
        self.assertEqual(convert.structured.load(Path(result["output"]), "yaml")["label"], "first")

    def test_cancelled_copy_removes_only_new_partial_file(self):
        stage = self.work / "stage"
        stage.mkdir()
        (stage / "audio.mp3").write_bytes(b"new audio")
        occupied = self.work / "audio.mp3"
        occupied.write_bytes(b"original audio")
        with (
            patch.object(convert.os, "link", side_effect=OSError(errno.EOPNOTSUPP, "unsupported")),
            patch.object(convert.CANCEL, "is_set", return_value=True),
        ):
            with self.assertRaises(InterruptedError):
                convert.publish_here(stage, self.work, "audio", "mp3")
        self.assertEqual(occupied.read_bytes(), b"original audio")
        self.assertFalse((self.work / "audio (2).mp3").exists())

    def test_html_companion_images_use_one_folder_and_keep_relative_links(self):
        source = self.work / "note.md"
        source.write_text("![Image](image.png)\n")
        shutil.copy2(ROOT / "examples/Colour.png", self.work / "image.png")
        doc = convert.convert_one(convert.inspect(source), "docx", self.work, 0)
        self.assertTrue(doc["success"], doc["error"])
        docx = next(Path(doc["output"]).glob("*.docx"))
        here = convert.convert_one(convert.inspect(docx), "html", docx.parent, 0, here=True)
        self.assertTrue(here["success"], here["error"])
        folder = Path(here["output"])
        self.assertEqual(folder.parent, docx.parent)
        self.assertEqual(folder.name, "note-html")
        self.assertIn("media/", next(folder.glob("*.html")).read_text())
        self.assertEqual(
            next((folder / "media").glob("*.png")).read_bytes(),
            (self.work / "image.png").read_bytes(),
        )

    def test_gpkg_is_direct_and_layer_metadata_moves_to_report(self):
        source = self.work / "Places.geojson"
        shutil.copy2(ROOT / "examples/Places.geojson", source)
        self.sources = [source]
        report = self.run_batch("--here", "--to", "gpkg")
        self.assertEqual(Path(report["result_files"][0]), source.with_suffix(".gpkg"))
        self.assertTrue(Path(report["result_files"][0]).is_file())
        saved = json.loads(Path(report["reports"][0]).read_text())
        self.assertTrue(saved["results"][0]["layers"]["source_layers"])
        self.assertFalse((source.parent / "layers.json").exists())

    def test_shapefile_companions_stay_together_without_an_outer_batch(self):
        source = self.work / "Places.geojson"
        shutil.copy2(ROOT / "examples/Places.geojson", source)
        self.sources = [source]
        report = self.run_batch("--here", "--to", "shp")
        folder = Path(report["result_files"][0])
        self.assertEqual(folder, self.work / "Places-shp")
        for extension in ("shp", "dbf", "shx", "prj"):
            self.assertTrue((folder / f"Places.{extension}").is_file())
        self.assertEqual(convert.inspect(folder / "Places.shp")["format"], "shp")
        self.assertFalse(list(self.work.glob("Converted*")))

    def test_case_insensitive_collision_preserves_existing_file(self):
        for source in self.sources:
            source.with_name("SAME-NAME.yaml").write_bytes(b"keep existing")
        if not self.sources[0].with_suffix(".yaml").exists():
            self.skipTest("Volume is case-sensitive")
        report = self.run_batch("--here", "--to", "yaml")
        self.assertTrue(all(Path(p).name == "same-name (2).yaml" for p in report["result_files"]))
        self.assertTrue(
            all(
                s.with_name("SAME-NAME.yaml").read_bytes() == b"keep existing" for s in self.sources
            )
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

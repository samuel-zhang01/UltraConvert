"""Real batch UX regressions for placement, skip, collisions and reports."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ultraconvert-batch-")
        self.work = Path(self.temp.name)
        self.sources = []
        for folder in ("first", "second"):
            parent = self.work / folder
            parent.mkdir()
            source = parent / "same-name.json"
            source.write_text('{"label":"' + folder + '"}')
            self.sources.append(source)

    def tearDown(self):
        self.temp.cleanup()

    def run_batch(self, *options):
        result = subprocess.run(
            [sys.executable, str(ROOT / "src/convert.py"), *options, "--", *map(str, self.sources)],
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
            bundle = Path(result["output"])
            self.assertEqual(bundle.parent.parent, Path(result["path"]).parent)
            saved = json.loads((bundle.parent / "conversion-report.json").read_text())
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

    def test_repeat_batches_do_not_overwrite(self):
        first = self.run_batch("--here", "--to", "yaml")
        second = self.run_batch("--here", "--to", "yaml")
        self.assertTrue(set(first["outputs"]).isdisjoint(second["outputs"]))
        self.assertTrue(all(Path(p).exists() for p in first["outputs"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""Adversarial regressions exercising parser boundaries and real engine policy."""

import http.server
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import convert
import guards
import structured


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ultraconvert-adversarial-")
        self.work = Path(self.temp.name)
        convert.CANCEL.clear()

    def tearDown(self):
        convert.CANCEL.clear()
        self.temp.cleanup()

    def archive(self, entries):
        path = self.work / "hostile.docx"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
                for name, data in entries:
                    z.writestr(name, data)
        return path

    def test_gml_reader_does_not_write_beside_original(self):
        output = self.work / "generated"
        output.mkdir()
        result = convert.convert_one(
            convert.inspect(ROOT / "examples/Places.geojson"), "gml", output, 1
        )
        self.assertTrue(result["success"], result["error"])
        source = next(Path(result["output"]).glob("*.gml"))
        before = {p.name: p.read_bytes() for p in source.parent.iterdir() if p.is_file()}
        returned = convert.convert_one(convert.inspect(source), "geojson", output, 2)
        self.assertTrue(returned["success"], returned["error"])
        self.assertEqual(
            before, {p.name: p.read_bytes() for p in source.parent.iterdir() if p.is_file()}
        )

    def test_gml_external_schema_include_is_refused(self):
        output = self.work / "generated"
        output.mkdir()
        result = convert.convert_one(
            convert.inspect(ROOT / "examples/Places.geojson"), "gml", output, 1
        )
        source = next(Path(result["output"]).glob("*.gml"))
        source.with_suffix(".xsd").write_text(
            '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:include schemaLocation="file:///etc/passwd"/></xs:schema>'
        )
        returned = convert.convert_one(convert.inspect(source), "geojson", output, 2)
        self.assertFalse(returned["success"])
        self.assertIn("External XSD", returned["error"])

    def test_archive_traversal(self):
        source = self.archive([("word/document.xml", "<doc/>"), ("../escape", "payload")])
        self.assertIn("unsafe member", convert.inspect(source)["error"])
        self.assertFalse((self.work.parent / "escape").exists())

    def test_archive_duplicate(self):
        source = self.archive([("word/document.xml", "a"), ("word/document.xml", "b")])
        self.assertIn("duplicate", convert.inspect(source)["error"])

    def test_archive_symlink(self):
        path = self.work / "symlink.zip"
        info = zipfile.ZipInfo("link")
        info.create_system = 3
        info.external_attr = 0o120777 << 16
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(info, "../../outside")
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            guards.validate_archive(path)

    def test_archive_expansion_limit(self):
        source = self.archive([("word/document.xml", "x" * 10_000)])
        with patch.object(guards, "MAX_ARCHIVE_BYTES", 4096):
            self.assertIn("expansion", convert.inspect(source)["error"])

    def test_yaml_tags_do_not_execute(self):
        source = self.work / "tag.yaml"
        marker = self.work / "executed"
        source.write_text(f"!!python/object/apply:os.system ['touch {marker}']")
        self.assertIsNotNone(convert.inspect(source)["error"])
        self.assertFalse(marker.exists())

    def test_yaml_alias_expansion_is_bounded(self):
        source = self.work / "aliases.yaml"
        source.write_text(
            "a: &a [1]\n"
            + "".join(
                f"n{i}: &n{i} [*{'a' if i == 0 else 'n' + str(i - 1)}, *{'a' if i == 0 else 'n' + str(i - 1)}]\n"
                for i in range(25)
            )
        )
        started = time.monotonic()
        self.assertIn("safety limit", convert.inspect(source)["error"])
        self.assertLess(time.monotonic() - started, 5)

    def test_nested_config_is_bounded(self):
        source = self.work / "deep.json"
        source.write_text("[" * 120 + "0" + "]" * 120)
        self.assertIn("safety limit", convert.inspect(source)["error"])

    def test_configuration_size_limit(self):
        source = self.work / "oversized.json"
        source.write_text('{"value":"' + "x" * 4096 + '"}')
        with patch.object(structured, "MAX_CONFIG_BYTES", 1024):
            self.assertIn("safety limit", convert.inspect(source)["error"])

    def test_xml_entities_refused(self):
        source = self.work / "entity.gml"
        source.write_text('<!DOCTYPE a [<!ENTITY leak SYSTEM "file:///etc/passwd">]><a>&leak;</a>')
        self.assertIsNotNone(convert.inspect(source)["error"])

    def test_svg_disguised_as_png_is_refused(self):
        source = self.work / "disguised.png"
        source.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><image href="file:///etc/passwd"/></svg>'
        )
        info = convert.inspect(source)
        self.assertIsNotNone(info["error"])
        self.assertNotEqual(info["format"], "png")

    def test_source_change_is_refused(self):
        source = self.work / "changed.json"
        source.write_text('{"a":1}')
        info = convert.inspect(source)
        source.write_text('{"a":200}')
        result = convert.convert_one(info, "yaml", self.work, 0)
        self.assertIn("changed after recognition", result["error"])

    def test_document_cannot_read_outside_folder(self):
        docs = self.work / "docs"
        docs.mkdir()
        image = self.work / "private.png"
        convert.run(["magick", "-size", "16x16", "xc:blue", image])
        for index, link in enumerate(["../private.png", str(image), "escape.png"]):
            if link == "escape.png":
                (docs / link).symlink_to(image)
            source = docs / f"outside{index}.md"
            source.write_text(f"![Private]({link})\n")
            result = convert.convert_one(convert.inspect(source), "docx", self.work, index)
            self.assertFalse(result["success"])

    def test_network_document_and_kml_are_not_fetched(self):
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"test")

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/private"
            md = self.work / "remote.md"
            md.write_text(f"![Remote]({url})\n")
            self.assertFalse(
                convert.convert_one(convert.inspect(md), "docx", self.work, 0)["success"]
            )
            kml = self.work / "style.kml"
            kml.write_text(
                f'<kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark><styleUrl>{url}#style</styleUrl><Point><coordinates>1,2</coordinates></Point></Placemark></Document></kml>'
            )
            result = convert.convert_one(convert.inspect(kml), "gpkg", self.work, 1)
            self.assertTrue(result["success"], result["error"])
            self.assertEqual(requests, [])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_cancel_escalates_for_uncooperative_engine(self):
        started = time.monotonic()
        timer = threading.Timer(0.3, convert.cancel)
        timer.start()
        try:
            with patch.object(convert, "tool", return_value=sys.executable):
                with self.assertRaises(InterruptedError):
                    convert.run(
                        [
                            "python",
                            "-c",
                            "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)",
                        ]
                    )
            self.assertLess(time.monotonic() - started, 5)
            self.assertEqual(convert.PROCESSES, set())
        finally:
            timer.cancel()

    def test_engine_log_volume_is_bounded(self):
        with patch.object(convert, "tool", return_value=sys.executable):
            with self.assertRaisesRegex(ValueError, "output exceeded"):
                convert.run(["python", "-c", "import sys; sys.stderr.write('x' * (10*1024*1024))"])

    def test_invalid_plan_fails_before_output(self):
        source = self.work / "input.json"
        source.write_text('{"a":1}')
        plan = self.work / "plan.json"
        plan.write_text('["invalid"]')
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "src/convert.py"),
                "--plan",
                str(plan),
                "--output",
                str(self.work / "output"),
                "--",
                str(source),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.work / "output").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)

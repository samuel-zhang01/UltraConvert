#!/usr/bin/env python3
"""Exercise each requested format in both directions using real installed engines."""

import argparse
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import convert
import structured


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", choices=list(convert.FORMATS))
    args = parser.parse_args()
    categories = args.only or list(convert.FORMATS)
    evidence = {
        "date": "2026-10-06",
        "method": "Generate real fixtures, write every target, detect output, convert back with installed engines; hash originals before/after.",
        "formats": [],
        "checks": [],
    }
    failures = []
    with tempfile.TemporaryDirectory(prefix="ultraconvert-format-tests-") as tmp:
        work = Path(tmp)
        fixtures = work / "fixtures"
        fixtures.mkdir()
        out = work / "output"
        out.mkdir()
        inputs = {}
        inputs["config"] = fixtures / "sample.json"
        inputs["config"].write_text(
            json.dumps(
                {
                    "label": "conversion ✓",
                    "count": 7,
                    "ratio": 2.5,
                    "enabled": True,
                    "list": ["a", "b"],
                    "nested": {"key": "value"},
                }
            )
        )
        inputs["document"] = fixtures / "sample.md"
        inputs["document"].write_text(
            "# Conversion test\n\nRetain this distinctive sentence.\n\n- One\n- Two\n"
        )
        inputs["geo"] = fixtures / "point.geojson"
        inputs["geo"].write_text(
            json.dumps(
                {
                    "type": "FeatureCollection",
                    "features": [
                        {
                            "type": "Feature",
                            "properties": {"name": "London", "value": 7},
                            "geometry": {"type": "Point", "coordinates": [-0.12, 51.5]},
                        }
                    ],
                }
            )
        )
        inputs["image"] = fixtures / "sample.png"
        convert.run(["magick", "-size", "128x96", "gradient:navy-cyan", inputs["image"]])
        inputs["audio"] = fixtures / "sample.wav"
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=1",
                "-ar",
                "48000",
                "-ac",
                "2",
                inputs["audio"],
            ]
        )
        inputs["video"] = fixtures / "sample.mp4"
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=128x96:rate=25:duration=1",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=1",
                "-c:v",
                "libx264",
                "-c:a",
                "aac",
                "-ar",
                "48000",
                "-ac",
                "2",
                "-shortest",
                inputs["video"],
            ]
        )
        original_hashes = {str(p): sha(p) for p in inputs.values()}
        index = 0
        for category in categories:
            info = convert.inspect(inputs[category])
            for target in convert.FORMATS[category]:
                index += 2
                result = convert.convert_one(info, target, out, index)
                record = {
                    "category": category,
                    "format": target,
                    "write": result["success"],
                    "read": False,
                    "error": result["error"],
                }
                if result["success"]:
                    extension = "m4a" if target == "alac" else target
                    candidates = sorted(Path(result["output"]).glob(f"*.{extension}"))
                    if not candidates:
                        record["error"] = "No output with target extension"
                    else:
                        produced = candidates[0]
                        actual = convert.inspect(produced)
                        record["detected_format"] = actual["format"]
                        record["bytes"] = produced.stat().st_size
                        back_target = {
                            "config": "json",
                            "image": "png",
                            "audio": "wav",
                            "video": "mp4",
                            "document": "md",
                            "geo": "geojson",
                        }[category]
                        back = convert.convert_one(actual, back_target, out, index + 1)
                        record["read"] = back["success"]
                        if not back["success"]:
                            record["error"] = back["error"]
                        elif category == "document":
                            content = next(Path(back["output"]).glob("*.md")).read_text()
                            if "distinctive sentence" not in content:
                                record["read"] = False
                                record["error"] = "Document content lost"
                        elif category == "config":
                            returned = next(Path(back["output"]).glob("*.json"))
                            if structured.signature(
                                structured.load(returned, "json")
                            ) != structured.signature(structured.load(inputs[category], "json")):
                                record["read"] = False
                                record["error"] = "Configuration types changed"
                        elif category == "geo":
                            returned = json.loads(
                                next(Path(back["output"]).glob("*.geojson")).read_text()
                            )
                            if not returned.get("features"):
                                record["read"] = False
                                record["error"] = "GIS features lost"
                evidence["formats"].append(record)
                ok = record["write"] and record["read"]
                print(
                    f"{'PASS' if ok else 'FAIL'} {category} .{target}"
                    + (f": {record['error']}" if not ok else ""),
                    flush=True,
                )
                if not ok:
                    failures.append(record)

        def check(name, test):
            try:
                assert test(), name
                evidence["checks"].append({"name": name, "pass": True})
                print(f"PASS {name}", flush=True)
            except Exception as exc:
                evidence["checks"].append({"name": name, "pass": False, "error": str(exc)})
                failures.append({"check": name, "error": str(exc)})
                print(f"FAIL {name}: {exc}", flush=True)

        check(
            "original file hashes unchanged",
            lambda: all(sha(Path(p)) == value for p, value in original_hashes.items()),
        )
        renamed = fixtures / "mislabeled.mp4"
        renamed.write_bytes(inputs["image"].read_bytes())
        check(
            "content detection overrides wrong extension",
            lambda: convert.inspect(renamed)["category"] == "image",
        )
        extensionless = fixtures / "no-extension"
        extensionless.write_bytes(inputs["document"].read_bytes())
        binary = fixtures / "binary.plist"
        binary.write_bytes(plistlib.dumps({"count": 7}, fmt=plistlib.FMT_BINARY))
        check(
            "binary PLIST recognition and conversion",
            lambda: convert.convert_one(convert.inspect(binary), "json", out, 700)["success"],
        )
        duplicate = fixtures / "duplicates.json"
        duplicate.write_text('{"a":1,"a":2}')
        check("duplicate keys rejected", lambda: bool(convert.inspect(duplicate)["error"]))
        null = fixtures / "null.json"
        null.write_text('{"a":null}')
        check(
            "TOML null refuses silent loss",
            lambda: not convert.convert_one(convert.inspect(null), "toml", out, 701)["success"],
        )
        date = fixtures / "date.yaml"
        date.write_text("date: 2026-10-06\n")
        check(
            "JSON date refuses silent coercion",
            lambda: not convert.convert_one(convert.inspect(date), "json", out, 702)["success"],
        )
        if "geo" in categories:
            bare = fixtures / "bare.wkt"
            bare.write_text("POINT (-0.12 51.5)\n")
            check(
                "WKT without CRS rejected",
                lambda: (
                    not convert.convert_one(convert.inspect(bare), "geojson", out, 703)["success"]
                ),
            )
            check(
                "WKT with explicit CRS works",
                lambda: convert.convert_one(convert.inspect(bare), "gpkg", out, 704, "EPSG:4326")[
                    "success"
                ],
            )
            polygon = fixtures / "polygon.geojson"
            polygon.write_text(
                json.dumps(
                    {
                        "type": "FeatureCollection",
                        "features": [
                            {
                                "type": "Feature",
                                "properties": {},
                                "geometry": {
                                    "type": "Polygon",
                                    "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]],
                                },
                            }
                        ],
                    }
                )
            )
            check(
                "GPX refuses polygons",
                lambda: (
                    not convert.convert_one(convert.inspect(polygon), "gpx", out, 705)["success"]
                ),
            )
            multi = fixtures / "multiple.gpkg"
            convert.run(["ogr2ogr", "-f", "GPKG", multi, inputs["geo"], "-nln", "first"])
            convert.run(["ogr2ogr", "-update", multi, inputs["geo"], "-nln", "second"])
            multi_result = convert.convert_one(convert.inspect(multi), "geojson", out, 706)
            check(
                "all GeoPackage layers exported",
                lambda: (
                    multi_result["success"]
                    and len(list(Path(multi_result["output"]).glob("*.geojson"))) == 2
                ),
            )
        special = fixtures / "quotes ' $() [name].png"
        special.write_bytes(inputs["image"].read_bytes())
        check(
            "quoted filenames convert without shell interpolation",
            lambda: convert.convert_one(convert.inspect(special), "jpg", out, 707)["success"],
        )
        plan = fixtures / "plan.json"
        plan.write_text(
            json.dumps({"image": "png", "config": "yaml", "document": "docx", "video": "opus"})
        )
        mixed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "src/convert.py"),
                "--plan",
                str(plan),
                "--output",
                str(out),
                "--",
                str(inputs["image"]),
                str(inputs["config"]),
                str(inputs["document"]),
                str(inputs["video"]),
                str(inputs["image"]),
                str(fixtures / "missing.file"),
            ],
            text=True,
            capture_output=True,
        )
        events = [json.loads(line) for line in mixed.stdout.splitlines()]
        report = events[-1]
        check(
            "mixed batch continues after a failure and deduplicates inputs",
            lambda: mixed.returncode == 1 and report["success"] == 4 and report["failed"] == 1,
        )
        check(
            "batch report saved",
            lambda: (Path(report["output"]) / "conversion-report.json").is_file(),
        )
        check(
            "staging directories cleaned after failures", lambda: not list(out.rglob(".working-*"))
        )
    evidence["passed_formats"] = sum(r["write"] and r["read"] for r in evidence["formats"])
    evidence["failed_count"] = len(failures)
    path = (
        ROOT
        / "evidence/local"
        / ("format-verification" + ("-" + "-".join(categories) if args.only else "") + ".json")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Evidence: {path}; {len(failures)} failures", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

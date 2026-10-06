#!/usr/bin/env python3
"""Batch cancellation, image dependencies, Shapefile grouping and naming edges."""

import hashlib
import json
import signal
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import convert

checks = []


def check(name, value):
    checks.append({"name": name, "pass": bool(value)})
    print(f"{'PASS' if value else 'FAIL'} {name}", flush=True)


with tempfile.TemporaryDirectory(prefix="ultraconvert-edge-tests-") as tmp:
    work = Path(tmp)
    image = work / "image.png"
    convert.run(["magick", "-size", "64x64", "xc:blue", image])
    md = work / "with-image.md"
    md.write_text("# Media\n\n![Blue](image.png)\n")
    doc = convert.convert_one(convert.inspect(md), "docx", work, 0)
    with zipfile.ZipFile(next(Path(doc["output"]).glob("*.docx"))) as archive:
        names = [n for n in archive.namelist() if n.startswith("word/media/")]
        check(
            "local Markdown image embedded in DOCX",
            bool(names) and archive.read(names[0]) == image.read_bytes(),
        )
    back = convert.convert_one(
        convert.inspect(next(Path(doc["output"]).glob("*.docx"))), "html", work, 1
    )
    bundle = Path(back["output"])
    copied = list((bundle / "media").glob("*.png"))
    html = next(bundle.glob("*.html")).read_text()
    check(
        "DOCX images retained with relative HTML links",
        len(copied) == 1 and copied[0].read_bytes() == image.read_bytes() and "media/" in html,
    )
    missing = work / "missing.md"
    missing.write_text("![Missing](not-here.png)\n")
    check(
        "missing document image refuses silent loss",
        not convert.convert_one(convert.inspect(missing), "docx", work, 2)["success"],
    )
    remote = work / "remote.md"
    remote.write_text("![External](https://example.invalid/image.png)\n")
    check(
        "binary document does not fetch a remote image",
        not convert.convert_one(convert.inspect(remote), "docx", work, 3)["success"],
    )
    points = work / "points.geojson"
    points.write_text(
        '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"id":1},"geometry":{"type":"Point","coordinates":[1,2]}}]}'
    )
    shp_result = convert.convert_one(convert.inspect(points), "shp", work, 4)
    shape = Path(shp_result["output"])
    inspected = subprocess.run(
        [
            sys.executable,
            str(ROOT / "src/convert.py"),
            "--inspect",
            "--",
            *map(str, shape.glob("points.*")),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    check(
        "Finder selection of Shapefile sidecars forms one input",
        len(json.loads(inspected.stdout)["files"]) == 1,
    )
    two_page = work / "pages.tiff"
    convert.run(["magick", "-size", "16x16", "xc:red", "xc:green", two_page])
    pages = convert.convert_one(convert.inspect(two_page), "png", work, 5)
    check(
        "multipage TIFF preserves both pages",
        pages["success"] and len(list(Path(pages["output"]).glob("*.png"))) == 2,
    )
    video = work / "clip.mp4"
    convert.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=320x240:rate=30:duration=2",
            "-c:v",
            "libx264",
            video,
        ]
    )
    bad_ext = work / "clip.mp3"
    bad_ext.write_bytes(video.read_bytes())
    check(
        "media content overrides audio extension on a video",
        convert.inspect(bad_ext)["category"] == "video",
    )
    before = hashlib.sha256(video.read_bytes()).hexdigest()
    task = subprocess.Popen(
        [
            sys.executable,
            str(ROOT / "src/convert.py"),
            "--to",
            "mxf",
            "--output",
            str(work),
            "--jobs",
            "1",
            "--",
            *[str(video)],
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    start = json.loads(task.stdout.readline())
    time.sleep(0.1)
    task.send_signal(signal.SIGTERM)
    stdout, stderr = task.communicate(timeout=30)
    report = json.loads(stdout.splitlines()[-1])
    check(
        "cancellation returns a report and exit 130", task.returncode == 130 and report["cancelled"]
    )
    check(
        "cancellation cleans incomplete output", not list(Path(start["output"]).glob(".working-*"))
    )
    check(
        "cancellation leaves original unchanged",
        hashlib.sha256(video.read_bytes()).hexdigest() == before,
    )

evidence = {
    "date": "2026-10-06",
    "checks": checks,
    "failed_count": sum(not c["pass"] for c in checks),
}
(ROOT / "evidence/local").mkdir(parents=True, exist_ok=True)
(ROOT / "evidence/local/edge-verification.json").write_text(json.dumps(evidence, indent=2) + "\n")
sys.exit(bool(evidence["failed_count"]))

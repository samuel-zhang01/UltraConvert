"""Record reproducible small-file batch throughput without touching user files."""

import hashlib
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
records = []
with tempfile.TemporaryDirectory(prefix="ultraconvert-benchmark-") as temp:
    base = Path(temp)
    files = []
    for index in range(40):
        source = ROOT / "examples" / ("Colour.png" if index % 2 else "Settings.json")
        dest = base / (f"{index:03d}" + source.suffix)
        shutil.copyfile(source, dest)
        files.append(dest)
    hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
    plan = base / "plan.json"
    plan.write_text('{"image":"webp","config":"yaml"}')
    for jobs in (1, 2, 4):
        start = time.perf_counter()
        result = subprocess.run(
            [
                sys.executable,
                ROOT / "src/convert.py",
                "--jobs",
                str(jobs),
                "--plan",
                plan,
                "--output",
                base / f"out-{jobs}",
                *files,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode:
            raise RuntimeError(result.stderr)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        report = events[-1]
        if report.get("success") != 40 or report.get("failed"):
            raise RuntimeError("Benchmark conversion failed")
        records.append(
            {
                "jobs": jobs,
                "files": 40,
                "seconds": round(time.perf_counter() - start, 3),
                "converted": report["success"],
            }
        )
    if hashes != [hashlib.sha256(p.read_bytes()).hexdigest() for p in files]:
        raise RuntimeError("Original fixtures changed")
data = {
    "platform": platform.system(),
    "architecture": platform.machine(),
    "fixture": "20 x 64px PNG to WebP, 20 x JSON to YAML",
    "limitations": "Small-file throughput only; results depend on machine and format. Each engine is limited to two threads; up to four jobs.",
    "results": records,
}
path = ROOT / "evidence/local/benchmark.json"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
print(json.dumps(data, indent=2))

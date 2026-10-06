"""Compile icon sizes and ICNS from the final generated master artwork."""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
assets = ROOT / "assets"
master = assets / "icon-master.png"


def run(*args):
    subprocess.run(list(map(str, args)), check=True, stdout=subprocess.DEVNULL)


assets.mkdir(exist_ok=True)
run("/usr/bin/swift", ROOT / "scripts/render_icon.swift", master)
run("sips", "-z", "1024", "1024", master, "--out", assets / "icon.png")
run("sips", "-z", "128", "128", master, "--out", assets / "logo.png")
with tempfile.TemporaryDirectory(prefix="ultraconvert-icons-") as temp:
    iconset = Path(temp) / "UltraConvert.iconset"
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            run("sips", "-z", size * scale, size * scale, master, "--out", iconset / name)
    run("iconutil", "-c", "icns", iconset, "-o", assets / "UltraConvert.icns")
print("Built icon.png, logo.png and UltraConvert.icns")

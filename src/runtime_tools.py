"""Resolve the same local conversion engines for batches and setup checks."""

import shutil
from pathlib import Path


def tool(name):
    if name in ("ffmpeg", "ffprobe"):
        for prefix in ("/opt/homebrew/opt/ffmpeg-full/bin", "/usr/local/opt/ffmpeg-full/bin"):
            full = Path(prefix) / name
            if full.exists():
                return str(full)
    if name == "ebook-convert":
        p = Path("/Applications/calibre.app/Contents/MacOS/ebook-convert")
        if p.exists():
            return str(p)
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"):
        path = Path(prefix) / name
        if path.exists():
            return str(path)
    found = shutil.which(name)
    if found:
        return found
    raise FileNotFoundError(
        f"Missing conversion tool: {name}. Run install.py from the source repository."
    )

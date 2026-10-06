"""Resolve the same local conversion engines for batches and setup checks."""

import json
import os
import shutil
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=8)
def bundled_runtime(source=None):
    """A sealed app manifest is authoritative; never fall back from an incomplete bundle."""
    source = Path(__file__).resolve().parent if source is None else Path(source).resolve()
    manifest = source.parent / "runtime-manifest.json"
    if not manifest.exists():
        return None
    data = json.loads(manifest.read_text())
    if data.get("schema") != 1 or not isinstance(data.get("tools"), dict):
        raise ValueError("Invalid bundled runtime manifest")
    contents = manifest.parent.parent.resolve()

    def inside(relative):
        if not isinstance(relative, str) or Path(relative).is_absolute():
            raise ValueError("Invalid bundled runtime path")
        path = (contents / relative).resolve()
        if not path.is_relative_to(contents) or not path.exists():
            raise ValueError("Bundled runtime is incomplete or points outside the app")
        return str(path)

    tools = {name: inside(path) for name, path in data["tools"].items()}
    allowed = {"GDAL_DATA", "PROJ_DATA", "MAGICK_CONFIGURE_PATH", "MAGICK_CODER_MODULE_PATH"}
    paths = data.get("environment_paths", {})
    if not isinstance(paths, dict) or set(paths) - allowed:
        raise ValueError("Invalid bundled runtime environment")
    environment = {name: inside(path) for name, path in paths.items()}
    environment["PATH"] = str(contents / "Helpers") + ":/usr/bin:/bin:/usr/sbin:/sbin"
    # Our conversion policy must precede ImageMagick's packaged configuration.
    environment["MAGICK_CONFIGURE_PATH"] = str(source) + (
        ":" + environment["MAGICK_CONFIGURE_PATH"] if "MAGICK_CONFIGURE_PATH" in environment else ""
    )
    environment["GDAL_DRIVER_PATH"] = "disable"
    return {"tools": tools, "environment": environment}


def runtime_environment():
    runtime = bundled_runtime()
    return {} if runtime is None else runtime["environment"]


def tool(name):
    runtime = bundled_runtime()
    if runtime is not None:
        if name in ("sips", "iconutil", "file"):
            return str(Path("/usr/bin") / name)
        path = runtime["tools"].get(name)
        if path and os.access(path, os.X_OK):
            return path
        raise FileNotFoundError(
            f"Missing bundled conversion tool: {name}. Replace the app with a complete download."
        )
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

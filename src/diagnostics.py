"""Read-only, local setup checks. No selected files or network requests."""

import concurrent.futures
import json
import os
import platform
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

from runtime_tools import bundled_runtime, runtime_environment, tool

PROBES = {
    "FFmpeg": ("ffmpeg", "-version"),
    "FFprobe": ("ffprobe", "-version"),
    "ImageMagick": ("magick", "-version"),
    "Pandoc": ("pandoc", "--version"),
    "Calibre": ("ebook-convert", "--version"),
    "Monkey's Audio": ("mac",),
}


def repair_message():
    return (
        "Replace the app with a complete download."
        if bundled_runtime() is not None
        else "Re-run install.py."
    )


def probe(name, args):
    try:
        executable = tool(args[0])
        with tempfile.TemporaryFile() as log:
            result = subprocess.run(
                [executable, *args[1:]],
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=8,
                check=False,
                env={**os.environ, **runtime_environment(), "PYTHONDONTWRITEBYTECODE": "1"},
            )
            log.seek(0)
            text = log.read(4096).decode("utf-8", errors="replace").strip()
        # The APE frontend prints its banner and usage with exit 255 when no files are given.
        banner = text.splitlines()[0] if text else ""
        ok = result.returncode == 0 or (
            args == ("mac",) and result.returncode == 255 and "Monkey's Audio" in banner
        )
        return {
            "name": name,
            "ok": ok,
            "detail": banner[:180] if ok else "Engine did not start correctly. " + repair_message(),
        }
    except FileNotFoundError:
        return {"name": name, "ok": False, "detail": "Missing. " + repair_message()}
    except OSError, subprocess.TimeoutExpired:
        return {
            "name": name,
            "ok": False,
            "detail": "Could not start within 8 seconds. " + repair_message(),
        }


def check_packages():
    try:
        isolated = ["-I", "-B"]
        setup = ""
        if bundled_runtime() is not None:
            isolated.append("-S")
            packages = (
                Path(sys.base_prefix)
                / "lib"
                / f"python{sys.version_info.major}.{sys.version_info.minor}"
                / "site-packages"
            )
            setup = f"import sys; sys.path.insert(0, {str(packages)!r}); "
        # Isolated import in the installed interpreter checks the actual GDAL ABI and parsers.
        result = subprocess.run(
            [
                sys.executable,
                *isolated,
                "-c",
                setup + "from osgeo import gdal; import yaml, tomli_w, defusedxml; "
                "print('GDAL ' + gdal.VersionInfo('RELEASE_NAME') + '; safe parsers available')",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=8,
            check=False,
        )
        ok = result.returncode == 0
        return {
            "name": "GDAL and Python packages",
            "ok": ok,
            "detail": result.stdout.decode(errors="replace").strip()[:180]
            if ok
            else "Imports failed. " + repair_message(),
        }
    except OSError, subprocess.TimeoutExpired:
        return {
            "name": "GDAL and Python packages",
            "ok": False,
            "detail": "Runtime check could not finish.",
        }


def check_workflow(path):
    try:
        info = path / "Contents/Info.plist"
        if info.stat().st_size > 65536:
            raise ValueError("Oversized metadata")
        data = plistlib.loads(info.read_bytes())
        if not isinstance(data, dict) or not isinstance(data.get("NSServices"), list):
            raise ValueError("Invalid service metadata")
        service = data["NSServices"][0]
        if not isinstance(service, dict):
            raise ValueError("Invalid service entry")
        icon = service.get("NSIconName")
        ok = (
            icon == "workflowCustomImage"
            and (path / "Contents/Resources/workflowCustomImage.png").is_file()
            and (path / "Contents/document.wflow").is_file()
        )
        return {
            "name": path.stem,
            "ok": ok,
            "detail": "Installed with icon. Check its switch in Finder Settings."
            if ok
            else "Incomplete workflow. Re-run install.py.",
        }
    except OSError, ValueError, KeyError, IndexError, TypeError, plistlib.InvalidFileException:
        return {"name": path.stem, "ok": False, "detail": "Missing or invalid. Re-run install.py."}


def check_setup(home=None):
    home = Path.home() if home is None else Path(home)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        checks = list(pool.map(lambda item: probe(*item), PROBES.items()))
    checks.append(check_packages())
    checks.append(
        {
            "name": "Native icon tools",
            "ok": all(Path("/usr/bin", name).is_file() for name in ("sips", "iconutil")),
            "detail": "macOS sips and iconutil are required for ICNS output.",
        }
    )
    for name in ("Convert Here with UltraConvert", "Convert to Destination with UltraConvert"):
        checks.append(check_workflow(home / "Library/Services" / (name + ".workflow")))
    return {
        "ok": all(check["ok"] for check in checks),
        "environment": f"macOS {platform.mac_ver()[0]} · {platform.machine()} · Python {platform.python_version()}",
        "checks": checks,
        "note": "Availability checks, not a conversion test. Finder enablement and folder permissions must be checked in macOS. Nothing is uploaded.",
    }


if __name__ == "__main__":
    report = check_setup()
    print(json.dumps(report))
    sys.exit(0 if report["ok"] else 1)

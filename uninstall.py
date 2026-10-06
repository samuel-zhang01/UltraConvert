#!/usr/bin/env python3
"""Move only this managed app, service and runtime to Trash. Retain shared engines."""

import datetime
import fcntl
import json
import shutil
import subprocess
import uuid
from pathlib import Path

home_dir = Path.home()
targets = [
    (home_dir / "Applications/UltraConvert.app", "Contents/Resources/ultraconvert-managed.json"),
    (
        home_dir / "Library/Services/Convert Files with UltraConvert.workflow",
        "Contents/ultraconvert-managed.json",
    ),
    (
        home_dir / "Library/Services/Convert Here with UltraConvert.workflow",
        "Contents/ultraconvert-managed.json",
    ),
    (
        home_dir / "Library/Services/Convert to Destination with UltraConvert.workflow",
        "Contents/ultraconvert-managed.json",
    ),
    (home_dir / "Library/Application Support/UltraConvert", "installation.json"),
]
runtime = targets[-1][0]
lock = None
if runtime.exists() and not runtime.is_symlink():
    lock = (runtime / "install.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
for path, marker in targets:
    if not path.exists() and not path.is_symlink():
        continue
    try:
        data = json.loads((path / marker).read_text())
    except OSError, ValueError:
        data = {}
    owned = data.get("owner") == "UltraConvert" or (
        path == runtime and data.get("app") == str(targets[0][0])
    )
    if path.is_symlink() or not owned:
        raise RuntimeError(f"Unmanaged path; not removed: {path}")
trash = (
    home_dir
    / ".Trash"
    / (
        "UltraConvert "
        + datetime.datetime.now().strftime("%Y-%m-%d %H-%M-%S ")
        + uuid.uuid4().hex[:6]
    )
)
trash.mkdir(parents=True)
for path, _marker in targets:
    if path.exists():
        shutil.move(path, trash / ("Runtime" if path.name == "UltraConvert" else path.name))
subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=True)
print(
    f"Moved managed installation to {trash}. Shared Homebrew tools and converted files were retained."
)

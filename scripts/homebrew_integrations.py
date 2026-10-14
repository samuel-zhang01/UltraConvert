"""Remove only owned Finder actions for the cask's exact app; retain all user data."""

import argparse
import datetime
import json
import plistlib
import shlex
import shutil
import uuid
from pathlib import Path

NAMES = (
    "Convert Files with UltraConvert.workflow",
    "Convert Here with UltraConvert.workflow",
    "Convert to Destination with UltraConvert.workflow",
)


def remove_actions(app, home=None):
    home = Path.home() if home is None else Path(home)
    app = Path(app)
    if not app.is_absolute() or app.name != "UltraConvert.app":
        raise ValueError("Supply the cask's absolute UltraConvert.app path")
    services = home / "Library/Services"
    if services.is_symlink():
        raise ValueError("Services is a symlink; no actions were removed")
    owned = []
    for name in NAMES:
        path = services / name
        marker = path / "Contents/ultraconvert-managed.json"
        document = path / "Contents/document.wflow"
        if not path.exists() or any(
            p.is_symlink() for p in [path, path / "Contents", marker, document]
        ):
            continue
        try:
            if marker.stat().st_size > 4096 or document.stat().st_size > 1024 * 1024:
                continue
            owner = json.loads(marker.read_text())
            data = plistlib.loads(document.read_bytes())
            commands = [a["action"]["ActionParameters"]["COMMAND_STRING"] for a in data["actions"]]
            targets_app = any(str(app) in shlex.split(command) for command in commands)
        except OSError, ValueError, KeyError, TypeError:
            continue
        if isinstance(owner, dict) and owner.get("owner") == "UltraConvert" and targets_app:
            owned.append(path)
    if not owned:
        return 0
    trash = home / ".Trash"
    if trash.is_symlink():
        raise ValueError("Trash is a symlink; no actions were removed")
    destination = trash / (
        "UltraConvert Finder actions "
        + datetime.datetime.now().strftime("%Y-%m-%d ")
        + uuid.uuid4().hex[:8]
    )
    destination.mkdir(parents=True)
    for path in owned:
        shutil.move(str(path), destination / path.name)
    return len(owned)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    print(
        f"Moved {remove_actions(args.app)} owned Finder actions to Trash; settings and folder rules retained."
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Install the native app and Finder Quick Action for the current user."""

import argparse
import datetime
import fcntl
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from package_app import build_app, validate_prebuilt

ROOT = Path(__file__).resolve().parent
HOME_DIR = Path.home()
SUPPORT = HOME_DIR / "Library/Application Support/UltraConvert"
APP = HOME_DIR / "Applications/UltraConvert.app"
SERVICE = HOME_DIR / "Library/Services/Convert Files with UltraConvert.workflow"
SERVICES = {
    "here": HOME_DIR / "Library/Services/Convert Here with UltraConvert.workflow",
    "destination": HOME_DIR / "Library/Services/Convert to Destination with UltraConvert.workflow",
}


def run(args):
    subprocess.run(list(map(str, args)), check=True)


def workflow(path, mode="destination"):
    contents = path / "Contents"
    contents.mkdir(parents=True)
    command = (
        f'/usr/bin/open -n -a "$HOME/Applications/UltraConvert.app" --args --mode {mode} -- "$@"'
    )
    action = {
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "BundleIdentifier": "com.apple.RunShellScript",
        "ActionParameters": {
            "COMMAND_STRING": command,
            "inputMethod": 1,
            "shell": "/bin/zsh",
            "source": "",
            "CheckedForUserDefaultShell": True,
        },
        "AMAccepts": {"Container": "List", "Optional": False, "Types": ["com.apple.cocoa.string"]},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3",
        "AMApplication": ["Automator"],
        "Class Name": "RunShellScriptAction",
        "isViewVisible": True,
        "CanShowWhenRun": True,
        "CanShowSelectedItemsWhenRun": False,
        "InputUUID": str(uuid.uuid4()),
        "OutputUUID": str(uuid.uuid4()),
        "UUID": str(uuid.uuid4()),
        "Category": ["AMCategoryUtilities"],
        "CFBundleVersion": "2.0.3",
        "AMParameterProperties": {
            key: {}
            for key in (
                "COMMAND_STRING",
                "inputMethod",
                "shell",
                "source",
                "CheckedForUserDefaultShell",
            )
        },
    }
    meta = {
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        "applicationBundleID": "com.apple.finder",
        "applicationBundleIDsByPath": {
            "/System/Library/CoreServices/Finder.app": "com.apple.finder"
        },
        "applicationPath": "/System/Library/CoreServices/Finder.app",
        "applicationPaths": ["/System/Library/CoreServices/Finder.app"],
        "serviceApplicationBundleID": "com.apple.finder",
        "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
        "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "outputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "presentationMode": 15,
        "processesInput": 0,
        "serviceProcessesInput": 0,
        "useAutomaticInputType": 0,
        "systemImageName": "NSActionTemplate",
    }
    document = {
        "AMDocumentVersion": "2",
        "AMApplicationVersion": "2.10",
        "AMApplicationBuild": "525",
        "actions": [{"action": action, "isViewVisible": True}],
        "connectors": {},
        "workflowMetaData": meta,
    }
    (contents / "document.wflow").write_bytes(plistlib.dumps(document))
    service_info = {
        "NSServices": [
            {
                "NSMenuItem": {"default": path.stem},
                "NSBackgroundColorName": "background",
                "NSMessage": "runWorkflowAsService",
                "NSIconName": "NSActionTemplate",
                "NSSendFileTypes": ["public.item"],
                "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            }
        ]
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(service_info))
    (contents / "ultraconvert-managed.json").write_text('{"owner":"UltraConvert"}\n')


def managed(path, marker, legacy_runtime=False):
    if path.is_symlink():
        return False
    try:
        data = json.loads((path / marker).read_text())
        return data.get("owner") == "UltraConvert" or (
            legacy_runtime and data.get("app") == str(APP)
        )
    except (OSError, ValueError):
        return False


def install_payload(payload):
    """Stage all files, swap by rename, and roll back every swap on failure."""
    transaction = uuid.uuid4().hex[:12]
    backup = (
        SUPPORT
        / "backups"
        / (datetime.datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M-%S_") + transaction)
    )
    staged, swapped = [], []
    try:
        for source, dest in payload:
            dest.parent.mkdir(parents=True, exist_ok=True)
            fresh = dest.parent / (".ultraconvert-new-" + transaction + "-" + dest.name)
            old = dest.parent / (".ultraconvert-old-" + transaction + "-" + dest.name)
            staged.append((fresh, dest, old))
            shutil.copytree(source, fresh, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            if dest.exists() and dest.suffix == ".app":
                backup.mkdir(parents=True, exist_ok=True)
                zipped = backup / (dest.name + ".zip")
                run(["/usr/bin/ditto", "-c", "-k", "--keepParent", dest, zipped])
                with zipfile.ZipFile(zipped) as archive:
                    if archive.testzip() is not None:
                        raise RuntimeError(
                            "App backup failed verification; installation was retained"
                        )
                    for path in dest.rglob("*"):
                        if path.is_file() and not path.is_symlink():
                            saved = archive.read(dest.name + "/" + str(path.relative_to(dest)))
                            if (
                                hashlib.sha256(saved).digest()
                                != hashlib.sha256(path.read_bytes()).digest()
                            ):
                                raise RuntimeError("App backup differs; installation was retained")
        for fresh, dest, old in staged:
            if dest.exists():
                dest.rename(old)
            swapped.append((fresh, dest, old))
            fresh.rename(dest)
    except BaseException:
        for _fresh, dest, old in reversed(swapped):
            if dest.exists():
                shutil.rmtree(dest)
            if old.exists():
                old.rename(dest)
        raise
    finally:
        for fresh, _, _ in staged:
            if fresh.exists():
                shutil.rmtree(fresh)
    # The transaction has committed. Retain old runtimes/workflows as backups;
    # keep old apps zipped to prevent duplicate LaunchServices registrations.
    for _, dest, old in swapped:
        if old.exists():
            if dest.suffix == ".app":
                shutil.rmtree(old)
            else:
                backup.mkdir(parents=True, exist_ok=True)
                old.rename(backup / dest.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-deps", action="store_true", help="Dependencies were already installed"
    )
    parser.add_argument(
        "--build-from-source",
        action="store_true",
        help="Compile even if release contains a prebuilt app",
    )
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise RuntimeError("The native app and Finder actions require macOS")
    for path, marker in [
        (APP, "Contents/Resources/ultraconvert-managed.json"),
        *[(p, "Contents/ultraconvert-managed.json") for p in [SERVICE, *SERVICES.values()]],
    ]:
        if (path.exists() or path.is_symlink()) and not managed(path, marker):
            raise RuntimeError(f"Unmanaged installation; left in place: {path}")
    if SUPPORT.is_symlink() or (
        SUPPORT.exists() and not managed(SUPPORT, "installation.json", legacy_runtime=True)
    ):
        raise RuntimeError(f"Unmanaged runtime; left in place: {SUPPORT}")
    if (SUPPORT / "src").is_symlink() or (SUPPORT / ".venv").is_symlink():
        raise RuntimeError("Runtime source/environment must not be symlinks")
    SUPPORT.mkdir(parents=True, exist_ok=True)
    # Record ownership before initial dependency setup, so interrupted installs can retry.
    if not (SUPPORT / "installation.json").exists():
        (SUPPORT / "installation.json").write_text('{"owner":"UltraConvert"}\n')
    lock = (SUPPORT / "install.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("Another UltraConvert installation is running") from None
    if not args.skip_deps:
        brew = shutil.which("brew")
        if not brew:
            raise RuntimeError("Install Homebrew first from https://brew.sh")
        for name in ("ffmpeg-full", "imagemagick", "pandoc", "gdal", "mac", "python@3.14"):
            if subprocess.run(
                [brew, "list", "--versions", name], stdout=subprocess.DEVNULL, check=False
            ).returncode:
                run([brew, "install", name])
        if not Path("/Applications/calibre.app").exists():
            run([brew, "install", "--cask", "calibre"])
    python = Path("/opt/homebrew/opt/python@3.14/bin/python3.14")
    if not python.exists():
        python = Path("/usr/local/opt/python@3.14/bin/python3.14")
    if not python.exists():
        raise RuntimeError("Homebrew Python 3.14 is required for the installed GDAL bindings")
    SUPPORT.mkdir(parents=True, exist_ok=True)
    if not (SUPPORT / ".venv/bin/python").exists():
        run([python, "-m", "venv", "--system-site-packages", SUPPORT / ".venv"])
    runtime = SUPPORT / ".venv/bin/python"
    run(
        [
            runtime,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "-r",
            ROOT / "requirements.txt",
        ]
    )
    run(
        [
            runtime,
            "-c",
            "from osgeo import gdal; import yaml, tomli_w, defusedxml; print('GDAL', gdal.VersionInfo())",
        ]
    )
    with tempfile.TemporaryDirectory(prefix="ultraconvert-convert-install-") as temp:
        build = Path(temp)
        prebuilt = ROOT / "prebuilt/UltraConvert.app"
        app = (
            validate_prebuilt(prebuilt)
            if prebuilt.exists() and not args.build_from_source
            else build_app(build)
        )
        prepared_services = {}
        for mode, path in SERVICES.items():
            service = build / path.name
            workflow(service, mode)
            prepared_services[path] = service
        # Compile/validate and stage everything before replacing a working installation.
        install_payload(
            [
                (ROOT / "src", SUPPORT / "src"),
                (app, APP),
                *[(source, path) for path, source in prepared_services.items()],
            ]
        )
        if SERVICE.exists():
            backup = SUPPORT / "backups" / ("legacy-workflow-" + uuid.uuid4().hex[:8])
            backup.mkdir(parents=True)
            shutil.move(SERVICE, backup / SERVICE.name)
    run(
        [
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "-f",
            APP,
        ]
    )
    run(["/System/Library/CoreServices/pbs", "-update"])
    inventory = {
        "owner": "UltraConvert",
        "source": str(ROOT),
        "app": str(APP),
        "services": list(map(str, SERVICES.values())),
        "runtime": str(SUPPORT),
        "installed_date": datetime.datetime.now().astimezone().date().isoformat(),
        "source_sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (ROOT / "src").glob("*")
            if p.is_file()
        },
    }
    (SUPPORT / "installation.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(
        f"Installed app: {APP}\nFinder Quick Actions: "
        + ", ".join(path.stem for path in SERVICES.values())
        + f"\nRuntime: {SUPPORT}\nEnable both actions in System Settings → Login Items & Extensions → Finder."
    )


if __name__ == "__main__":
    main()

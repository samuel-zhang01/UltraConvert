#!/usr/bin/env python3
"""Run maintained native gates without installing into the owner's home."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT))
import package_app

import install


def run(args, **kwargs):
    subprocess.run([str(value) for value in args], cwd=ROOT, check=True, **kwargs)


def main():
    if sys.platform != "darwin" or sys.version_info[:2] != (3, 14):
        raise RuntimeError("Native CI requires macOS with Python 3.14 and installed public engines")
    os.umask(0o077)
    parent = os.environ.get("RUNNER_TEMP")
    with tempfile.TemporaryDirectory(prefix="ultraconvert-native-ci-", dir=parent) as temporary:
        work = Path(temporary)
        # Compile/sign only a disposable ad-hoc development app. Do not launch
        # its normal entrypoint or call install.main/install_payload.
        app = package_app.build_app(work)
        native = app / "Contents/MacOS/UltraConvert"
        version = subprocess.check_output([str(native), "--version"], text=True).strip()
        if version != (ROOT / "VERSION").read_text().strip():
            raise RuntimeError("Native version command does not match VERSION")
        fixture_home = work / "fixture-home"
        actions = fixture_home / "Library/Services"
        for mode, name in (
            ("here", "Convert Here with UltraConvert"),
            ("destination", "Convert to Destination with UltraConvert"),
        ):
            install.workflow(actions / (name + ".workflow"), mode, app_path=app)
        run(
            [
                app / "Contents/MacOS/UltraConvert",
                "--brand-workflows",
                *sorted(actions.glob("*.workflow")),
            ]
        )
        fixture_support = fixture_home / "Library/Application Support/UltraConvert"
        fixture_support.mkdir(parents=True)
        (fixture_support / ".venv").symlink_to(Path(sys.prefix), target_is_directory=True)
        cli_environment = {
            **os.environ,
            "HOME": str(fixture_home),
            "CFFIXED_USER_HOME": str(fixture_home),
        }
        cli_setup = json.loads(
            subprocess.check_output([str(native), "--check-setup"], text=True, env=cli_environment)
        )
        if not cli_setup["ok"]:
            raise RuntimeError("Native setup command failed against disposable fixtures")
        for filename in ("test_conversion.py", "test_edges.py"):
            run([sys.executable, ROOT / "tests" / filename])
        report = work / "interface.json"
        with report.open("w") as output:
            run(
                [
                    sys.executable,
                    ROOT / "src/convert.py",
                    "--inspect",
                    "--",
                    *sorted((ROOT / "examples").glob("*")),
                ],
                stdout=output,
            )
        sources = sorted((ROOT / "src").glob("*.swift"))
        for name in (
            "interface",
            "guidance",
            "backend",
            "automation",
            "rule_editor",
            "updates",
            "startup",
            "settings",
            "compression",
            "report",
        ):
            binary = work / ("test-" + name)
            run(
                [
                    "xcrun",
                    "swiftc",
                    "-Osize",
                    "-parse-as-library",
                    "-D",
                    "ULTRACONVERT_INTERFACE_TESTS",
                    "-framework",
                    "AppKit",
                    *sources,
                    ROOT / "tests" / ("test_" + name + ".swift"),
                    "-o",
                    binary,
                ]
            )
            arguments = [report] if name == "interface" else [actions] if name == "backend" else []
            run([binary, *arguments])
        for name in (
            "security",
            "batch",
            "installer",
            "diagnostics",
            "release",
            "runtime",
            "compression",
        ):
            run(
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    "tests",
                    "-p",
                    "test_" + name + ".py",
                    "-v",
                ],
                env={**os.environ, "ULTRACONVERT_TEST_APP": str(app)},
            )
        # Explicit fixture home makes this setup check independent of owner's
        # installed Finder actions or runtime state.
        sys.path.insert(0, str(ROOT / "src"))
        import diagnostics

        setup = diagnostics.check_setup(home=fixture_home)
        print(json.dumps(setup))
        if not setup["ok"]:
            raise RuntimeError("Disposable native setup checks failed")


if __name__ == "__main__":
    main()

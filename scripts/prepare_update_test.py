"""Build an isolated real-app update fixture; never install it over UltraConvert.

Run on macOS with --sign-identity. Serve OUTPUT/feed on localhost:8768, then
open OUTPUT/installed/UltraConvert.app and use Check for Updates. Only this
explicit test build permits a local HTTP feed and uses its isolated support folder.
"""

import argparse
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

import sparkle
from package_app import build_app, developer_id_identity


def prepare(output, identity):
    output = output.resolve()
    if output.exists():
        raise RuntimeError("Choose a new test directory")
    output.mkdir(parents=True)
    support = output / "support"
    support.mkdir()
    engine = Path.home() / "Library/Application Support/UltraConvert/.venv"
    (support / ".venv").symlink_to(engine, target_is_directory=True)
    config = {
        "CFBundleIdentifier": "local.ultraconvert.update-qa",
        "CFBundleDisplayName": "UltraConvert Update Test",
        "CFBundleVersion": "1.7.99",
        "CFBundleShortVersionString": "1.7.99",
        "UCUpdateTestSupport": str(support),
        "SUFeedURL": "http://localhost:8768/appcast.xml",
        "SUEnableAutomaticChecks": False,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    }
    installed = build_app(output / "installed", sign_identity=identity, update_test_config=config)
    candidate = output / "candidate/UltraConvert.app"
    shutil.copytree(installed, candidate, symlinks=True)
    info_path = candidate / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleVersion"] = "1.8.0"
    info["CFBundleShortVersionString"] = "1.8.0"
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(
        [
            "/usr/bin/codesign",
            "--force",
            "--sign",
            developer_id_identity(identity),
            "--options",
            "runtime",
            "--timestamp",
            str(candidate),
        ],
        check=True,
    )
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(candidate)], check=True
    )
    feed = output / "feed"
    feed.mkdir()
    archive = feed / "UltraConvert-1.8.0-test-update.zip"
    subprocess.run(
        ["/usr/bin/ditto", "-c", "-k", "--keepParent", str(candidate), str(archive)], check=True
    )
    with sparkle.distribution() as dependency:
        subprocess.run(
            [
                str(dependency / "bin/generate_appcast"),
                "--account",
                sparkle.KEY_ACCOUNT,
                "--maximum-deltas",
                "0",
                "--download-url-prefix",
                "http://localhost:8768/",
                str(feed),
            ],
            check=True,
        )
        subprocess.run(
            [
                str(dependency / "bin/sign_update"),
                "--account",
                sparkle.KEY_ACCOUNT,
                "--verify",
                str(feed / "appcast.xml"),
            ],
            check=True,
        )
    (output / "fixture.json").write_text(
        json.dumps(
            {
                "installed": str(installed),
                "candidate": str(candidate),
                "support": str(support),
                "feed": str(feed),
                "old_version": "1.7.99",
                "new_version": "1.8.0",
                "notarized": False,
            },
            indent=2,
        )
        + "\n"
    )
    return installed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sign-identity", required=True)
    args = parser.parse_args()
    print(prepare(args.output, args.sign_identity))

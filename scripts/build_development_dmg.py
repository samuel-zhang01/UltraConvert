"""Package a locally verified standalone app as a drag-to-Applications preview."""

import argparse
import hashlib
import json
import platform
import plistlib
import subprocess
import tempfile
from pathlib import Path


def build_dmg(app, output):
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    inventory = json.loads((app / "Contents/Resources/ThirdParty/inventory.json").read_text())
    if (
        info.get("CFBundleIdentifier") != "local.ultraconvert"
        or inventory.get("public_distribution_ready") is not False
    ):
        raise RuntimeError("This packager accepts only marked UltraConvert development bundles")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], check=True)
    output.mkdir(parents=True, exist_ok=False)
    version = info["CFBundleShortVersionString"]
    dmg = output / f"UltraConvert-{version}-standalone-development-{platform.machine()}.dmg"
    with tempfile.TemporaryDirectory(prefix="ultraconvert-dev-dmg-") as temp:
        stage = Path(temp)
        subprocess.run(["/usr/bin/ditto", app, stage / "UltraConvert.app"], check=True)
        (stage / "Applications").symlink_to("/Applications", target_is_directory=True)
        (stage / "READ ME.txt").write_text(
            "UltraConvert standalone development preview\n\nDrag UltraConvert.app to Applications, eject this disk image, then open the installed app. Engines are bundled; no Terminal/Homebrew setup is needed on launch. Enable Finder actions in System Settings.\n\nApple Silicon/macOS "
            + inventory["minimum_macos"]
            + "+. This locally built preview is not notarized or approved for public binary distribution.\n"
        )
        subprocess.run(
            [
                "/usr/bin/hdiutil",
                "create",
                "-volname",
                "UltraConvert Development",
                "-srcfolder",
                stage,
                "-format",
                "UDZO",
                "-fs",
                "APFS",
                dmg,
            ],
            check=True,
        )
    subprocess.run(["/usr/bin/hdiutil", "verify", dmg], check=True)
    with dmg.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    (output / "SHA256SUMS.txt").write_text(digest + "  " + dmg.name + "\n")
    (output / "RELEASE-METADATA.json").write_text(
        json.dumps(
            {
                "version": version,
                "architecture": platform.machine(),
                "minimum_macos": inventory["minimum_macos"],
                "development_preview": True,
                "standalone_runtime": True,
                "notarized": False,
                "public_distribution_ready": False,
                "sha256": digest,
            },
            indent=2,
        )
        + "\n"
    )
    return dmg


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(build_dmg(args.app, args.output))

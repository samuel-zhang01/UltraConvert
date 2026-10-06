"""Package the committed source and matching native app without local evidence/caches."""

import argparse
import hashlib
import io
import json
import platform
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

from notarize import notarize, staple
from package_app import ROOT, build_app, developer_id_identity, validate_prebuilt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--sign-identity", help="Exact Developer ID Application name or SHA-1 in Keychain"
)
parser.add_argument(
    "--notary-profile", help="Existing notarytool Keychain profile; requires --sign-identity"
)
parser.add_argument(
    "--dmg", action="store_true", help="Also package an installer-source disk image"
)
parser.add_argument(
    "--output-dir", type=Path, help="New artifact directory; defaults to dist/VERSION"
)
args = parser.parse_args()
if args.notary_profile and not args.sign_identity:
    parser.error("--notary-profile requires --sign-identity")
if args.sign_identity:
    developer_id_identity(args.sign_identity)
if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).strip():
    raise RuntimeError("Commit the public working tree before building a release")
version = (ROOT / "VERSION").read_text().strip()
arch = platform.machine()
out = args.output_dir or ROOT / "dist" / version
out.mkdir(parents=True, exist_ok=True)
if any(out.glob("UltraConvert-*")):
    raise RuntimeError(
        "Release artifacts already exist here. Choose a new --output-dir to preserve them."
    )
# git archive includes precisely the committed public tree, without ignored/private files.
source = subprocess.check_output(["git", "archive", "HEAD"], cwd=ROOT)
with tempfile.TemporaryDirectory(prefix="ultraconvert-release-") as temp:
    base = Path(temp)
    folder = base / "UltraConvert"
    folder.mkdir()
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        archive.extractall(folder, filter="data")
    installation_note = (
        f"UltraConvert {version} — native app with runtime installer\n\n"
        "This package installs conversion engines separately. Keep this complete folder together.\n"
        "1. Install Homebrew from https://brew.sh if needed.\n"
        "2. In Terminal, type cd followed by a space, drag this UltraConvert folder into Terminal, and press Return.\n"
        "3. Run: python3 install.py\n"
        "4. Open the installed app in ~/Applications. Enable its Quick Actions in macOS Finder Settings.\n\n"
        "The prebuilt app alone does not install its runtime. The DMG is an installer folder, not a drag-only installer.\n"
        + (
            "This build is not Apple notarized. If macOS blocks the prebuilt app, install Apple's Command Line Tools and run python3 install.py --build-from-source. Do not disable Gatekeeper.\n"
            if not args.notary_profile
            else "Apple accepted notarization and the app/DMG tickets are stapled.\n"
        )
        + "\nRead README.md for complete instructions, usage and tested system limits.\n"
    )
    (folder / "INSTALL-FIRST.txt").write_text(installation_note)
    app = build_app(base / "native", sign_identity=args.sign_identity)
    if args.notary_profile:
        submission = base / "notary-app.zip"
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, submission], check=True)
        notarize(submission, args.notary_profile)
        staple(app)
        subprocess.run(
            ["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app], check=True
        )
    validate_prebuilt(app)
    (folder / "prebuilt").mkdir()
    subprocess.run(["/usr/bin/ditto", app, folder / "prebuilt/UltraConvert.app"], check=True)
    bundle = out / f"UltraConvert-{version}-macos-{arch}.zip"
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", folder, bundle], check=True)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Release archive integrity check failed")
    artifacts = [bundle]
    if args.dmg:
        dmg = out / f"UltraConvert-{version}-macos-{arch}.dmg"
        # The app requires its engine/runtime installer. Keep the release folder together.
        container = base / "disk-image"
        container.mkdir()
        (container / "INSTALL-FIRST.txt").write_text(installation_note)
        subprocess.run(["/usr/bin/ditto", folder, container / "UltraConvert"], check=True)
        subprocess.run(
            [
                "/usr/bin/hdiutil",
                "create",
                "-volname",
                "UltraConvert",
                "-srcfolder",
                container,
                "-format",
                "UDZO",
                "-fs",
                "APFS",
                dmg,
            ],
            check=True,
        )
        subprocess.run(["/usr/bin/hdiutil", "verify", dmg], check=True)
        if args.sign_identity:
            subprocess.run(
                [
                    "/usr/bin/codesign",
                    "--sign",
                    developer_id_identity(args.sign_identity),
                    "--timestamp",
                    dmg,
                ],
                check=True,
            )
        if args.notary_profile:
            notarize(dmg, args.notary_profile)
            staple(dmg)
            subprocess.run(
                [
                    "/usr/sbin/spctl",
                    "--assess",
                    "--type",
                    "open",
                    "--context",
                    "context:primary-signature",
                    "--verbose=2",
                    dmg,
                ],
                check=True,
            )
        artifacts.append(dmg)
    source_path = out / f"UltraConvert-{version}-source.tar.gz"
    subprocess.run(
        ["git", "archive", "--format=tar.gz", "--prefix=UltraConvert/", "-o", source_path, "HEAD"],
        cwd=ROOT,
        check=True,
    )
artifacts.append(source_path)
metadata = out / "RELEASE-METADATA.json"
metadata.write_text(
    json.dumps(
        {
            "version": version,
            "commit": subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
            ).strip(),
            "architecture": arch,
            "signing": "Developer ID Application" if args.sign_identity else "ad-hoc",
            "hardened_runtime": True,
            "apple_notarization_accepted_and_stapled": bool(args.notary_profile),
            "engine_runtime_installer_required": True,
            "artifact_kind": "native_app_and_source_installer",
            "standalone_runtime": False,
            "conversion_engines_bundled": False,
            "minimum_macos_native_app": "13.0",
        },
        indent=2,
    )
    + "\n"
)
artifacts.append(metadata)
checksums = out / "SHA256SUMS.txt"
checksums.write_text(
    "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in artifacts)
)
for artifact in artifacts:
    print(artifact)
print(checksums)

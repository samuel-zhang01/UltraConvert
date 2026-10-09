"""Build a single-app Xcode archive for Organizer's Developer ID notarization flow."""

import argparse
import datetime
import plistlib
from pathlib import Path

from package_app import build_app, developer_id_details, native_provenance


def build_archive(destination, sign_identity):
    destination = Path(destination).resolve()
    if destination.suffix != ".xcarchive":
        raise RuntimeError("Choose an output path ending in .xcarchive")
    if destination.exists():
        raise RuntimeError("Choose a new archive path; existing archives are never replaced")
    identity = developer_id_details(sign_identity)
    app = build_app(destination / "Products/Applications", sign_identity=sign_identity)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    metadata = {
        "ArchiveVersion": 2,
        "ApplicationProperties": {
            "ApplicationPath": "Applications/UltraConvert.app",
            "CFBundleIdentifier": info["CFBundleIdentifier"],
            "CFBundleShortVersionString": info["CFBundleShortVersionString"],
            "CFBundleVersion": info["CFBundleVersion"],
            "SigningIdentity": identity["name"],
            "Team": identity["team"],
        },
        "CreationDate": datetime.datetime.now(datetime.UTC).replace(tzinfo=None),
        "Name": "UltraConvert",
        "SchemeName": "UltraConvert",
    }
    (destination / "Info.plist").write_bytes(plistlib.dumps(metadata))
    # Native provenance is sealed inside the signed application, not only in
    # mutable archive metadata. Organizer may re-sign the app during export.
    return {
        "archive": str(destination),
        "app": str(app),
        "team": identity["team"],
        "native_source_fingerprint": native_provenance()["source_fingerprint"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New .xcarchive path")
    parser.add_argument(
        "--sign-identity", required=True, help="Exact Developer ID Application name or SHA-1"
    )
    args = parser.parse_args()
    import json

    print(json.dumps(build_archive(args.output, args.sign_identity), indent=2))


if __name__ == "__main__":
    main()

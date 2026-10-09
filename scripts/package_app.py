"""Build the native app; conversion engines are installed separately."""

import hashlib
import json
import platform
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCES = sorted((ROOT / "src").glob("*.swift"))


def run(args):
    subprocess.run(list(map(str, args)), check=True)


def developer_id_details(identity):
    """Resolve a valid public app identity without exporting any credentials."""
    output = subprocess.check_output(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"], text=True
    )
    for digest, name in re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', output):
        if name.startswith("Developer ID Application:") and identity in (digest, name):
            team = re.search(r"\(([A-Z0-9]+)\)$", name)
            if team:
                return {"sha1": digest, "name": name, "team": team[1]}
    raise RuntimeError(
        "No matching valid Developer ID Application identity. Create/import it in Keychain first; an Apple Development certificate cannot sign a public Developer ID release."
    )


def developer_id_identity(identity):
    """Resolve a valid Developer ID Application identity, never a development cert."""
    return developer_id_details(identity)["sha1"]


def native_provenance():
    """Fingerprint every input that generates the native app or release container."""
    inputs = [
        *APP_SOURCES,
        ROOT / "VERSION",
        ROOT / "LICENSE",
        ROOT / "assets/UltraConvert.icns",
        ROOT / "install.py",
        *(
            ROOT / "scripts" / name
            for name in (
                "package_app.py",
                "build_release.py",
                "build_xcode_archive.py",
                "notarize.py",
            )
        ),
    ]
    files = {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(inputs)
    }
    fingerprint = hashlib.sha256(
        json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    return {
        "schema": 1,
        "version": (ROOT / "VERSION").read_text().strip(),
        "source_fingerprint": fingerprint,
        "files": files,
    }


def build_app(destination, sign_identity=None):
    provenance = native_provenance()
    version = (ROOT / "VERSION").read_text().strip()
    icon = ROOT / "assets/UltraConvert.icns"
    if not icon.is_file():
        raise RuntimeError("Missing app icon. Run python3 scripts/build_brand.py first.")
    app = Path(destination) / "UltraConvert.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    run(
        [
            "/usr/bin/xcrun",
            "swiftc",
            "-Osize",
            "-parse-as-library",
            "-target",
            f"{arch}-apple-macosx13.0",
            "-framework",
            "AppKit",
            *APP_SOURCES,
            "-o",
            contents / "MacOS/UltraConvert",
        ]
    )
    # Keep runtime/exported symbols; discard local/debug names before signing.
    run(["/usr/bin/strip", "-S", "-x", contents / "MacOS/UltraConvert"])
    info = {
        "CFBundleIdentifier": "local.ultraconvert",
        "CFBundleName": "UltraConvert",
        "CFBundleDisplayName": "UltraConvert",
        "CFBundleExecutable": "UltraConvert",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": version,
        "CFBundleShortVersionString": version,
        "CFBundleIconFile": "UltraConvert",
        "NSHighResolutionCapable": True,
        "LSMinimumSystemVersion": "13.0",
        "NSHumanReadableCopyright": "© 2026 UltraConvert contributors. MIT licence.",
        "NSServices": format_services(),
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "Convertible files",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "None",
                "LSItemContentTypes": ["public.data"],
            }
        ],
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    (contents / "Resources/UltraConvert.icns").write_bytes(icon.read_bytes())
    (contents / "Resources/LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
    (contents / "Resources/ultraconvert-managed.json").write_text(
        json.dumps({"owner": "UltraConvert", "version": version}) + "\n"
    )
    if provenance != native_provenance():
        raise RuntimeError("Native source inputs changed while compiling the app")
    (contents / "Resources/native-provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n"
    )
    # Keep repair templates in every native app, including installer releases.
    # The native installer fills in the actual app path without running Python.
    sys.path.insert(0, str(ROOT))
    from install import workflow

    for mode, name in (
        ("here", "Convert Here with UltraConvert"),
        ("destination", "Convert to Destination with UltraConvert"),
    ):
        workflow(contents / "Resources/FinderActions" / (name + ".workflow"), mode)
    identity = developer_id_identity(sign_identity) if sign_identity else "-"
    run(
        [
            "/usr/bin/codesign",
            "--force",
            "--sign",
            identity,
            "--options",
            "runtime",
            "--timestamp" if sign_identity else "--timestamp=none",
            app,
        ]
    )
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    return app


def format_services():
    """A small set of Finder presets. Every service opens a batch for review."""
    services = [
        {
            "NSMenuItem": {"default": f"Convert to {label} with UltraConvert"},
            "NSMessage": "prepareConversion",
            "NSPortName": "UltraConvert",
            "NSUserData": target,
            "NSSendFileTypes": types,
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSServiceDescription": "Choose this format, review the batch in UltraConvert, then click Convert.",
        }
        for label, target, types in [
            ("PNG", "png", ["public.image"]),
            ("JPEG", "jpg", ["public.image"]),
            ("WebP", "webp", ["public.image"]),
            ("MP3", "mp3", ["public.audiovisual-content"]),
            ("Opus", "opus", ["public.audiovisual-content"]),
            ("MP4", "mp4", ["public.movie"]),
        ]
    ]
    services.append(
        {
            "NSMenuItem": {"default": "Convert Here with UltraConvert — Choose Format…"},
            "NSMessage": "prepareConversion",
            "NSPortName": "UltraConvert",
            "NSUserData": "choose",
            "NSSendFileTypes": ["public.data"],
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSServiceDescription": "Choose Audio, Video, Images, Documents, Geospatial or Structured data, then review the conversion.",
        }
    )
    return services


def validate_prebuilt(app):
    app = Path(app)
    data = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (
        data.get("CFBundleIdentifier") != "local.ultraconvert"
        or data.get("CFBundleShortVersionString") != (ROOT / "VERSION").read_text().strip()
    ):
        raise RuntimeError("Prebuilt app version/identifier does not match this source release")
    marker = json.loads((app / "Contents/Resources/ultraconvert-managed.json").read_text())
    if marker.get("owner") != "UltraConvert":
        raise RuntimeError("Prebuilt app is not marked as UltraConvert")
    if (app / "Contents/Resources/UltraConvert.icns").read_bytes() != (
        ROOT / "assets/UltraConvert.icns"
    ).read_bytes():
        raise RuntimeError("Prebuilt icon does not match this release")
    architectures = subprocess.check_output(
        ["/usr/bin/lipo", "-archs", app / "Contents/MacOS/UltraConvert"], text=True
    ).split()
    if platform.machine() not in architectures:
        raise RuntimeError(
            "This prebuilt app does not support this Mac. Install with --build-from-source."
        )
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    return app


def validate_notarized_app(app, sign_identity):
    """Reuse only this source's exact signed, stapled and Gatekeeper-accepted app."""
    app = validate_prebuilt(app)
    provenance_path = app / "Contents/Resources/native-provenance.json"
    try:
        provenance = json.loads(provenance_path.read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError("Notarized app has no valid native source provenance") from error
    if provenance != native_provenance():
        raise RuntimeError("Notarized app was built from different native source inputs")
    if (app / "Contents/Resources/runtime-manifest.json").exists():
        raise RuntimeError("This public installer cannot reuse a bundled-engine development app")
    identity = developer_id_details(sign_identity)
    requirement = (
        f'anchor apple generic and certificate leaf = H"{identity["sha1"]}" '
        f'and certificate leaf[subject.OU] = "{identity["team"]}"'
    )
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "-R=" + requirement, app])
    display = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", str(app)],
        check=True,
        text=True,
        capture_output=True,
    ).stderr
    flags = re.search(r"^.*flags=.*\(([^)]*)\)", display, re.M)
    if (
        f"Authority={identity['name']}" not in display.splitlines()
        or f"TeamIdentifier={identity['team']}" not in display.splitlines()
        or not flags
        or "runtime" not in flags[1].split(",")
        or not re.search(r"^Timestamp=.+$", display, re.M)
    ):
        raise RuntimeError(
            "Exported app lacks the expected Developer ID/team, Hardened Runtime or timestamp"
        )
    run(["/usr/bin/xcrun", "stapler", "validate", app])
    run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app])
    return app

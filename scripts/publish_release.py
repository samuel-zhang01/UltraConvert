"""Trusted Mac release pipeline. Signing keys remain in its local Keychain."""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import time
from pathlib import Path

from package_app import ROOT, developer_id_details, native_provenance, validate_notarized_app
from render_homebrew import checked_artifacts, release_version, render

REPOSITORY = "samuel-zhang01/UltraConvert"
TAP = "samuel-zhang01/homebrew-ultraconvert"
IDENTITY = "9EB5F0840D5809223A046EDA4903EDFB0206FF2F"


def run(command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, **kwargs)


def api(path, method="GET", data=None, tap=False):
    env = os.environ.copy()
    if tap:
        # The repository-scoped Actions token cannot write another repository.
        # Use this trusted runner's existing gh login; never export credentials.
        env.pop("GH_TOKEN", None)
        env.pop("GITHUB_TOKEN", None)
    command = ["gh", "api", path, "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = run(
        command,
        input=json.dumps(data) if data is not None else None,
        text=True,
        capture_output=True,
        env=env,
    )
    return json.loads(result.stdout)


def optional_api(path, tap=False):
    try:
        return api(path, tap=tap)
    except subprocess.CalledProcessError as error:
        if "HTTP 404" in (error.stderr or ""):
            return None
        raise


def validate_ref(version):
    release_version(version)
    if (ROOT / "VERSION").read_text().strip() != version:
        raise ValueError("Requested release does not match VERSION")
    head = subprocess.check_output(
        ["/usr/bin/git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    tag = subprocess.check_output(
        ["/usr/bin/git", "rev-parse", f"v{version}^{{commit}}"], cwd=ROOT, text=True
    ).strip()
    if head != tag:
        raise ValueError("Run the release at its exact version tag")
    run(["/usr/bin/git", "merge-base", "--is-ancestor", head, "origin/main"], cwd=ROOT)
    if subprocess.check_output(["/usr/bin/git", "status", "--porcelain"], cwd=ROOT).strip():
        raise ValueError("The release checkout must be clean")
    return head


def verify_release(directory, version, commit):
    meta, _ = checked_artifacts(directory)
    if meta["version"] != version or meta["commit"] != commit:
        raise ValueError("Public release metadata does not match its exact tag")
    if meta["native_source_fingerprint"] != native_provenance("universal")["source_fingerprint"]:
        raise ValueError("Public app was built from different native inputs")
    expected_source = subprocess.check_output(
        ["/usr/bin/git", "archive", "--format=tar.gz", "--prefix=UltraConvert/", commit], cwd=ROOT
    )
    if (
        hashlib.sha256(expected_source).hexdigest()
        != hashlib.sha256(
            (Path(directory) / f"UltraConvert-{version}-source.tar.gz").read_bytes()
        ).hexdigest()
    ):
        raise ValueError("Source archive does not match the exact approved Git tag")
    app = Path(directory) / "extracted/UltraConvert.app"
    if not app.exists():
        app.parent.mkdir()
        run(
            [
                "/usr/bin/ditto",
                "-x",
                "-k",
                Path(directory) / f"UltraConvert-{version}-update-macos-universal.zip",
                app.parent,
            ]
        )
    validate_notarized_app(app, IDENTITY, architecture="universal")
    from defusedxml import ElementTree as ET
    from sparkle import distribution

    feed = Path(directory) / "appcast.xml"
    enclosure = ET.parse(feed).find("./channel/item/enclosure")
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/v{version}/UltraConvert-{version}-update-macos-universal.zip"
    archive = Path(directory) / f"UltraConvert-{version}-update-macos-universal.zip"
    if (
        enclosure is None
        or enclosure.get("url") != expected_url
        or int(enclosure.get("length", "0")) != archive.stat().st_size
    ):
        raise ValueError("Signed feed does not reference the exact public update archive")
    with distribution() as dependency:
        tool = dependency / "bin/sign_update"
        run([tool, "--account", "UltraConvert", "--verify", feed])
        run(
            [
                tool,
                "--account",
                "UltraConvert",
                "--verify",
                archive,
                enclosure.attrib[
                    "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"
                ],
            ]
        )
    return meta


def xcode_notarized_app(base):
    identity = developer_id_details(IDENTITY)
    archive = base / "UltraConvert.xcarchive"
    run(
        [
            sys.executable,
            ROOT / "scripts/build_xcode_archive.py",
            "--output",
            archive,
            "--sign-identity",
            IDENTITY,
            "--architecture",
            "universal",
        ],
        cwd=ROOT,
    )
    # Xcode distribution diagnostics can include account details. Keep them local.
    for destination in ["upload", "export"]:
        options = base / f"ExportOptions-{destination}.plist"
        options.write_bytes(
            plistlib.dumps(
                {
                    "method": "developer-id",
                    "destination": destination,
                    "signingStyle": "manual",
                    "signingCertificate": IDENTITY,
                    "teamID": identity["team"],
                    "manageAppVersionAndBuildNumber": False,
                    "stripSwiftSymbols": False,
                }
            )
        )
        output = base / destination
        with (base / f"xcode-{destination}-private.log").open("w") as log:
            try:
                run(
                    [
                        "/usr/bin/xcodebuild",
                        "-exportArchive",
                        "-archivePath",
                        archive,
                        "-exportPath",
                        output,
                        "-exportOptionsPlist",
                        options,
                    ],
                    stdout=log,
                    stderr=subprocess.STDOUT,
                )
            except subprocess.CalledProcessError:
                raise RuntimeError(
                    "Xcode distribution did not finish. Review its private local log and refresh Xcode account authorization if required; no unsigned release is permitted."
                ) from None
        print("Xcode " + destination + " completed", flush=True)
    return validate_notarized_app(
        base / "export/UltraConvert.app", IDENTITY, architecture="universal"
    )


def publish_tap(directory, version):
    folder = Path(directory) / "tap"
    render(directory, folder)
    files = {
        "Formula/ultraconvert-runtime.rb": (folder / "Formula/ultraconvert-runtime.rb").read_text(),
        "Casks/ultraconvert.rb": (folder / "Casks/ultraconvert.rb").read_text(),
        "LICENSE": (ROOT / "LICENSE").read_text(),
        "README.md": (ROOT / "homebrew/TAP-README.md").read_text(),
        ".github/workflows/ci.yml": (ROOT / "homebrew/tap-ci.yml").read_text(),
    }
    reference = api(f"repos/{TAP}/git/ref/heads/main", tap=True)
    parent = reference["object"]["sha"]
    previous = api(f"repos/{TAP}/git/commits/{parent}", tap=True)
    changed = False
    for name, text in files.items():
        existing = optional_api(f"repos/{TAP}/contents/{name}?ref=main", tap=True)
        if not existing or base64.b64decode(existing["content"]).decode() != text:
            changed = True
    if not changed:
        print("Homebrew tap already matches this verified release", flush=True)
        return parent
    tree = api(
        f"repos/{TAP}/git/trees",
        "POST",
        {
            "base_tree": previous["tree"]["sha"],
            "tree": [
                {"path": name, "mode": "100644", "type": "blob", "content": text}
                for name, text in files.items()
            ],
        },
        tap=True,
    )
    commit = api(
        f"repos/{TAP}/git/commits",
        "POST",
        {"message": f"Update UltraConvert to {version}", "tree": tree["sha"], "parents": [parent]},
        tap=True,
    )
    api(
        f"repos/{TAP}/git/refs/heads/main",
        "PATCH",
        {"sha": commit["sha"], "force": False},
        tap=True,
    )
    print("Published atomic Homebrew tap update", flush=True)
    return commit["sha"]


def wait_tap_ci(commit, timeout=2400):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        runs = api(f"repos/{TAP}/actions/runs?head_sha={commit}&event=push", tap=True)[
            "workflow_runs"
        ]
        completed = [r for r in runs if r["status"] == "completed"]
        if completed:
            if any(r["conclusion"] != "success" for r in completed):
                raise RuntimeError(
                    "Homebrew CI failed; the update feed was not changed. Fix the tap and rerun this release."
                )
            print(
                "Homebrew audit, install, runtime test and data-preserving uninstall passed",
                flush=True,
            )
            return
        time.sleep(20)
    raise RuntimeError("Homebrew CI did not finish; the update feed was not changed")


def publish_feed(directory, version):
    latest = api(f"repos/{REPOSITORY}/releases/latest")
    if release_version(latest["tag_name"].removeprefix("v")) > release_version(version):
        raise ValueError("Refusing to replace a newer release feed")
    path = f"repos/{REPOSITORY}/contents/updates/appcast.xml"
    existing = api(path)
    data = (Path(directory) / "appcast.xml").read_bytes()
    if base64.b64decode(existing["content"]) == data:
        print("Signed feed already published", flush=True)
        return
    api(
        path,
        "PUT",
        {
            "message": f"Publish verified signed v{version} update feed",
            "content": base64.b64encode(data).decode(),
            "sha": existing["sha"],
            "branch": "main",
        },
    )
    print("Published signed feed after public assets and Homebrew CI verification", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise RuntimeError("Official releases require the trusted signing Mac")
    commit = validate_ref(args.version)
    existing = optional_api(f"repos/{REPOSITORY}/releases/tags/v{args.version}")
    latest = optional_api(f"repos/{REPOSITORY}/releases/latest")
    if latest and release_version(latest["tag_name"].removeprefix("v")) > release_version(
        args.version
    ):
        raise ValueError("Refusing to publish an older release")
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=False)
    public = base / "downloaded"
    public.mkdir()
    if existing and not existing["draft"]:
        print("Verifying existing immutable release for a safe retry", flush=True)
    else:
        app = xcode_notarized_app(base)
        artifacts = base / "artifacts"
        run(
            [
                sys.executable,
                ROOT / "scripts/build_release.py",
                "--architecture",
                "universal",
                "--sign-identity",
                IDENTITY,
                "--notarized-app",
                app,
                "--dmg",
                "--update-assets",
                "--output-dir",
                artifacts,
            ],
            cwd=ROOT,
        )
        notes = ROOT / "docs/releases" / (args.version + ".md")
        files = sorted(artifacts.iterdir())
        if existing:
            raise RuntimeError("A draft with this version exists; review it before publishing")
        run(
            [
                "gh",
                "release",
                "create",
                f"v{args.version}",
                "--repo",
                REPOSITORY,
                "--verify-tag",
                "--latest",
                "--title",
                f"UltraConvert {args.version}",
                "--notes-file",
                notes,
                *files,
            ]
        )
    run(["gh", "release", "download", f"v{args.version}", "--repo", REPOSITORY, "--dir", public])
    verify_release(public, args.version, commit)
    tap_commit = publish_tap(public, args.version)
    wait_tap_ci(tap_commit)
    publish_feed(public, args.version)
    print(
        f"Complete stable release: https://github.com/{REPOSITORY}/releases/tag/v{args.version}",
        flush=True,
    )


if __name__ == "__main__":
    main()

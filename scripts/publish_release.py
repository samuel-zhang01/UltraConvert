"""Trusted Mac release pipeline. Signing keys remain in its local Keychain."""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from package_app import ROOT, developer_id_details, native_provenance, validate_notarized_app
from render_homebrew import checked_artifacts, release_version, render

REPOSITORY = "samuel-zhang01/UltraConvert"
TAP = "samuel-zhang01/homebrew-ultraconvert"
IDENTITY = "9EB5F0840D5809223A046EDA4903EDFB0206FF2F"

# A named config roots RuboCop's project index at our isolated working folder.
# Inheriting the canonical rules retains all enabled cops, including duplicate
# methods, without indexing an older installed copy of the same formula.
HOMEBREW_STYLE = r"""
require "json"
require "utils/gem_setup"
Utils::GemSetup.install_bundler_gems!(groups: ["style"])
config = Pathname(ARGV.shift)
config.write("inherit_from: #{(HOMEBREW_LIBRARY_PATH.parent/".rubocop.yml").to_s.to_json}\n")
ARGV.unshift("--config", config.to_s, "--force-exclusion", "--format", "clang")
load HOMEBREW_LIBRARY_PATH/"utils/rubocop.rb"
"""

# Homebrew 7 no longer accepts `brew audit /path/to/recipe.rb`. Its content
# loaders let the maintainer audit newly rendered, checksum-verified definitions
# without installing a tap, changing its trust store, or replacing active recipes.
# An incompatible Homebrew API fails the gate rather than silently skipping it.
HOMEBREW_AUDIT = r"""
require "formula"
require "utils/curl"
require "formula_cellar_checks"
require "utils/spdx"
require "formula_auditor"
require "cask/cask_loader"
require "cask/auditor"

Homebrew.auditing = true
path = Pathname(ARGV.fetch(0)).realpath
formula = Formulary.from_contents("ultraconvert-runtime", path, path.read)
auditor = Homebrew::FormulaAuditor.new(formula, new_formula: true, strict: true, online: true)
auditor.audit
errors = { "formula" => auditor.problems + auditor.new_formula_problems }
cask = Cask::CaskLoader::FromContentLoader.new(File.read(ARGV.fetch(1))).load(config: nil)
errors["cask"] = Cask::Auditor.audit(
  cask, audit_online: true, audit_strict: true, audit_new_cask: true,
  any_named_args: true, except: ["github_repository"]
).to_a
errors.each do |kind, entries|
  entries.each do |entry|
    message = if entry.is_a?(Hash)
      entry.fetch(:message)
    elsif entry.respond_to?(:message)
      entry.message
    else
      entry.to_s
    end
    warn "#{kind}: #{message}"
  end
end
abort "Homebrew recipe audit failed; no tap or feed was published" if errors.values.any?(&:any?)
puts "Homebrew formula and cask audits passed without installing or removing anything"
"""


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
    return json.loads(result.stdout) if result.stdout.strip() else None


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
        existing = optional_api(f"repos/{REPOSITORY}/releases/tags/v{version}")
        if not existing or existing["draft"]:
            raise ValueError("New releases require their exact version tag")
        # Main may repair publication orchestration for an immutable release.
        # verify_release still binds its source archive to this tag and requires
        # the current native inputs to match the signed published app exactly.
        run(["/usr/bin/git", "merge-base", "--is-ancestor", tag, head], cwd=ROOT)
    run(["/usr/bin/git", "merge-base", "--is-ancestor", head, "origin/main"], cwd=ROOT)
    if subprocess.check_output(["/usr/bin/git", "status", "--porcelain"], cwd=ROOT).strip():
        raise ValueError("The release checkout must be clean")
    return tag


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


def wait_for_ticket(app, timeout=1200):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["/usr/bin/xcrun", "stapler", "staple", str(app)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            print("Apple notarization ticket is stapled", flush=True)
            return
        time.sleep(20)
    raise RuntimeError("Apple notarization ticket is not available; no release was published")


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
    wait_for_ticket(base / "export/UltraConvert.app")
    return validate_notarized_app(
        base / "export/UltraConvert.app", IDENTITY, architecture="universal"
    )


def style_homebrew(files, env):
    # Keep the index outside the runner's hidden .github-runners directory:
    # Homebrew's Formula/Casks glob exclusions intentionally skip hidden paths.
    # Only these exact audited bytes are staged; no installed tap is changed.
    with tempfile.TemporaryDirectory(prefix="ultraconvert-homebrew-style-") as temporary:
        folder = Path(temporary).resolve()
        if any(part.startswith(".") for part in folder.parts):
            raise ValueError("Homebrew style staging must be outside hidden directories")
        recipes = []
        for name, text in files.items():
            if name.endswith(".rb"):
                target = folder / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                recipes.append(target)
        run(
            ["brew", "ruby", "-e", HOMEBREW_STYLE, folder / "release-style.yml", *recipes],
            env=env,
            cwd=folder,
        )


def audit_homebrew(directory, version):
    folder = Path(directory) / "tap"
    meta = render(directory, folder)
    if meta["version"] != version:
        raise ValueError("Homebrew recipes do not match the requested release")
    files = {
        "Formula/ultraconvert-runtime.rb": (folder / "Formula/ultraconvert-runtime.rb").read_text(),
        "Casks/ultraconvert.rb": (folder / "Casks/ultraconvert.rb").read_text(),
        "LICENSE": (ROOT / "LICENSE").read_text(),
        "README.md": (ROOT / "homebrew/TAP-README.md").read_text(),
        ".github/workflows/ci.yml": (ROOT / "homebrew/tap-ci.yml").read_text(),
    }
    recipes = [folder / name for name in files if name.endswith(".rb")]
    env = os.environ.copy()
    token = env.pop("GH_TOKEN", None) or env.get("GITHUB_TOKEN")
    env.pop("GITHUB_TOKEN", None)
    if token:
        # Reuse only the current job's existing credential in this child process.
        # No new token, global Homebrew configuration or trust setting is created.
        env["HOMEBREW_GITHUB_API_TOKEN"] = token
    env.update(HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_ANALYTICS="1")
    style_homebrew(files, env)
    run(["brew", "ruby", "-e", HOMEBREW_AUDIT, *recipes], env=env)
    if any((folder / name).read_text() != files[name] for name in files if name.endswith(".rb")):
        raise ValueError("Homebrew changed a rendered recipe during its audit")
    print("Inline Homebrew style and online recipe audits passed on the release Mac", flush=True)
    return files


def publish_tap(files, version):
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


def verify_published_tap(commit, files):
    def require_head():
        if api(f"repos/{TAP}/git/ref/heads/main", tap=True)["object"]["sha"] != commit:
            raise RuntimeError("The published tap changed; the update feed was not changed")

    require_head()
    for name, expected in files.items():
        existing = api(f"repos/{TAP}/contents/{name}?ref={commit}", tap=True)
        if base64.b64decode(existing["content"]).decode() != expected:
            raise RuntimeError("Published Homebrew files differ from the audited release")
    require_head()
    print("Verified the exact published Homebrew commit and audited file bytes", flush=True)


def publish_verified_distribution(directory, version, commit):
    verify_release(directory, version, commit)
    files = audit_homebrew(directory, version)
    tap_commit = publish_tap(files, version)
    verify_published_tap(tap_commit, files)
    publish_feed(directory, version)


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
    print("Published signed feed after public assets and inline Homebrew verification", flush=True)


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
    publish_verified_distribution(public, args.version, commit)
    print(
        f"Complete stable release: https://github.com/{REPOSITORY}/releases/tag/v{args.version}",
        flush=True,
    )


if __name__ == "__main__":
    main()

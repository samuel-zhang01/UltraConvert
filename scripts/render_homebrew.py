"""Render a custom tap only from checksum-verified, notarized release artifacts."""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def release_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]*\.[0-9]+\.[0-9]+", value):
        raise ValueError("Use a stable major.minor.patch version")
    return tuple(map(int, value.split(".")))


def checked_artifacts(directory):
    directory = Path(directory)
    sums = {}
    for line in (directory / "SHA256SUMS.txt").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.lstrip("*")
        if (
            not re.fullmatch(r"[a-f0-9]{64}", digest)
            or Path(name).name != name
            or name in {".", ".."}
            or name in sums
        ):
            raise ValueError("Invalid release checksum manifest")
        file = directory / name
        if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != digest:
            raise ValueError("Release checksum mismatch: " + name)
        sums[name] = digest
    if "RELEASE-METADATA.json" not in sums:
        raise ValueError("Release metadata must be checksum verified")
    meta = json.loads((directory / "RELEASE-METADATA.json").read_text())
    release_version(meta["version"])
    if not (
        meta.get("app_notarized") is True
        and meta.get("hardened_runtime") is True
        and meta.get("homebrew_runtime_supported") is True
    ):
        raise ValueError("A notarized app with Homebrew runtime support is required")
    if meta.get("architecture") != "universal" or set(meta.get("architectures", [])) != {
        "arm64",
        "x86_64",
    }:
        raise ValueError("The cask requires a universal app")
    if not meta.get("updater", {}).get("signed_archive") or not meta.get("updater", {}).get(
        "signed_feed"
    ):
        raise ValueError("Signed update assets are required")
    for name in [
        f"UltraConvert-{meta['version']}-source.tar.gz",
        f"UltraConvert-{meta['version']}-update-macos-universal.zip",
        "appcast.xml",
    ]:
        if name not in sums:
            raise ValueError("Release asset is missing: " + name)
    return meta, sums


def render(directory, destination):
    meta, sums = checked_artifacts(directory)
    version = meta["version"]
    destination = Path(destination)
    substitutions = {
        "@VERSION@": version,
        "@SOURCE_SHA256@": sums[f"UltraConvert-{version}-source.tar.gz"],
        "@APP_SHA256@": sums[f"UltraConvert-{version}-update-macos-universal.zip"],
    }
    for folder, name in [("Formula", "ultraconvert-runtime"), ("Casks", "ultraconvert")]:
        text = (ROOT / "homebrew/templates" / (name + ".rb.in")).read_text()
        for token, value in substitutions.items():
            text = text.replace(token, value)
        if re.search(r"@[A-Z_]+@", text):
            raise ValueError("An unresolved template token remains")
        target = destination / folder / (name + ".rb")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print("Rendered verified Homebrew release " + render(args.artifacts, args.output)["version"])


if __name__ == "__main__":
    main()

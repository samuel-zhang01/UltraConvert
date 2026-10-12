"""Pinned Sparkle dependency. Private update keys stay in the login Keychain."""

import contextlib
import hashlib
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
PUBLIC_KEY = "Lbd66CTOHM4+DJci387OSXG+ceqZgY8eAIrANWMrSWQ="
KEY_ACCOUNT = "UltraConvert"
FEED_URL = "https://raw.githubusercontent.com/samuel-zhang01/UltraConvert/main/updates/appcast.xml"


def verified_archive():
    cache = ROOT / "build/dependencies"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"Sparkle-{VERSION}.tar.xz"
    if not archive.exists():
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temp:
            temporary = Path(temp.name)
            try:
                # Fixed upstream HTTPS URL, followed by a pinned SHA-256 check.
                with urllib.request.urlopen(URL, timeout=30) as response:  # nosec B310
                    shutil.copyfileobj(response, temp)
                temp.flush()
                if hashlib.sha256(temporary.read_bytes()).hexdigest() != SHA256:
                    raise RuntimeError("Sparkle download checksum mismatch")
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("Cached Sparkle checksum mismatch; remove the cache and retry")
    return archive


@contextlib.contextmanager
def distribution():
    # Extract only the exact upstream archive whose SHA-256 is pinned above.
    # A fresh extraction prevents an old, modified framework being reused.
    archive = verified_archive()
    with tempfile.TemporaryDirectory(prefix="ultraconvert-sparkle-") as temp:
        subprocess.run(["/usr/bin/tar", "-xf", str(archive), "-C", temp], check=True)
        yield Path(temp)


def embed(distribution_root, contents, identity, timestamp):
    framework = contents / "Frameworks/Sparkle.framework"
    shutil.copytree(distribution_root / "Sparkle.framework", framework, symlinks=True)
    version = framework / "Versions/B"
    # UltraConvert is not sandboxed; these optional services are unused.
    shutil.rmtree(version / "XPCServices")
    for target in (version / "Autoupdate", version / "Updater.app", framework):
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--force",
                "--sign",
                identity,
                "--options",
                "runtime",
                timestamp,
                str(target),
            ],
            check=True,
        )
    return framework

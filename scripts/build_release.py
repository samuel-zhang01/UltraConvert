"""Package the committed source and matching native app without local evidence/caches."""

import hashlib
import io
import platform
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

from package_app import ROOT, build_app, validate_prebuilt

version = (ROOT / "VERSION").read_text().strip()
arch = platform.machine()
out = ROOT / "dist"
out.mkdir(exist_ok=True)
# git archive includes precisely the committed public tree, without ignored/private files.
source = subprocess.check_output(["git", "archive", "HEAD"], cwd=ROOT)
with tempfile.TemporaryDirectory(prefix="ultraconvert-release-") as temp:
    base = Path(temp)
    folder = base / "UltraConvert"
    folder.mkdir()
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        archive.extractall(folder, filter="data")
    app = build_app(base / "native")
    validate_prebuilt(app)
    (folder / "prebuilt").mkdir()
    shutil.copytree(app, folder / "prebuilt/UltraConvert.app")
    bundle = out / f"UltraConvert-{version}-macos-{arch}.zip"
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", folder, bundle], check=True)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Release archive integrity check failed")
    source_path = out / f"UltraConvert-{version}-source.tar.gz"
    subprocess.run(
        ["git", "archive", "--format=tar.gz", "--prefix=UltraConvert/", "-o", source_path, "HEAD"],
        cwd=ROOT,
        check=True,
    )
checksums = out / "SHA256SUMS.txt"
checksums.write_text(
    "".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in (bundle, source_path)
    )
)
print(bundle)
print(source_path)
print(checksums)

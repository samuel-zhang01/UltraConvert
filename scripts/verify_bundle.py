"""Exercise real engine fixtures using only an app's isolated bundled Python."""

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from package_app import ROOT


def verify(app, output):
    app = Path(app).resolve()
    contents = app / "Contents"
    manifest = json.loads((contents / "Resources/runtime-manifest.json").read_text())
    python = contents / manifest["python"]
    source = contents / manifest["source"]
    packages = python.parent.parent / "lib/python3.14/site-packages"
    environment = {
        "HOME": str(Path.home()),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_GB.UTF-8",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], check=True)
    # Tests import the actual sealed Source through a symlink. The private test
    # shim supplies -S package paths to child CLI checks too; no app is modified.
    with tempfile.TemporaryDirectory(prefix="ultraconvert-bundle-tests-") as temp:
        root = Path(temp)
        (root / "home").mkdir()
        environment["HOME"] = str(root / "home")
        (root / "src").symlink_to(source, target_is_directory=True)
        shutil.copytree(ROOT / "examples", root / "examples")
        shutil.copytree(
            ROOT / "tests", root / "tests", ignore=shutil.ignore_patterns("__pycache__")
        )
        bootstrap = (
            "import sys,runpy; "
            f"sys.path[:0] = [{str(packages)!r}, {str(source)!r}]; "
            "args=sys.argv[1:]; sys.argv=args[1:] if args[0]=='-c' else args; "
            "exec(args[1]) if args[0]=='-c' else runpy.run_path(args[0], run_name='__main__')"
        )
        # CLI regression tests normally invoke sys.executable directly. A local
        # shim keeps every child interpreter isolated, including cancellation.
        shim = root / "isolated-python"
        import shlex

        shim.write_text(
            "#!/bin/sh\nexec "
            + shlex.quote(str(python))
            + " -I -S -B -c "
            + shlex.quote(bootstrap)
            + ' "$@"\n'
        )
        shim.chmod(0o755)
        launcher = (
            "import sys,runpy; "
            + f"sys.path[:0] = [{str(packages)!r}, {str(source)!r}]; sys.executable={str(shim)!r}; "
            + "sys.argv=sys.argv[1:]; runpy.run_path(sys.argv[0], run_name='__main__')"
        )
        for name in ("test_conversion.py", "test_edges.py", "test_security.py", "test_batch.py"):
            with (output / (name + ".log")).open("w") as log:
                result = subprocess.run(
                    [python, "-I", "-S", "-B", "-c", launcher, root / "tests" / name],
                    env=environment,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    timeout=1800,
                    check=False,
                )
            if result.returncode:
                raise RuntimeError(
                    "Bundled engine check failed: "
                    + name
                    + "; see "
                    + str(output / (name + ".log"))
                )
            print("Passed bundled " + name, flush=True)
        for evidence in (root / "evidence/local").glob("*.json"):
            shutil.copy2(evidence, output / evidence.name)
    report = {
        "method": "Real conversion/preservation/security/batch corpus against sealed app Source, isolated bundled Python (-I -S), system-only PATH; source installation retained.",
        "app": app.name,
        "checks": ["format round trips", "edge preservation", "security", "batch workflow"],
        "ok": True,
        "clean_mac_verified": False,
    }
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.app, args.output)))

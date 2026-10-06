"""Start sealed app code without processing global/user site customisations."""

import runpy
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"convert.py", "diagnostics.py"}:
        raise ValueError("Unknown app command")
    source = Path(__file__).resolve().parent
    contents = source.parents[1]
    packages = (
        Path(sys.base_prefix)
        / "lib"
        / (f"python{sys.version_info.major}.{sys.version_info.minor}")
        / "site-packages"
    )
    if not packages.resolve().is_relative_to(contents) or not packages.is_dir():
        raise ValueError("Bundled Python packages are missing")
    sys.path[:0] = [str(source), str(packages)]
    script = source / sys.argv[1]
    sys.argv = [str(script), *sys.argv[2:]]
    runpy.run_path(str(script), run_name="__main__")


if __name__ == "__main__":
    main()

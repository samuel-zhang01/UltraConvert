"""Build a relocatable local-development app from installed, pinned engines.

This does not grant distribution permission. Corresponding-source completion and
Developer ID/notarization remain separate public-release gates.
"""

import concurrent.futures
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

from package_app import ROOT, build_app

MACHO = {
    b"\xcf\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf",
}
SYSTEM = ("/usr/lib/", "/System/Library/")


def run(args):
    subprocess.run(list(map(str, args)), check=True, stdout=subprocess.DEVNULL)


def output(args):
    return subprocess.check_output(list(map(str, args)), text=True)


def macho(path):
    if not path.is_file() or path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in MACHO


def inspect(path):
    libraries = output(["/usr/bin/otool", "-arch", platform.machine(), "-L", path]).splitlines()[1:]
    dependencies = [
        line.strip().rsplit(" (compatibility version", 1)[0]
        for line in libraries
        if " (compatibility version" in line
    ]
    commands = output(["/usr/bin/otool", "-arch", platform.machine(), "-l", path])
    identifiers = re.findall(r"cmd LC_ID_DYLIB\n\s*cmdsize \d+\n\s*name (.+?) \(offset", commands)
    dependencies = [dependency for dependency in dependencies if dependency not in identifiers]
    rpaths = re.findall(r"cmd LC_RPATH\n\s*cmdsize \d+\n\s*path (.+?) \(offset", commands)
    minimum = []
    for command in commands.split("Load command"):
        if "cmd LC_BUILD_VERSION" in command:
            minimum.extend(re.findall(r"\n\s*minos (\d+\.\d+(?:\.\d+)?)\n", command))
        elif "cmd LC_VERSION_MIN_MACOSX" in command:
            minimum.extend(re.findall(r"\n\s*version (\d+\.\d+(?:\.\d+)?)\n", command))
    return {
        "dependencies": dependencies,
        "rpaths": rpaths,
        "minimum": minimum,
        "identifiers": identifiers,
    }


class RuntimeBundler:
    def __init__(self, app, brew):
        self.app = Path(app).resolve()
        self.contents = self.app / "Contents"
        self.resources = self.contents / "Resources"
        self.helpers = self.contents / "Helpers"
        self.frameworks = self.contents / "Frameworks"
        self.brew = Path(brew)
        self.prefix = Path(output([brew, "--prefix"]).strip()).resolve()
        self.mapping = {}
        self.scanned = {}
        self.formula_roots = set()
        self.size_optimizations = []
        self.helpers.mkdir()
        self.frameworks.mkdir()

    def record(self, origin, target):
        origin = origin.resolve()
        target = target.resolve()
        if origin in self.mapping and self.mapping[origin] != target:
            raise RuntimeError(f"Duplicate origin: {origin.name}")
        self.mapping[origin] = target
        try:
            parts = origin.relative_to(self.prefix / "Cellar").parts
            self.formula_roots.add(self.prefix / "Cellar" / parts[0] / parts[1])
        except ValueError:
            pass

    def copy_file(self, origin, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
        self.record(origin, target)

    def copy_tree(self, origin, target):
        origin = Path(origin).resolve()
        run(["/usr/bin/ditto", origin, target])
        for path in origin.rglob("*"):
            if macho(path):
                self.record(path, target / path.relative_to(origin))

    def setup(self):
        python = (
            Path(output([self.brew, "--prefix", "python@3.14"]).strip())
            / "Frameworks/Python.framework"
        )
        self.copy_tree(python, self.frameworks / "Python.framework")
        # Homebrew's site-packages symlink exits the framework. Replace it with a
        # private package directory containing only this app's runtime imports.
        site = self.frameworks / "Python.framework/Versions/3.14/lib/python3.14/site-packages"
        site.unlink()
        site.mkdir()
        interpreter = Path.home() / "Library/Application Support/UltraConvert/.venv/bin/python"
        packages = json.loads(
            output(
                [
                    interpreter,
                    "-I",
                    "-c",
                    "import json,osgeo,numpy,yaml,tomli_w,defusedxml; print(json.dumps([m.__file__ for m in (osgeo,numpy,yaml,tomli_w,defusedxml)]))",
                ]
            )
        )
        for filename in packages:
            origin = Path(filename).resolve().parent
            self.copy_tree(origin, site / origin.name)
            for metadata in origin.parent.glob(origin.name + "-*.dist-info"):
                shutil.copytree(metadata, site / metadata.name, dirs_exist_ok=True)
        shutil.copytree(
            ROOT / "src",
            self.resources / "Source",
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.swift"),
        )
        for name, formula in (
            ("ffmpeg", "ffmpeg-full"),
            ("ffprobe", "ffmpeg-full"),
            ("magick", "imagemagick"),
            ("pandoc", "pandoc"),
            ("mac", "mac"),
            ("ogr2ogr", "gdal"),
        ):
            prefix = Path(output([self.brew, "--prefix", formula]).strip())
            self.copy_file((prefix / "bin" / name).resolve(), self.helpers / name)
        self.copy_tree(Path("/Applications/calibre.app"), self.helpers / "Calibre.app")
        image = Path(output([self.brew, "--prefix", "imagemagick"]).strip())
        data = self.resources / "EngineData"
        shutil.copytree(image / "etc/ImageMagick-7", data / "ImageMagick")
        module_roots = list((image / "lib").glob("ImageMagick*/modules-*/coders"))
        if not module_roots:
            raise RuntimeError("ImageMagick's coder modules are required for a complete bundle")
        paths = {"MAGICK_CONFIGURE_PATH": "Resources/EngineData/ImageMagick"}
        if module_roots:
            if len(module_roots) != 1:
                raise RuntimeError("Ambiguous ImageMagick module directory")
            modules = self.frameworks / "ImageMagickCoders"
            archives = data / "ImageMagickCoders"
            modules.mkdir()
            archives.mkdir()
            for origin in module_roots[0].iterdir():
                if macho(origin):
                    self.copy_file(origin, modules / origin.name)
                elif origin.suffix == ".la":
                    text = origin.read_text()
                    match = re.search(r"^dlname='([^']+)'", text, re.M)
                    if not match or Path(match[1]).name != match[1]:
                        raise RuntimeError("Invalid ImageMagick module archive")
                    relative = os.path.relpath(modules / match[1], archives)
                    text = re.sub(r"^dlname='.*'", "dlname='" + relative + "'", text, flags=re.M)
                    text = re.sub(r"^(dependency_libs|libdir)='.*'", r"\1=''", text, flags=re.M)
                    (archives / origin.name).write_text(text)
            paths["MAGICK_CODER_MODULE_PATH"] = "Resources/EngineData/ImageMagickCoders"
        for formula, name in (("gdal", "gdal"), ("proj", "proj")):
            prefix = Path(output([self.brew, "--prefix", formula]).strip()).resolve()
            shutil.copytree(prefix / "share" / name, data / name, symlinks=True)
            self.formula_roots.add(prefix)
            paths["GDAL_DATA" if name == "gdal" else "PROJ_DATA"] = "Resources/EngineData/" + name
        manifest = {
            "schema": 1,
            "python": "Frameworks/Python.framework/Versions/3.14/bin/python3.14",
            "source": "Resources/Source",
            "tools": {
                name: "Helpers/" + name
                for name in ("ffmpeg", "ffprobe", "magick", "pandoc", "mac", "ogr2ogr")
            },
            "environment_paths": paths,
        }
        manifest["tools"]["ebook-convert"] = "Helpers/Calibre.app/Contents/MacOS/ebook-convert"
        (self.resources / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    def dependency_origin(self, origin, dependency, rpaths):
        if dependency.startswith(SYSTEM):
            return None
        if dependency.startswith("/"):
            candidate = Path(dependency).resolve()
            if candidate == origin:
                return None  # LC_ID_DYLIB, not a load dependency.
            if candidate.exists() and (
                candidate in self.mapping or candidate.is_relative_to(self.prefix)
            ):
                return candidate
            raise RuntimeError(f"Unresolved non-system library in {origin.name}: {dependency}")
        if dependency.startswith("@loader_path/"):
            candidate = (origin.parent / dependency[len("@loader_path/") :]).resolve()
            if candidate.exists():
                return candidate
        if dependency.startswith("@rpath/"):
            for rpath in rpaths:
                expanded = rpath.replace("@loader_path", str(origin.parent))
                if "@" not in expanded:
                    candidate = (Path(expanded) / dependency[len("@rpath/") :]).resolve()
                    if candidate.exists():
                        return None if candidate == origin else candidate
        # Calibre's entire prebuilt tree is preserved, including executable-
        # relative framework rpaths. No Homebrew lookup is permitted here.
        calibre = Path("/Applications/calibre.app/Contents").resolve()
        if origin.is_relative_to(calibre) and dependency.startswith(
            ("@rpath/", "@executable_path/")
        ):
            return None
        raise RuntimeError(f"Unresolved relative library in {origin.name}: {dependency}")

    def close_dependencies(self):
        while True:
            pending = [origin for origin in self.mapping if origin not in self.scanned]
            if not pending:
                break
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                infos = list(pool.map(inspect, pending))
            for origin, info in zip(pending, infos, strict=True):
                self.scanned[origin] = info
                for dependency in info["dependencies"]:
                    candidate = self.dependency_origin(origin, dependency, info["rpaths"])
                    if candidate is not None and candidate not in self.mapping:
                        if not candidate.is_relative_to(self.prefix):
                            raise RuntimeError(
                                "A bundled framework dependency was not copied: " + str(candidate)
                            )
                        digest = hashlib.sha256(str(candidate).encode()).hexdigest()[:12]
                        self.copy_file(
                            candidate,
                            self.frameworks / "Libraries" / (digest + "-" + candidate.name),
                        )
            print(
                f"Resolved {len(self.scanned)} Mach-O files; {len(self.mapping)} total", flush=True
            )

    def relocate(self):
        for origin, target in self.mapping.items():
            with target.open("rb") as stream:
                fat = stream.read(4) in {
                    b"\xca\xfe\xba\xbe",
                    b"\xbe\xba\xfe\xca",
                    b"\xca\xfe\xba\xbf",
                }
            if fat:
                temporary = target.with_name(target.name + ".arm64-stage")
                run(["/usr/bin/lipo", target, "-thin", platform.machine(), "-output", temporary])
                temporary.replace(target)
            info = self.scanned[origin]
            changes = []
            if info["identifiers"]:
                changes.extend(["-id", "@loader_path/" + target.name])
            for rpath in info["rpaths"]:
                if rpath.startswith("/") and not rpath.startswith(SYSTEM):
                    changes.extend(["-delete_rpath", rpath])
            for dependency in info["dependencies"]:
                candidate = self.dependency_origin(origin, dependency, info["rpaths"])
                if candidate is not None:
                    relative = os.path.relpath(self.mapping[candidate], target.parent)
                    changes.extend(["-change", dependency, "@loader_path/" + relative])
            if changes:
                run(["/usr/bin/install_name_tool", *changes, target])
            # Preserve all exported symbols, resources and engine capabilities.
            # Local/debug symbols have no role in the conversion runtime. Keep
            # Calibre's prebuilt internals intact rather than pruning Qt plugins.
            if not target.is_relative_to(self.helpers / "Calibre.app"):
                before = target.stat().st_size
                target.chmod(target.stat().st_mode | 0o200)
                run(["/usr/bin/strip", "-S", "-x", target])
                removed = before - target.stat().st_size
                if removed > 0:
                    self.size_optimizations.append(
                        {"path": str(target.relative_to(self.contents)), "removed_bytes": removed}
                    )
        # C headers and pkg-config metadata are used to build extensions, not
        # run them. Preserve licences, the complete stdlib and GIS precision data.
        python = self.frameworks / "Python.framework"
        for relative in (
            "Headers",
            "Versions/3.14/Headers",
            "Versions/3.14/include",
            "Versions/3.14/lib/pkgconfig",
        ):
            path = python / relative
            if path.is_symlink():
                path.unlink()
            elif path.is_dir():
                removed = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
                shutil.rmtree(path)
                self.size_optimizations.append(
                    {"path": str(path.relative_to(self.contents)), "removed_bytes": removed}
                )
        self.check_containment()
        minimum = max(
            (
                tuple(map(int, version.split(".")))
                for info in self.scanned.values()
                for version in info["minimum"]
            ),
            default=(13, 0),
        )
        plist = self.contents / "Info.plist"
        metadata = plistlib.loads(plist.read_bytes())
        metadata["LSMinimumSystemVersion"] = ".".join(map(str, minimum))
        plist.write_bytes(plistlib.dumps(metadata))
        return metadata["LSMinimumSystemVersion"]

    def check_containment(self):
        root = self.contents.resolve()
        for path in self.contents.rglob("*"):
            if path.is_symlink() and (not path.exists() or not path.resolve().is_relative_to(root)):
                raise RuntimeError("Invalid app symlink: " + str(path.relative_to(root)))
        for target in self.mapping.values():
            info = inspect(target)
            for dependency in info["dependencies"]:
                if dependency.startswith("/") and not dependency.startswith(SYSTEM):
                    raise RuntimeError("External library remains: " + dependency)

    def provenance(self, minimum):
        destination = self.resources / "ThirdParty"
        destination.mkdir()
        formulas = []
        for prefix in sorted(self.formula_roots):
            name, version = prefix.parent.name, prefix.name
            entry = {"name": name, "installed_version": version}
            target = destination / "Homebrew" / name
            target.mkdir(parents=True)
            for path in prefix.iterdir():
                if path.is_file() and re.search(
                    r"license|copying|notice|copyright|authors", path.name, re.I
                ):
                    shutil.copy2(path, target / path.name)
            recipe = prefix / ".brew" / (name + ".rb")
            if recipe.exists():
                shutil.copy2(recipe, target / recipe.name)
            receipt = prefix / "INSTALL_RECEIPT.json"
            if receipt.exists():
                installed = json.loads(receipt.read_text())
                entry["homebrew_commit"] = installed.get("source", {}).get("tap_git_head")
                entry["runtime_dependencies"] = installed.get("runtime_dependencies", [])
            formulas.append(entry)
        calibre_info = plistlib.loads(
            (self.helpers / "Calibre.app/Contents/Info.plist").read_bytes()
        )
        inventory = {
            "schema": 1,
            "architecture": platform.machine(),
            "minimum_macos": minimum,
            "formulae": formulas,
            "calibre_version": calibre_info.get("CFBundleShortVersionString"),
            "mach_o_files": len(self.mapping),
            "size_optimizations": self.size_optimizations,
            "removed_development_bytes": sum(
                item["removed_bytes"] for item in self.size_optimizations
            ),
            "public_distribution_ready": False,
            "remaining_gates": [
                "Corresponding-source archive and licence inventory verification",
                "Developer ID Application signing and Apple notarization",
                "Quarantined clean-Mac verification",
            ],
        }
        (destination / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
        (destination / "README.txt").write_text(
            "UltraConvert local-development runtime\n\nThe conversion engines and their libraries retain their upstream licences. UltraConvert's MIT licence covers its own code only. Homebrew recipes and available licence texts are in this folder; inventory.json records versions. This local build is not approved for public binary distribution. Corresponding source, complete notices, Developer ID/notarization and clean-Mac checks are release gates.\n\nFFmpeg: https://ffmpeg.org/legal.html\nCalibre: https://calibre-ebook.com/about#license\nHomebrew source recipes: https://github.com/Homebrew/homebrew-core\n"
        )
        return inventory

    def sign(self):
        # Sign real files first, then nested frameworks/apps from the inside out.
        # Deep signing is not used to conceal an incomplete signing inventory.
        for path in sorted(self.mapping.values()):
            run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path])
        nested = [
            p
            for p in self.contents.rglob("*")
            if p.is_dir() and not p.is_symlink() and p.suffix in (".framework", ".app")
        ]
        for path in sorted(nested, key=lambda p: len(p.parts), reverse=True):
            run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path])
        run(
            [
                "/usr/bin/codesign",
                "--force",
                "--sign",
                "-",
                "--options",
                "runtime",
                "--timestamp=none",
                self.app,
            ]
        )
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", self.app])


def build_portable(destination):
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise RuntimeError("The first bundled runtime is verified only on Apple Silicon macOS")
    brew = shutil.which("brew") or "/opt/homebrew/bin/brew"
    app = build_app(destination)
    bundler = RuntimeBundler(app, brew)
    bundler.setup()
    bundler.close_dependencies()
    minimum = bundler.relocate()
    inventory = bundler.provenance(minimum)
    bundler.sign()
    return app, inventory


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, required=True, help="New directory for the local-development app"
    )
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Choose a new output directory; existing bundles are never replaced")
    app, inventory = build_portable(args.output)
    print(
        json.dumps(
            {
                "app": str(app),
                "minimum_macos": inventory["minimum_macos"],
                "public_distribution_ready": False,
            }
        )
    )

"""A failed multi-component update must leave the old installation runnable."""

import ast
import importlib.util
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin", "Finder resource forks require macOS")
    def test_staged_workflow_preserves_finder_custom_icon(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source, dest = base / "Source.workflow", base / "Installed.workflow"
            installer.workflow(source)
            installer.run(
                [installer.APP / "Contents/MacOS/UltraConvert", "--brand-workflows", source]
            )
            with patch.object(installer, "SUPPORT", base / "support"):
                installer.install_payload([(source, dest)])
            for suffix, attr in (
                ("", "com.apple.FinderInfo"),
                ("/Icon\r", "com.apple.ResourceFork"),
            ):
                original = subprocess.check_output(
                    ["/usr/bin/xattr", "-px", attr, str(source) + suffix]
                )
                copied = subprocess.check_output(
                    ["/usr/bin/xattr", "-px", attr, str(dest) + suffix]
                )
                self.assertTrue(original.strip())
                self.assertEqual(original, copied)

    def test_both_workflows_have_resolvable_icons_and_safe_arguments(self):
        with tempfile.TemporaryDirectory() as temp:
            for mode, name in (("here", "Convert Here"), ("destination", "Convert to Destination")):
                path = Path(temp) / (name + ".workflow")
                installer.workflow(path, mode)
                contents = path / "Contents"
                info = plistlib.loads((contents / "Info.plist").read_bytes())
                document = plistlib.loads((contents / "document.wflow").read_bytes())
                icon_name = info["NSServices"][0]["NSIconName"]
                self.assertEqual(
                    (contents / "Resources" / (icon_name + ".png")).read_bytes(),
                    (ROOT / "assets/logo.png").read_bytes(),
                )
                self.assertEqual(
                    document["workflowMetaData"]["customImageFileData"],
                    (ROOT / "assets/logo.png").read_bytes(),
                )
                command = document["actions"][0]["action"]["ActionParameters"]["COMMAND_STRING"]
                self.assertIn(f'--mode {mode} -- "$@"', command)
                # A workflow service must dispatch through Automator's runner.
                self.assertNotIn("CFBundleIdentifier", info)

    def test_bootstrap_and_uninstall_parse_on_system_python(self):
        for path in (ROOT / "install.py", ROOT / "uninstall.py", ROOT / "scripts/package_app.py"):
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 9))

    def test_uninstall_leaves_unowned_runtime_untouched(self):
        spec = importlib.util.spec_from_file_location("uninstaller", ROOT / "uninstall.py")
        uninstaller = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(uninstaller)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            runtime = base / "Library/Application Support/UltraConvert"
            runtime.mkdir(parents=True)
            (runtime / "installation.json").write_text('{"owner":"Other App"}')
            with self.assertRaisesRegex(RuntimeError, "Unmanaged"):
                uninstaller.main(base)
            self.assertEqual([p.name for p in runtime.iterdir()], ["installation.json"])
            self.assertFalse((base / ".Trash").exists())

    def test_failed_second_swap_restores_every_component(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            payload = []
            for name in ("runtime", "workflow"):
                source, dest = base / (name + "-new"), base / name
                source.mkdir()
                dest.mkdir()
                (source / "data").write_text("new " + name)
                (dest / "data").write_text("old " + name)
                payload.append((source, dest))
            real_rename = Path.rename

            def fail_once(path, target):
                if path.name.startswith(".ultraconvert-new-") and str(target).endswith("workflow"):
                    raise OSError("simulated disk failure")
                return real_rename(path, target)

            with (
                patch.object(installer, "SUPPORT", base / "support"),
                patch.object(Path, "rename", fail_once),
            ):
                with self.assertRaisesRegex(OSError, "simulated"):
                    installer.install_payload(payload)
            for _, dest in payload:
                self.assertEqual((dest / "data").read_text(), "old " + dest.name)
            self.assertFalse(list(base.glob(".ultraconvert-*")))

    def test_wrong_owner_and_symlink_are_not_managed(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            folder = base / "other"
            folder.mkdir()
            (folder / "marker.json").write_text('{"owner":"Other App"}')
            self.assertFalse(installer.managed(folder, "marker.json"))
            (folder / "marker.json").write_text('{"owner":"UltraConvert"}')
            link = base / "link"
            link.symlink_to(folder)
            self.assertFalse(installer.managed(link, "marker.json"))
            self.assertTrue(installer.managed(folder, "marker.json"))


if __name__ == "__main__":
    unittest.main()

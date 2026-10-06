"""A failed multi-component update must leave the old installation runnable."""

import ast
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
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

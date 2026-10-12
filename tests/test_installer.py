"""A failed multi-component update must leave the old installation runnable."""

import ast
import importlib.util
import json
import os
import plistlib
import shlex
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
from package_app import format_services

APP_FIXTURE = Path(os.environ.get("ULTRACONVERT_TEST_APP", str(installer.APP)))


class InstallerTests(unittest.TestCase):
    def owned_app(self, path):
        marker = path / "Contents/Resources/ultraconvert-managed.json"
        marker.parent.mkdir(parents=True)
        marker.write_text('{"owner":"UltraConvert"}')
        (path / "retained.txt").write_text("keep the existing app")
        return path

    def test_existing_owned_system_app_is_reused_instead_of_creating_second_app(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            home, support = base / "home", base / "support"
            shared = self.owned_app(base / "Applications/UltraConvert.app")
            support.mkdir()
            (support / "installation.json").write_text(
                json.dumps({"owner": "UltraConvert", "app": str(shared)})
            )
            self.assertEqual(installer.installed_app_destination(home, support, shared), shared)
            self.assertFalse((home / "Applications/UltraConvert.app").exists())
            self.assertEqual((shared / "retained.txt").read_text(), "keep the existing app")

    def test_existing_owned_app_is_found_when_install_record_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            shared = self.owned_app(base / "Applications/UltraConvert.app")
            self.assertEqual(
                installer.installed_app_destination(base / "home", base / "support", shared), shared
            )

    def test_first_install_uses_user_applications(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.assertEqual(
                installer.installed_app_destination(
                    base / "home", base / "support", base / "Applications/UltraConvert.app"
                ),
                base / "home/Applications/UltraConvert.app",
            )
            self.assertEqual(list(base.iterdir()), [])

    def test_unsupported_recorded_location_is_never_used_even_if_marked_owned(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            outside = self.owned_app(base / "outside/UltraConvert.app")
            support = base / "support"
            support.mkdir()
            (support / "installation.json").write_text(
                json.dumps({"owner": "UltraConvert", "app": str(outside)})
            )
            with self.assertRaisesRegex(RuntimeError, "outside the supported"):
                installer.installed_app_destination(
                    base / "home", support, base / "Applications/UltraConvert.app"
                )
            self.assertTrue((outside / "retained.txt").exists())

    def test_unowned_or_ambiguous_apps_abort_without_modifying_either_location(self):
        for unowned in (True, False):
            with tempfile.TemporaryDirectory() as temp, self.subTest(unowned=unowned):
                base = Path(temp)
                shared = self.owned_app(base / "Applications/UltraConvert.app")
                user = self.owned_app(base / "home/Applications/UltraConvert.app")
                if unowned:
                    (shared / "Contents/Resources/ultraconvert-managed.json").write_text(
                        '{"owner":"Another app"}'
                    )
                with self.assertRaisesRegex(RuntimeError, "Unmanaged|Multiple"):
                    installer.installed_app_destination(base / "home", base / "support", shared)
                self.assertTrue((shared / "retained.txt").exists())
                self.assertTrue((user / "retained.txt").exists())

    def test_app_and_applications_symlinks_are_not_followed(self):
        for parent_link in (True, False):
            with tempfile.TemporaryDirectory() as temp, self.subTest(parent_link=parent_link):
                base = Path(temp)
                owned = self.owned_app(base / "outside/UltraConvert.app")
                home = base / "home"
                home.mkdir()
                if parent_link:
                    (home / "Applications").symlink_to(owned.parent)
                else:
                    (home / "Applications").mkdir()
                    (home / "Applications/UltraConvert.app").symlink_to(owned)
                with self.assertRaisesRegex(RuntimeError, "Unmanaged"):
                    installer.installed_app_destination(
                        home, base / "support", base / "Applications/UltraConvert.app"
                    )
                self.assertTrue((owned / "retained.txt").exists())

    def test_empty_symlinked_applications_folder_is_not_a_first_install_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            outside = base / "outside"
            outside.mkdir()
            home = base / "home"
            home.mkdir()
            (home / "Applications").symlink_to(outside)
            with self.assertRaisesRegex(RuntimeError, "Unmanaged Applications"):
                installer.installed_app_destination(
                    home, base / "support", base / "Applications/UltraConvert.app"
                )
            self.assertEqual(list(outside.iterdir()), [])

    def test_workflow_dispatches_to_exact_app_path_with_safe_quoting(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            app = base / "Applications/Sam's $(touch nope) app.app"
            path = base / "Convert Here.workflow"
            installer.workflow(path, "here", app_path=app)
            document = plistlib.loads((path / "Contents/document.wflow").read_bytes())
            command = document["actions"][0]["action"]["ActionParameters"]["COMMAND_STRING"]
            self.assertEqual(shlex.split(command)[3], str(app))
            self.assertIn('--mode here -- "$@"', command)
            self.assertEqual(
                json.loads((path / "Contents/ultraconvert-managed.json").read_text())["app"],
                str(app),
            )

    def test_uninstall_moves_owned_system_app_and_runtime_together(self):
        spec = importlib.util.spec_from_file_location("uninstaller", ROOT / "uninstall.py")
        uninstaller = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(uninstaller)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            home = base / "home"
            shared = self.owned_app(base / "Applications/UltraConvert.app")
            runtime = home / "Library/Application Support/UltraConvert"
            runtime.mkdir(parents=True)
            (runtime / "installation.json").write_text(
                json.dumps({"owner": "UltraConvert", "app": str(shared)})
            )
            (runtime / "data.txt").write_text("retained runtime")
            with patch.object(uninstaller.subprocess, "run"):
                uninstaller.main(home, system_app=shared)
            self.assertFalse(shared.exists())
            self.assertFalse(runtime.exists())
            trash = list((home / ".Trash").iterdir())
            self.assertEqual(len(trash), 1)
            self.assertTrue((trash[0] / "UltraConvert.app/retained.txt").exists())
            self.assertEqual((trash[0] / "Runtime/data.txt").read_text(), "retained runtime")

    def test_uninstall_rejects_unowned_system_app_before_creating_trash(self):
        spec = importlib.util.spec_from_file_location("uninstaller", ROOT / "uninstall.py")
        uninstaller = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(uninstaller)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            shared = self.owned_app(base / "Applications/UltraConvert.app")
            (shared / "Contents/Resources/ultraconvert-managed.json").write_text(
                '{"owner":"Another app"}'
            )
            with self.assertRaisesRegex(RuntimeError, "Unmanaged"):
                uninstaller.main(base / "home", system_app=shared)
            self.assertTrue((shared / "retained.txt").exists())
            self.assertFalse((base / "home/.Trash").exists())

    def test_uninstall_rejects_foreign_runtime_even_when_it_names_owned_app(self):
        spec = importlib.util.spec_from_file_location("uninstaller", ROOT / "uninstall.py")
        uninstaller = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(uninstaller)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            shared = self.owned_app(base / "Applications/UltraConvert.app")
            home = base / "home"
            runtime = home / "Library/Application Support/UltraConvert"
            runtime.mkdir(parents=True)
            (runtime / "installation.json").write_text(
                json.dumps({"owner": "Another app", "app": str(shared)})
            )
            with self.assertRaisesRegex(RuntimeError, "Unmanaged"):
                uninstaller.main(home, system_app=shared)
            self.assertTrue((shared / "retained.txt").exists())
            self.assertTrue((runtime / "installation.json").exists())
            self.assertFalse((home / ".Trash").exists())

    @unittest.skipUnless(sys.platform == "darwin", "App bundle metadata requires macOS")
    def test_app_staging_preserves_metadata_and_valid_signature(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source, dest = base / "Source.app", base / "Installed.app"
            installer.run(["/usr/bin/ditto", APP_FIXTURE, source])
            attribute = "com.ultraconvert.install-test"
            installer.run(["/usr/bin/xattr", "-w", attribute, "preserve-bundle-metadata", source])
            with patch.object(installer, "SUPPORT", base / "support"):
                installer.install_payload([(source, dest)])
            self.assertEqual(
                subprocess.check_output(["/usr/bin/xattr", "-p", attribute, dest]).strip(),
                b"preserve-bundle-metadata",
            )
            installer.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", dest])

    @unittest.skipUnless(sys.platform == "darwin", "Finder resource forks require macOS")
    def test_staged_workflow_preserves_finder_custom_icon(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source, dest = base / "Source.workflow", base / "Installed.workflow"
            installer.workflow(source)
            installer.run(
                [APP_FIXTURE / "Contents/MacOS/UltraConvert", "--brand-workflows", source]
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

    def test_finder_format_services_are_bounded_and_reviewable(self):
        services = format_services()
        self.assertEqual(
            {item["NSUserData"] for item in services},
            {"png", "jpg", "webp", "mp3", "opus", "mp4", "choose"},
        )
        self.assertEqual(len(services), 7)
        for item in services:
            self.assertEqual(item["NSMessage"], "prepareConversion")
            self.assertEqual(
                item["NSRequiredContext"], {"NSApplicationIdentifier": "com.apple.finder"}
            )
            self.assertIn("review", item["NSServiceDescription"])
            self.assertTrue(item["NSSendFileTypes"])

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

    def test_explicit_foreign_owner_cannot_claim_legacy_runtime_by_app_path(self):
        with tempfile.TemporaryDirectory() as temp:
            runtime = Path(temp)
            (runtime / "installation.json").write_text(
                json.dumps({"owner": "Another app", "app": str(installer.APP)})
            )
            self.assertFalse(installer.managed(runtime, "installation.json", legacy_runtime=True))
            (runtime / "installation.json").write_text("[]")
            self.assertFalse(installer.managed(runtime, "installation.json", legacy_runtime=True))


if __name__ == "__main__":
    unittest.main()

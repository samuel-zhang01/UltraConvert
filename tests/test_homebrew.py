"""Distribution integrity and data-preserving Homebrew uninstall checks."""

import base64
import hashlib
import io
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import homebrew_integrations
import publish_release
import render_homebrew


class HomebrewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def assets(self):
        folder = self.root / "release"
        folder.mkdir()
        meta = {
            "version": "1.8.1",
            "commit": "a" * 40,
            "architecture": "universal",
            "architectures": ["arm64", "x86_64"],
            "app_notarized": True,
            "hardened_runtime": True,
            "homebrew_runtime_supported": True,
            "updater": {"signed_archive": True, "signed_feed": True},
        }
        (folder / "RELEASE-METADATA.json").write_text(json.dumps(meta))
        for name in [
            "UltraConvert-1.8.1-source.tar.gz",
            "UltraConvert-1.8.1-update-macos-universal.zip",
            "appcast.xml",
        ]:
            (folder / name).write_text("test " + name)
        self.manifest(folder)
        return folder

    def manifest(self, folder):
        (folder / "SHA256SUMS.txt").write_text(
            "".join(
                hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n"
                for p in sorted(folder.iterdir())
                if p.name != "SHA256SUMS.txt"
            )
        )

    def action(self, app="/Applications/UltraConvert.app", owner="UltraConvert"):
        folder = self.root / "Library/Services" / homebrew_integrations.NAMES[1]
        (folder / "Contents").mkdir(parents=True)
        (folder / "Contents/ultraconvert-managed.json").write_text(json.dumps({"owner": owner}))
        (folder / "Contents/document.wflow").write_bytes(
            plistlib.dumps(
                {
                    "actions": [
                        {
                            "action": {
                                "ActionParameters": {
                                    "COMMAND_STRING": f'/usr/bin/open -a "{app}" --args --mode here -- "$@"'
                                }
                            }
                        }
                    ]
                }
            )
        )
        return folder

    def test_render_pins_verified_assets(self):
        assets = self.assets()
        render_homebrew.render(assets, self.root / "tap")
        cask = (self.root / "tap/Casks/ultraconvert.rb").read_text()
        formula = (self.root / "tap/Formula/ultraconvert-runtime.rb").read_text()
        self.assertIn(
            hashlib.sha256(
                (assets / "UltraConvert-1.8.1-update-macos-universal.zip").read_bytes()
            ).hexdigest(),
            cask,
        )
        self.assertIn(
            hashlib.sha256((assets / "UltraConvert-1.8.1-source.tar.gz").read_bytes()).hexdigest(),
            formula,
        )
        self.assertIn('license "MIT"', formula)
        self.assertNotIn("@VERSION@", cask + formula)

    def test_tampered_download_is_rejected(self):
        folder = self.assets()
        (folder / "UltraConvert-1.8.1-source.tar.gz").write_text("tampered")
        with self.assertRaises(ValueError):
            render_homebrew.render(folder, self.root / "tap")
        self.assertFalse((self.root / "tap").exists())

    def test_manifest_path_escape_and_duplicates_rejected(self):
        folder = self.assets()
        original = (folder / "SHA256SUMS.txt").read_text()
        for suffix in [
            "0" * 64 + "  ../outside\n",
            original.splitlines()[0] + "\n",
            "0" * 64 + "  ..\n",
        ]:
            (folder / "SHA256SUMS.txt").write_text(original + suffix)
            with self.assertRaises(ValueError):
                render_homebrew.checked_artifacts(folder)

    def test_distribution_gates_reject_unsafe_metadata(self):
        folder = self.assets()
        original = json.loads((folder / "RELEASE-METADATA.json").read_text())
        for key, value in [
            ("app_notarized", False),
            ("app_notarized", "false"),
            ("homebrew_runtime_supported", False),
            ("hardened_runtime", False),
            ("architecture", "arm64"),
        ]:
            meta = {**original, key: value}
            (folder / "RELEASE-METADATA.json").write_text(json.dumps(meta))
            self.manifest(folder)
            with self.assertRaises(ValueError):
                render_homebrew.checked_artifacts(folder)

    def test_invalid_versions_rejected(self):
        for version in ["v1.8.1", "1.8.1-preview", "1.8.1\n", "1.8.1;touch file", "../1.8.1"]:
            with self.assertRaises(ValueError):
                render_homebrew.release_version(version)

    def test_uninstall_preserves_rules_preferences_and_other_services(self):
        folder = self.action()
        rule = self.root / "Library/Application Support/UltraConvert/Automation/rules.json"
        rule.parent.mkdir(parents=True)
        rule.write_text('{"saved":"keep"}')
        preferences = self.root / "Library/Preferences/local.ultraconvert.plist"
        preferences.parent.mkdir()
        preferences.write_text("keep")
        other = folder.parent / "Unrelated.workflow"
        other.mkdir()
        self.assertEqual(
            homebrew_integrations.remove_actions(Path("/Applications/UltraConvert.app"), self.root),
            1,
        )
        self.assertFalse(folder.exists())
        self.assertEqual(rule.read_text(), '{"saved":"keep"}')
        self.assertEqual(preferences.read_text(), "keep")
        self.assertTrue(other.is_dir())
        self.assertEqual(len(list((self.root / ".Trash").rglob("document.wflow"))), 1)

    def test_custom_appdir_uninstall_keeps_canonical_actions(self):
        folder = self.action()
        self.assertEqual(
            homebrew_integrations.remove_actions(
                self.root / "Test Apps/UltraConvert.app", self.root
            ),
            0,
        )
        self.assertTrue(folder.exists())

    def test_legacy_cask_cleanup_during_upgrade_retains_actions_without_automatic_repair(self):
        folder = self.action()
        original = {p.name: p.read_bytes() for p in (folder / "Contents").iterdir()}
        # Installed 1.8.3 casks invoke the updated runtime helper this way during
        # upgrade. No app launch or automatic Finder repair is involved.
        with (
            patch.object(sys, "argv", ["cleanup", "--app", "/Applications/UltraConvert.app"]),
            patch.object(Path, "home", return_value=self.root),
            redirect_stdout(io.StringIO()),
        ):
            homebrew_integrations.main()
        self.assertEqual(
            {p.name: p.read_bytes() for p in (folder / "Contents").iterdir()}, original
        )
        self.assertFalse((self.root / ".Trash").exists())

    def test_explicit_cleanup_removes_owned_actions_but_keeps_rules_preferences_and_other_services(
        self,
    ):
        folder = self.action()
        rule = self.root / "Library/Application Support/UltraConvert/Automation/rules.json"
        rule.parent.mkdir(parents=True)
        rule.write_bytes(b'{"saved":"keep"}')
        preferences = self.root / "Library/Preferences/local.ultraconvert.plist"
        preferences.parent.mkdir()
        preferences.write_bytes(plistlib.dumps({"autoRegisterFinderActions": False}))
        original_preferences = preferences.read_bytes()
        other = folder.parent / "Unrelated.workflow"
        other.mkdir()
        with (
            patch.object(
                sys,
                "argv",
                ["cleanup", "--app", "/Applications/UltraConvert.app", "--confirm-removal"],
            ),
            patch.object(Path, "home", return_value=self.root),
            redirect_stdout(io.StringIO()),
        ):
            homebrew_integrations.main()
        self.assertFalse(folder.exists())
        self.assertEqual(rule.read_bytes(), b'{"saved":"keep"}')
        self.assertEqual(preferences.read_bytes(), original_preferences)
        self.assertTrue(other.is_dir())
        self.assertEqual(len(list((self.root / ".Trash").rglob("document.wflow"))), 1)

    def test_cask_requires_explicit_optional_cleanup_and_does_not_zap_user_data(self):
        assets = self.assets()
        render_homebrew.render(assets, self.root / "tap")
        cask = (self.root / "tap/Casks/ultraconvert.rb").read_text()
        ordinary_uninstall = cask.split("  uninstall ", 1)[1].split("  zap ", 1)[0]
        self.assertIn('quit: "local.ultraconvert"', ordinary_uninstall)
        self.assertNotIn("script:", ordinary_uninstall)
        zap = cask.split("  zap ", 1)[1].split("  caveats", 1)[0]
        self.assertIn("--confirm-removal", zap)
        self.assertNotIn("trash:", zap)
        self.assertNotIn("delete:", zap)
        self.assertNotIn("Library/", zap)

    def test_unmanaged_and_symlinked_actions_are_retained(self):
        folder = self.action(owner="Other")
        self.assertEqual(
            homebrew_integrations.remove_actions(Path("/Applications/UltraConvert.app"), self.root),
            0,
        )
        marker = folder / "Contents/ultraconvert-managed.json"
        marker.unlink()
        outside = self.root / "outside.json"
        outside.write_text('{"owner":"UltraConvert"}')
        marker.symlink_to(outside)
        self.assertEqual(
            homebrew_integrations.remove_actions(Path("/Applications/UltraConvert.app"), self.root),
            0,
        )
        self.assertTrue(outside.exists() and folder.exists())

    def test_symlinked_service_root_rejected(self):
        (self.root / "Library").mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "Library/Services").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            homebrew_integrations.remove_actions(Path("/Applications/UltraConvert.app"), self.root)

    def test_relative_app_path_rejected(self):
        with self.assertRaises(ValueError):
            homebrew_integrations.remove_actions(Path("UltraConvert.app"), self.root)

    def test_tap_token_uses_local_login_without_exporting_credentials(self):
        import subprocess

        with (
            patch.dict(
                "os.environ", {"GH_TOKEN": "scoped-test-token", "GITHUB_TOKEN": "scoped-test-token"}
            ),
            patch.object(
                publish_release, "run", return_value=subprocess.CompletedProcess([], 0, stdout="{}")
            ) as call,
        ):
            publish_release.api("repos/example/tap", tap=True)
        self.assertNotIn("GH_TOKEN", call.call_args.kwargs["env"])
        self.assertNotIn("GITHUB_TOKEN", call.call_args.kwargs["env"])

    def test_dependency_download_retries_temporary_failure(self):
        import io
        import urllib.error

        import sparkle

        data = io.BytesIO()
        failure = urllib.error.HTTPError(sparkle.URL, 504, "temporary", {}, None)
        with (
            patch.object(
                sparkle.urllib.request,
                "urlopen",
                side_effect=[failure, io.BytesIO(b"verified later")],
            ) as request,
            patch.object(sparkle.time, "sleep"),
        ):
            sparkle.download(data)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(data.getvalue(), b"verified later")

    def test_dependency_download_does_not_retry_permanent_http_error(self):
        import io
        import urllib.error

        import sparkle

        failure = urllib.error.HTTPError(sparkle.URL, 404, "missing", {}, None)
        with (
            patch.object(sparkle.urllib.request, "urlopen", side_effect=failure) as request,
            patch.object(sparkle.time, "sleep"),
        ):
            with self.assertRaises(urllib.error.HTTPError):
                sparkle.download(io.BytesIO())
        self.assertEqual(request.call_count, 1)

    def test_notary_ticket_wait_retries_then_succeeds(self):
        import subprocess

        with (
            patch.object(
                publish_release.subprocess,
                "run",
                side_effect=[
                    subprocess.CompletedProcess([], 65),
                    subprocess.CompletedProcess([], 0),
                ],
            ) as run,
            patch.object(publish_release.time, "sleep"),
        ):
            publish_release.wait_for_ticket(self.root / "App.app")
        self.assertEqual(run.call_count, 2)

    def test_notary_ticket_timeout_prevents_publication(self):
        with patch.object(publish_release.time, "monotonic", side_effect=[0, 1201]):
            with self.assertRaises(RuntimeError):
                publish_release.wait_for_ticket(self.root / "App.app")

    def test_api_accepts_no_content_responses(self):
        import subprocess

        with patch.object(
            publish_release, "run", return_value=subprocess.CompletedProcess([], 0, "")
        ):
            self.assertIsNone(publish_release.api("example", "POST", {}))

    def test_inline_audit_uses_verified_private_recipes_without_mutating_brew(self):
        folder = self.assets()
        with (
            patch.dict(os.environ, {"GH_TOKEN": "existing-job-token", "GITHUB_TOKEN": "unused"}),
            patch.object(publish_release, "run") as run,
        ):
            files = publish_release.audit_homebrew(folder, "1.8.1")
            self.assertEqual(os.environ["GH_TOKEN"], "existing-job-token")
        self.assertEqual(run.call_count, 2)
        style, audit = run.call_args_list
        self.assertEqual(style.args[0][:2], ["brew", "style"])
        self.assertEqual(audit.args[0][:3], ["brew", "ruby", "-e"])
        self.assertEqual(style.args[0][2:], audit.args[0][4:])
        self.assertTrue(
            all(str(path).startswith(str(folder / "tap")) for path in style.args[0][2:])
        )
        for call in [style, audit]:
            env = call.kwargs["env"]
            self.assertEqual(env["HOMEBREW_GITHUB_API_TOKEN"], "existing-job-token")
            self.assertEqual(env["HOMEBREW_NO_AUTO_UPDATE"], "1")
            self.assertNotIn("GH_TOKEN", env)
            self.assertNotIn("GITHUB_TOKEN", env)
            self.assertNotIn("HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS", env)
            self.assertNotIn("existing-job-token", str(call.args))
        self.assertEqual(len(files), 5)
        self.assertEqual(
            files["Casks/ultraconvert.rb"], (folder / "tap/Casks/ultraconvert.rb").read_text()
        )
        ruby = audit.args[0][3]
        self.assertIn("Formulary.from_contents", ruby)
        self.assertIn("Cask::CaskLoader::FromContentLoader", ruby)
        self.assertIn("new_formula: true, strict: true, online: true", ruby)
        self.assertIn("audit_online: true, audit_strict: true, audit_new_cask: true", ruby)
        self.assertIn('except: ["github_repository"]', ruby)
        for unsafe in [
            "Installer",
            "trust!",
            "tap-new",
            "brew install",
            "brew uninstall",
            "defaults write",
        ]:
            self.assertNotIn(unsafe, ruby)

    def test_inline_audit_rejects_corrupt_assets_before_evaluating_recipes(self):
        folder = self.assets()
        (folder / "UltraConvert-1.8.1-source.tar.gz").write_text("tampered")
        with patch.object(publish_release, "run") as run:
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                publish_release.audit_homebrew(folder, "1.8.1")
        run.assert_not_called()

    def test_inline_audit_rejects_wrong_release_before_running_brew(self):
        folder = self.assets()
        with patch.object(publish_release, "run") as run:
            with self.assertRaisesRegex(ValueError, "requested release"):
                publish_release.audit_homebrew(folder, "1.8.2")
        run.assert_not_called()

    def test_inline_audit_rejects_a_recipe_changed_by_an_auditor(self):
        folder = self.assets()

        def change_recipe(*args, **kwargs):
            (folder / "tap/Casks/ultraconvert.rb").write_text("changed")

        with patch.object(publish_release, "run", side_effect=change_recipe):
            with self.assertRaisesRegex(ValueError, "changed a rendered recipe"):
                publish_release.audit_homebrew(folder, "1.8.1")

    def test_distribution_checks_run_in_order_before_feed_publication(self):
        calls = []
        files = {"Casks/ultraconvert.rb": "audited bytes"}
        with (
            patch.object(
                publish_release, "verify_release", side_effect=lambda *a: calls.append("assets")
            ),
            patch.object(
                publish_release,
                "audit_homebrew",
                side_effect=lambda *a: calls.append("audit") or files,
            ),
            patch.object(
                publish_release,
                "publish_tap",
                side_effect=lambda *a: calls.append(("tap", a)) or "commit",
            ),
            patch.object(
                publish_release,
                "verify_published_tap",
                side_effect=lambda *a: calls.append(("remote", a)),
            ),
            patch.object(
                publish_release, "publish_feed", side_effect=lambda *a: calls.append("feed")
            ),
        ):
            publish_release.publish_verified_distribution(self.root, "1.8.1", "tag")
        self.assertEqual(
            calls,
            ["assets", "audit", ("tap", (files, "1.8.1")), ("remote", ("commit", files)), "feed"],
        )

    def test_every_failed_gate_prevents_feed_and_later_publication(self):
        gates = ["verify_release", "audit_homebrew", "publish_tap", "verify_published_tap"]
        for failed in gates:
            with self.subTest(gate=failed):
                with (
                    patch.object(publish_release, "verify_release") as assets,
                    patch.object(publish_release, "audit_homebrew", return_value={}) as audit,
                    patch.object(publish_release, "publish_tap", return_value="commit") as tap,
                    patch.object(publish_release, "verify_published_tap") as remote,
                    patch.object(publish_release, "publish_feed") as feed,
                ):
                    checks = dict(zip(gates, [assets, audit, tap, remote], strict=True))
                    checks[failed].side_effect = subprocess.CalledProcessError(1, ["failed gate"])
                    with self.assertRaises(subprocess.CalledProcessError):
                        publish_release.publish_verified_distribution(self.root, "1.8.1", "tag")
                    feed.assert_not_called()
                    for later in gates[gates.index(failed) + 1 :]:
                        checks[later].assert_not_called()

    def test_remote_gate_checks_the_exact_commit_and_audited_bytes(self):
        commit = "a" * 40
        files = {"Casks/ultraconvert.rb": "audited bytes"}
        with patch.object(
            publish_release,
            "api",
            side_effect=[
                {"object": {"sha": commit}},
                {"content": base64.b64encode(b"audited bytes").decode()},
                {"object": {"sha": commit}},
            ],
        ) as api:
            publish_release.verify_published_tap(commit, files)
        self.assertIn("?ref=" + commit, api.call_args_list[1].args[0])
        self.assertTrue(all(call.kwargs == {"tap": True} for call in api.call_args_list))

    def test_remote_gate_rejects_changed_head_before_or_after_reading_files(self):
        commit = "a" * 40
        files = {"Casks/ultraconvert.rb": "audited bytes"}
        for responses in [
            [{"object": {"sha": "different"}}],
            [
                {"object": {"sha": commit}},
                {"content": base64.b64encode(b"audited bytes").decode()},
                {"object": {"sha": "different"}},
            ],
        ]:
            with patch.object(publish_release, "api", side_effect=responses):
                with self.assertRaisesRegex(RuntimeError, "tap changed"):
                    publish_release.verify_published_tap(commit, files)

    def test_remote_gate_rejects_wrong_published_content(self):
        with patch.object(
            publish_release,
            "api",
            side_effect=[
                {"object": {"sha": "commit"}},
                {"content": base64.b64encode(b"changed bytes").decode()},
            ],
        ):
            with self.assertRaisesRegex(RuntimeError, "differ from the audited"):
                publish_release.verify_published_tap("commit", {"recipe.rb": "audited bytes"})

    def test_untagged_checkout_cannot_create_a_new_release(self):
        (self.root / "VERSION").write_text("1.8.3")
        with (
            patch.object(publish_release, "ROOT", self.root),
            patch.object(
                publish_release.subprocess, "check_output", side_effect=["a" * 40, "b" * 40]
            ),
            patch.object(publish_release, "optional_api", return_value=None),
        ):
            with self.assertRaisesRegex(ValueError, "exact version tag"):
                publish_release.validate_ref("1.8.3")

    def test_existing_public_release_resume_keeps_its_original_tag_commit(self):
        (self.root / "VERSION").write_text("1.8.3")
        with (
            patch.object(publish_release, "ROOT", self.root),
            patch.object(
                publish_release.subprocess, "check_output", side_effect=["a" * 40, "b" * 40, b""]
            ),
            patch.object(publish_release, "optional_api", return_value={"draft": False}),
            patch.object(publish_release, "run") as run,
        ):
            self.assertEqual(publish_release.validate_ref("1.8.3"), "b" * 40)
        self.assertEqual(run.call_args_list[0].args[0][-2:], ["b" * 40, "a" * 40])

    def test_draft_release_cannot_bypass_exact_tag_requirement(self):
        (self.root / "VERSION").write_text("1.8.3")
        with (
            patch.object(publish_release, "ROOT", self.root),
            patch.object(
                publish_release.subprocess, "check_output", side_effect=["a" * 40, "b" * 40]
            ),
            patch.object(publish_release, "optional_api", return_value={"draft": True}),
        ):
            with self.assertRaisesRegex(ValueError, "exact version tag"):
                publish_release.validate_ref("1.8.3")

    def test_existing_release_resume_rejects_changed_native_inputs(self):
        meta = {"version": "1.8.3", "commit": "b" * 40, "native_source_fingerprint": "old"}
        with (
            patch.object(publish_release, "checked_artifacts", return_value=(meta, {})),
            patch.object(
                publish_release, "native_provenance", return_value={"source_fingerprint": "changed"}
            ),
        ):
            with self.assertRaisesRegex(ValueError, "different native inputs"):
                publish_release.verify_release(self.root, "1.8.3", "b" * 40)

    def test_self_hosted_signing_is_owner_only_and_never_pr_triggered(self):
        import yaml

        workflow = yaml.load(
            (ROOT / ".github/workflows/release.yml").read_text(), Loader=yaml.BaseLoader
        )
        self.assertNotIn("pull_request", workflow["on"])
        job = workflow["jobs"]["release"]
        self.assertIn("github.actor == 'samuel-zhang01'", job["if"])
        self.assertEqual(job["runs-on"], ["ultraconvert", "local-macos"])
        self.assertIn("merge-base --is-ancestor", str(job["steps"]))
        self.assertEqual(workflow["concurrency"]["cancel-in-progress"], "false")

    def test_tap_workflow_cannot_allocate_any_runner_or_run_installs(self):
        import yaml

        workflow = yaml.load((ROOT / "homebrew/tap-ci.yml").read_text(), Loader=yaml.BaseLoader)
        self.assertEqual(set(workflow["on"]), {"workflow_dispatch"})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(len(workflow["jobs"]), 1)
        job = workflow["jobs"]["checks-run-inline"]
        self.assertEqual(job["if"], "${{ false }}")
        self.assertEqual(job["runs-on"], ["ultraconvert", "local-macos"])
        workflow_text = (ROOT / "homebrew/tap-ci.yml").read_text()
        for unsafe in [
            "macos-26",
            "macos-latest",
            "ubuntu-",
            "pull_request",
            "defaults write",
            "brew install",
            "brew upgrade",
            "brew uninstall",
        ]:
            self.assertNotIn(unsafe, workflow_text)


if __name__ == "__main__":
    unittest.main()

"""Release gates distinguish development signing from public notarized distribution."""

import contextlib
import io
import json
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import build_release
import build_xcode_archive
import notarize
import package_app


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        sdk = Path(fixture.name)
        (sdk / "LICENSE").write_text("Sparkle test licence")

        @contextlib.contextmanager
        def distribution():
            yield sdk

        sdk_patch = patch.object(package_app.sparkle, "distribution", distribution)
        sdk_patch.start()
        self.addCleanup(sdk_patch.stop)
        embed_patch = patch.object(package_app.sparkle, "embed")
        embed_patch.start()
        self.addCleanup(embed_patch.stop)
        self.identity = {
            "sha1": "E" * 40,
            "name": "Developer ID Application: Example (TEAM)",
            "team": "TEAM",
        }
        self.read_architectures = package_app.app_architectures
        patcher = patch.object(
            package_app, "app_architectures", return_value=package_app.build_architectures()
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_supported_architectures_are_explicit_and_deterministic(self):
        self.assertEqual(package_app.build_architectures("universal"), ["arm64", "x86_64"])
        self.assertEqual(package_app.architecture_label(["x86_64", "arm64"]), "universal")
        self.assertEqual(package_app.build_architectures("x86_64"), ["x86_64"])
        self.assertEqual(package_app.architecture_label(["arm64"]), "arm64")
        for invalid in ("i386", [], ["arm64", "arm64"], ["arm64", "unknown"]):
            with (
                self.subTest(invalid=invalid),
                self.assertRaisesRegex(RuntimeError, "architecture"),
            ):
                package_app.build_architectures(invalid)

    def test_actual_binary_architectures_are_read_and_validated(self):
        with patch.object(
            package_app.subprocess, "check_output", return_value="x86_64 arm64\n"
        ) as read:
            self.assertEqual(self.read_architectures(Path("Example.app")), ["arm64", "x86_64"])
        self.assertEqual(
            read.call_args.args[0],
            ["/usr/bin/lipo", "-archs", Path("Example.app/Contents/MacOS/UltraConvert")],
        )

    def test_universal_compiles_both_slices_before_combining_stripping_and_signing(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(package_app, "run") as run:
            app = package_app.build_app(Path(temp), architecture="universal")
            provenance = json.loads((app / "Contents/Resources/native-provenance.json").read_text())
        commands = [call.args[0] for call in run.call_args_list]
        compilers = [command for command in commands if command[:2] == ["/usr/bin/xcrun", "swiftc"]]
        self.assertEqual(
            [command[command.index("-target") + 1] for command in compilers],
            ["arm64-apple-macosx13.0", "x86_64-apple-macosx13.0"],
        )
        combine = next(command for command in commands if command[0] == "/usr/bin/lipo")
        self.assertEqual(combine[1], "-create")
        self.assertEqual(combine[-1], app / "Contents/MacOS/UltraConvert")
        self.assertLess(
            commands.index(combine),
            next(i for i, command in enumerate(commands) if command[0] == "/usr/bin/strip"),
        )
        self.assertLess(
            commands.index(combine),
            next(i for i, command in enumerate(commands) if command[0] == "/usr/bin/codesign"),
        )
        self.assertEqual(provenance["schema"], 2)
        self.assertEqual(provenance["architectures"], ["arm64", "x86_64"])

    def test_notarized_export_rejects_forged_architectures_before_identity_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.exported_app(temp)
            resource = app / "Contents/Resources/native-provenance.json"
            proof = json.loads(resource.read_text())
            proof["architectures"] = ["arm64", "x86_64"]
            resource.write_text(json.dumps(proof))
            with (
                patch.object(package_app, "validate_prebuilt", return_value=app),
                patch.object(package_app, "app_architectures", return_value=["arm64"]),
                patch.object(package_app, "developer_id_details") as identity,
            ):
                with self.assertRaisesRegex(RuntimeError, "source"):
                    package_app.validate_notarized_app(app, self.identity["sha1"])
            identity.assert_not_called()

    def test_installer_rejects_wrong_host_but_release_can_validate_cross_compiled_app(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "UltraConvert.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleIdentifier": "local.ultraconvert",
                        "CFBundleShortVersionString": (package_app.ROOT / "VERSION")
                        .read_text()
                        .strip(),
                    }
                )
            )
            (resources / "ultraconvert-managed.json").write_text('{"owner":"UltraConvert"}')
            (resources / "UltraConvert.icns").write_bytes(
                (package_app.ROOT / "assets/UltraConvert.icns").read_bytes()
            )
            with (
                patch.object(package_app.platform, "machine", return_value="arm64"),
                patch.object(package_app, "app_architectures", return_value=["x86_64"]),
                patch.object(package_app, "run") as verify,
            ):
                with self.assertRaisesRegex(RuntimeError, "does not support this Mac"):
                    package_app.validate_prebuilt(app)
                verify.assert_not_called()
                self.assertEqual(
                    package_app.validate_prebuilt(app, require_host=False, architecture="x86_64"),
                    app,
                )
                with self.assertRaisesRegex(RuntimeError, "architectures do not match"):
                    package_app.validate_prebuilt(app, require_host=False, architecture="universal")

    def test_universal_release_names_and_metadata_use_payload_architectures(self):
        source = io.BytesIO()
        with tarfile.open(fileobj=source, mode="w"):
            pass

        def git_output(command, **kwargs):
            if command == ["git", "status", "--porcelain"]:
                return b""
            if command == ["git", "archive", "HEAD"]:
                return source.getvalue()
            if command == ["git", "rev-parse", "HEAD"]:
                return "test-release-commit\n"
            raise AssertionError(f"Unexpected command: {command}")

        def create_artifact(command, **kwargs):
            command = list(map(str, command))
            if command[0] == "/usr/bin/ditto":
                if "-c" in command:
                    with zipfile.ZipFile(command[-1], "w") as archive:
                        archive.writestr("UltraConvert/INSTALL-FIRST.txt", "fixture")
                else:
                    shutil.copytree(command[1], command[2])
            elif command[:2] == ["git", "archive"]:
                Path(command[command.index("-o") + 1]).write_bytes(b"source fixture")
            else:
                raise AssertionError(f"Unexpected command: {command}")

        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            exported = self.exported_app(base / "exported")
            out = base / "release"
            args = [
                "build_release.py",
                "--sign-identity",
                self.identity["sha1"],
                "--notarized-app",
                str(exported),
                "--output-dir",
                str(out),
            ]
            with (
                patch.object(sys, "argv", args),
                patch.object(
                    build_release, "developer_id_identity", return_value=self.identity["sha1"]
                ),
                patch.object(build_release.subprocess, "check_output", side_effect=git_output),
                patch.object(build_release.subprocess, "run", side_effect=create_artifact),
                patch.object(build_release, "validate_notarized_app"),
                patch.object(build_release, "validate_prebuilt"),
                patch.object(build_release, "app_architectures", return_value=["arm64", "x86_64"]),
                patch.object(package_app.platform, "machine", return_value="arm64"),
            ):
                build_release.main()
            metadata = json.loads((out / "RELEASE-METADATA.json").read_text())
            self.assertEqual(metadata["architecture"], "universal")
            self.assertEqual(metadata["architectures"], ["arm64", "x86_64"])
            self.assertFalse(metadata["intel_hardware_tested"])
            self.assertFalse(metadata["conversion_engines_bundled"])
            self.assertTrue(metadata["engine_runtime_installer_required"])
            self.assertEqual(len(list(out.glob("UltraConvert-*-macos-universal.zip"))), 1)
            self.assertFalse(list(out.glob("UltraConvert-*-macos-arm64.zip")))

    def exported_app(self, destination):
        app = Path(destination) / "UltraConvert.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        (resources / "native-provenance.json").write_text(
            json.dumps(package_app.native_provenance())
        )
        (app / "Contents/Info.plist").write_bytes(
            plistlib.dumps(
                {
                    "SUFeedURL": package_app.sparkle.FEED_URL,
                    "SUPublicEDKey": package_app.sparkle.PUBLIC_KEY,
                    "SUVerifyUpdateBeforeExtraction": True,
                    "SURequireSignedFeed": True,
                    "SUSignedFeedFailureExpirationInterval": 0,
                    "SUEnableSystemProfiling": False,
                }
            )
        )
        source = resources / "Source"
        source.mkdir()
        for path in package_app.conversion_sources():
            shutil.copyfile(path, source / path.name)
        shutil.copyfile(package_app.ROOT / "requirements.txt", resources / "requirements.txt")
        sdk_resources = app / "Contents/Frameworks/Sparkle.framework/Resources"
        sdk_resources.mkdir(parents=True)
        (sdk_resources / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": package_app.sparkle.VERSION})
        )
        return app

    def export_display(self, **changes):
        fields = {
            "Authority": self.identity["name"],
            "TeamIdentifier": self.identity["team"],
            "CodeDirectory": "v=20500 size=1024 flags=0x10000(runtime)",
            "Timestamp": "Oct 9, 2026 at 12:00:00 PM",
        }
        fields.update(changes)
        return "\n".join(f"{key}={value}" for key, value in fields.items() if value is not None)

    def test_changed_updater_key_feed_or_policy_rejects_public_payload(self):
        for key, value in (
            ("SUPublicEDKey", "wrong"),
            ("SUFeedURL", "https://example.invalid/feed.xml"),
            ("SURequireSignedFeed", False),
            ("SUVerifyUpdateBeforeExtraction", False),
            ("SUSignedFeedFailureExpirationInterval", 1),
            ("SUEnableSystemProfiling", True),
        ):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temp:
                app = self.exported_app(temp)
                path = app / "Contents/Info.plist"
                info = plistlib.loads(path.read_bytes())
                info[key] = value
                path.write_bytes(plistlib.dumps(info))
                with self.assertRaisesRegex(RuntimeError, "security configuration"):
                    package_app.validate_update_payload(app)

    def test_modified_or_missing_sealed_conversion_code_rejects_update(self):
        for remove in (False, True):
            with self.subTest(remove=remove), tempfile.TemporaryDirectory() as temp:
                app = self.exported_app(temp)
                path = app / "Contents/Resources/Source/convert.py"
                if remove:
                    path.unlink()
                else:
                    path.write_text("modified")
                with self.assertRaisesRegex(RuntimeError, "conversion source"):
                    package_app.validate_update_payload(app)

    def test_test_build_provenance_cannot_pass_public_release_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.exported_app(temp)
            path = app / "Contents/Resources/native-provenance.json"
            proof = json.loads(path.read_text())
            proof["update_test_build"] = True
            path.write_text(json.dumps(proof))
            with patch.object(package_app, "validate_prebuilt", return_value=app):
                with self.assertRaisesRegex(RuntimeError, "different native source"):
                    package_app.validate_notarized_app(app, "unused-identity")

    def test_development_certificate_is_not_a_public_distribution_identity(self):
        digest = "A" * 40
        with patch.object(
            package_app.subprocess,
            "check_output",
            return_value=f'1) {digest} "Apple Development: Example (TEAM)"',
        ):
            with self.assertRaisesRegex(RuntimeError, "Developer ID Application"):
                package_app.developer_id_identity(digest)

    def test_developer_id_name_or_hash_resolves_only_an_exact_match(self):
        digest, name = "B" * 40, "Developer ID Application: Example (TEAM)"
        with patch.object(
            package_app.subprocess, "check_output", return_value=f'1) {digest} "{name}"'
        ):
            self.assertEqual(package_app.developer_id_identity(name), digest)
            self.assertEqual(package_app.developer_id_identity(digest), digest)
            with self.assertRaises(RuntimeError):
                package_app.developer_id_identity("Example")

    def test_installer_certificate_cannot_sign_an_app(self):
        digest = "C" * 40
        name = "Developer ID Installer: Example (TEAM)"
        with patch.object(
            package_app.subprocess, "check_output", return_value=f'1) {digest} "{name}"'
        ):
            for identity in (digest, name):
                with self.subTest(identity=identity), self.assertRaises(RuntimeError):
                    package_app.developer_id_identity(identity)

    def test_valid_identity_query_does_not_use_certificate_export(self):
        with patch.object(package_app.subprocess, "check_output", return_value="") as query:
            with self.assertRaises(RuntimeError):
                package_app.developer_id_identity("D" * 40)
        self.assertEqual(
            query.call_args.args[0],
            ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        )

    def test_public_app_uses_resolved_identity_runtime_timestamp_and_verification(self):
        digest = "E" * 40
        with (
            tempfile.TemporaryDirectory() as temp,
            patch.object(package_app, "developer_id_identity", return_value=digest) as resolve,
            patch.object(package_app, "run") as run,
        ):
            app = package_app.build_app(Path(temp), sign_identity="exact-public-identity")
        resolve.assert_called_once_with("exact-public-identity")
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            [
                "/usr/bin/codesign",
                "--force",
                "--sign",
                digest,
                "--options",
                "runtime",
                "--timestamp",
                app,
            ],
            commands,
        )
        self.assertEqual(commands[-1], ["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
        for command in commands:
            if command[0] == "/usr/bin/codesign" and "--sign" in command:
                self.assertNotIn("--deep", command)
                self.assertNotIn("--timestamp=none", command)
                self.assertNotIn("--entitlements", command)

    def test_debug_entitlements_cannot_pass_public_notarized_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.exported_app(temp)
            with (
                patch.object(package_app, "validate_prebuilt", return_value=app),
                patch.object(package_app, "developer_id_details", return_value=self.identity),
                patch.object(
                    package_app.subprocess,
                    "run",
                    return_value=SimpleNamespace(
                        stderr=self.export_display(),
                        stdout=plistlib.dumps(
                            {"com.apple.security.cs.disable-library-validation": True}
                        ).decode(),
                    ),
                ),
            ):
                with self.assertRaisesRegex(
                    RuntimeError, "unexpected development/security entitlements"
                ):
                    package_app.validate_notarized_app(app, self.identity["sha1"])

    def test_rejected_notarization_stops_the_release(self):
        with patch.object(
            notarize.subprocess,
            "run",
            return_value=SimpleNamespace(
                stdout=json.dumps({"status": "Invalid", "id": "test-submission"})
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                notarize.notarize(Path("test.zip"), "test-profile")

    def test_unfinished_missing_or_unknown_acceptance_cannot_pass(self):
        for report in (
            {},
            {"id": "test-submission"},
            {"status": "In Progress", "id": "test-submission"},
            {"status": "accepted", "id": "test-submission"},
        ):
            with (
                self.subTest(report=report),
                patch.object(
                    notarize.subprocess,
                    "run",
                    return_value=SimpleNamespace(stdout=json.dumps(report)),
                ),
                self.assertRaisesRegex(RuntimeError, "not accepted"),
            ):
                notarize.notarize(Path("test.zip"), "test-profile")

    def test_submission_command_failure_is_not_treated_as_acceptance(self):
        failure = subprocess.CalledProcessError(1, ["notarytool", "submit"])
        with patch.object(notarize.subprocess, "run", side_effect=failure) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                notarize.notarize(Path("test.zip"), "test-profile")
        run.assert_called_once()

    def test_malformed_notary_json_is_not_treated_as_acceptance(self):
        with patch.object(
            notarize.subprocess, "run", return_value=SimpleNamespace(stdout="not json")
        ):
            with self.assertRaises(json.JSONDecodeError):
                notarize.notarize(Path("test.zip"), "test-profile")

    def test_accepted_notarization_uses_a_keychain_profile(self):
        with patch.object(
            notarize.subprocess,
            "run",
            return_value=SimpleNamespace(
                stdout=json.dumps({"status": "Accepted", "id": "test-submission"})
            ),
        ) as run:
            self.assertEqual(notarize.notarize(Path("test.zip"), "test-profile"), "test-submission")
        args = run.call_args.args[0]
        self.assertIn("--keychain-profile", args)
        self.assertIn("--wait", args)
        self.assertNotIn("--password", args)

    def test_ticket_is_stapled_and_validated_in_order(self):
        app = Path("test.app")
        with patch.object(notarize.subprocess, "run") as run:
            notarize.staple(app)
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                ["/usr/bin/xcrun", "stapler", "staple", str(app)],
                ["/usr/bin/xcrun", "stapler", "validate", str(app)],
            ],
        )
        self.assertTrue(all(call.kwargs["check"] for call in run.call_args_list))

    def test_ticket_failure_stops_release_before_success(self):
        for failure_step in (0, 1):
            failure = subprocess.CalledProcessError(1, ["stapler"])
            responses = [None] * failure_step + [failure]
            with (
                self.subTest(failure_step=failure_step),
                patch.object(notarize.subprocess, "run", side_effect=responses) as run,
                self.assertRaises(subprocess.CalledProcessError),
            ):
                notarize.staple(Path("test.app"))
            self.assertEqual(run.call_count, failure_step + 1)

    def test_native_fingerprint_tracks_sources_version_and_packaging_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            names = [
                "src/App.swift",
                "VERSION",
                "LICENSE",
                "assets/UltraConvert.icns",
                "assets/logo.png",
                "install.py",
                "uninstall.py",
                "scripts/package_app.py",
                "scripts/build_release.py",
                "scripts/build_xcode_archive.py",
                "scripts/notarize.py",
                "scripts/sparkle.py",
                "scripts/build_updates.py",
                "requirements.txt",
                "src/convert.py",
                "src/policy.xml",
            ]
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("1.0.0" if name == "VERSION" else name)
            with (
                patch.object(package_app, "ROOT", root),
                patch.object(package_app, "APP_SOURCES", [root / "src/App.swift"]),
            ):
                before = package_app.native_provenance()
                self.assertEqual(set(before["files"]), set(names))
                (root / "src/App.swift").write_text("changed native code")
                changed_source = package_app.native_provenance()
                self.assertNotEqual(
                    before["source_fingerprint"], changed_source["source_fingerprint"]
                )
                (root / "VERSION").write_text("1.0.1")
                changed_version = package_app.native_provenance()
                self.assertEqual(changed_version["version"], "1.0.1")
                self.assertNotEqual(
                    changed_source["source_fingerprint"], changed_version["source_fingerprint"]
                )

    def test_source_changes_during_compilation_prevent_signature(self):
        with (
            tempfile.TemporaryDirectory() as temp,
            patch.object(
                package_app,
                "native_provenance",
                side_effect=[{"version": "old"}, {"version": "new"}],
            ),
            patch.object(package_app, "run") as run,
            self.assertRaisesRegex(RuntimeError, "changed while compiling"),
        ):
            package_app.build_app(Path(temp))
        self.assertFalse(any(call.args[0][0] == "/usr/bin/codesign" for call in run.call_args_list))

    def test_export_rejects_absent_or_mismatched_provenance_before_signing_checks(self):
        for invalid in (None, {"schema": 1, "source_fingerprint": "old-source"}):
            with tempfile.TemporaryDirectory() as temp, self.subTest(provenance=invalid):
                app = self.exported_app(temp)
                resource = app / "Contents/Resources/native-provenance.json"
                if invalid is None:
                    resource.unlink()
                else:
                    resource.write_text(json.dumps(invalid))
                with (
                    patch.object(package_app, "validate_prebuilt", return_value=app),
                    patch.object(package_app, "developer_id_details") as identity,
                    self.assertRaisesRegex(RuntimeError, "source"),
                ):
                    package_app.validate_notarized_app(app, self.identity["sha1"])
                identity.assert_not_called()

    def test_export_rejects_bundled_development_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.exported_app(temp)
            (app / "Contents/Resources/runtime-manifest.json").write_text("{}")
            with (
                patch.object(package_app, "validate_prebuilt", return_value=app),
                self.assertRaisesRegex(RuntimeError, "bundled-engine"),
            ):
                package_app.validate_notarized_app(app, self.identity["sha1"])

    def test_export_checks_exact_certificate_team_ticket_and_gatekeeper(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.exported_app(temp)
            with (
                patch.object(package_app, "validate_prebuilt", return_value=app),
                patch.object(package_app, "developer_id_details", return_value=self.identity),
                patch.object(
                    package_app.subprocess,
                    "run",
                    return_value=SimpleNamespace(stderr=self.export_display()),
                ),
                patch.object(package_app, "run") as run,
            ):
                self.assertEqual(
                    package_app.validate_notarized_app(app, self.identity["sha1"]), app
                )
            commands = [call.args[0] for call in run.call_args_list]
            requirement = commands[0][-2]
            self.assertIn('certificate leaf = H"' + self.identity["sha1"] + '"', requirement)
            self.assertIn('certificate leaf[subject.OU] = "TEAM"', requirement)
            self.assertEqual(commands[1], ["/usr/bin/xcrun", "stapler", "validate", app])
            self.assertEqual(
                commands[2],
                ["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app],
            )

    def test_export_rejects_development_authority_team_runtime_or_timestamp(self):
        changes = [
            {"Authority": "Apple Development: Example (TEAM)"},
            {"TeamIdentifier": "OTHER"},
            {"CodeDirectory": "v=20500 size=1024 flags=0x0(none)"},
            {"Timestamp": None},
        ]
        for change in changes:
            with tempfile.TemporaryDirectory() as temp, self.subTest(change=change):
                app = self.exported_app(temp)
                with (
                    patch.object(package_app, "validate_prebuilt", return_value=app),
                    patch.object(package_app, "developer_id_details", return_value=self.identity),
                    patch.object(
                        package_app.subprocess,
                        "run",
                        return_value=SimpleNamespace(stderr=self.export_display(**change)),
                    ),
                    patch.object(package_app, "run") as run,
                    self.assertRaisesRegex(RuntimeError, "Developer ID/team"),
                ):
                    package_app.validate_notarized_app(app, self.identity["sha1"])
                self.assertEqual(run.call_count, 1)

    def test_export_without_valid_ticket_or_gatekeeper_acceptance_cannot_pass(self):
        for failure_step in (0, 1, 2):
            with tempfile.TemporaryDirectory() as temp, self.subTest(failure_step=failure_step):
                app = self.exported_app(temp)
                responses = [None] * failure_step + [subprocess.CalledProcessError(1, ["verify"])]
                with (
                    patch.object(package_app, "validate_prebuilt", return_value=app),
                    patch.object(package_app, "developer_id_details", return_value=self.identity),
                    patch.object(
                        package_app.subprocess,
                        "run",
                        return_value=SimpleNamespace(stderr=self.export_display()),
                    ),
                    patch.object(package_app, "run", side_effect=responses) as run,
                    self.assertRaises(subprocess.CalledProcessError),
                ):
                    package_app.validate_notarized_app(app, self.identity["sha1"])
                self.assertEqual(run.call_count, failure_step + 1)

    def test_external_app_notarization_never_claims_a_dmg_ticket(self):
        status = build_release.notarization_status(None, Path("export.app"), True)
        self.assertTrue(status["app_notarized"])
        self.assertFalse(status["dmg_notarized"])
        self.assertFalse(status["apple_notarization_accepted_and_stapled"])
        self.assertIn(
            "not separately notarized",
            build_release.notarization_note(None, Path("export.app"), True),
        )
        zip_status = build_release.notarization_status(None, Path("export.app"), False)
        self.assertTrue(zip_status["apple_notarization_accepted_and_stapled"])
        profile_status = build_release.notarization_status("profile", None, True)
        self.assertTrue(profile_status["app_notarized"])
        self.assertTrue(profile_status["dmg_notarized"])

    def test_failed_export_validation_writes_no_release_archive_or_metadata(self):
        source = io.BytesIO()
        with tarfile.open(fileobj=source, mode="w"):
            pass

        def git_output(command, **kwargs):
            if command == ["git", "status", "--porcelain"]:
                return b""
            if command == ["git", "archive", "HEAD"]:
                return source.getvalue()
            raise AssertionError("Unexpected command after failed validation")

        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "release"
            args = [
                "build_release.py",
                "--sign-identity",
                self.identity["sha1"],
                "--notarized-app",
                "export.app",
                "--output-dir",
                str(out),
            ]
            with (
                patch.object(sys, "argv", args),
                patch.object(
                    build_release, "developer_id_identity", return_value=self.identity["sha1"]
                ),
                patch.object(build_release.subprocess, "check_output", side_effect=git_output),
                patch.object(build_release.subprocess, "run"),
                patch.object(build_release, "build_app") as build,
                patch.object(
                    build_release,
                    "validate_notarized_app",
                    side_effect=RuntimeError("missing stapled ticket"),
                ),
                self.assertRaisesRegex(RuntimeError, "missing stapled ticket"),
            ):
                build_release.main()
            build.assert_not_called()
            self.assertFalse((out / "RELEASE-METADATA.json").exists())
            self.assertEqual(list(out.iterdir()), [])

    def test_archive_contains_only_native_app_and_correct_organizer_metadata(self):
        def build(destination, sign_identity, architecture=None):
            app = destination / "UltraConvert.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleIdentifier": "local.ultraconvert",
                        "CFBundleShortVersionString": "1.0.0",
                        "CFBundleVersion": "1.0.0",
                    }
                )
            )
            return app

        with tempfile.TemporaryDirectory() as temp:
            archive = (Path(temp) / "UltraConvert.xcarchive").resolve()
            with (
                patch.object(
                    build_xcode_archive, "developer_id_details", return_value=self.identity
                ),
                patch.object(build_xcode_archive, "build_app", side_effect=build) as build_app,
                patch.object(
                    build_xcode_archive,
                    "app_architectures",
                    return_value=["arm64", "x86_64"],
                ),
            ):
                result = build_xcode_archive.build_archive(
                    archive, self.identity["sha1"], architecture="universal"
                )
            info = plistlib.loads((archive / "Info.plist").read_bytes())
            self.assertEqual(info["ArchiveVersion"], 2)
            self.assertEqual(info["ApplicationProperties"]["Team"], "TEAM")
            self.assertEqual(
                info["ApplicationProperties"]["SigningIdentity"], self.identity["name"]
            )
            self.assertEqual(
                info["ApplicationProperties"]["ApplicationPath"], "Applications/UltraConvert.app"
            )
            self.assertEqual(
                Path(result["app"]), archive / "Products/Applications/UltraConvert.app"
            )
            self.assertEqual(result["architectures"], ["arm64", "x86_64"])
            build_app.assert_called_once_with(
                archive / "Products/Applications",
                sign_identity=self.identity["sha1"],
                architecture="universal",
            )
            with self.assertRaisesRegex(RuntimeError, "never replaced"):
                build_xcode_archive.build_archive(archive, self.identity["sha1"])


if __name__ == "__main__":
    unittest.main()

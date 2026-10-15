"""Keep trusted CI on the registered Mac without hosted fallbacks."""

import subprocess
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = sorted(
    path for path in (ROOT / ".github/workflows").iterdir() if path.suffix in {".yml", ".yaml"}
)


class RunnerPolicyTests(unittest.TestCase):
    def test_inline_shell_steps_have_valid_syntax(self):
        for path in WORKFLOWS:
            workflow = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
            for job in workflow["jobs"].values():
                for step in job.get("steps", []):
                    if "run" in step:
                        with self.subTest(workflow=path.name, step=step.get("name", step["run"])):
                            result = subprocess.run(
                                ["/bin/bash", "-n"],
                                input=step["run"],
                                text=True,
                                capture_output=True,
                            )
                            self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_executable_jobs_select_only_the_registered_mac(self):
        workflows = WORKFLOWS
        self.assertTrue(workflows)
        for path in workflows:
            workflow = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
            for name, job in workflow["jobs"].items():
                with self.subTest(workflow=path.name, job=name):
                    if "uses" in job:
                        self.assertEqual(job["uses"], "./.github/workflows/ci.yml")
                    else:
                        self.assertEqual(job["runs-on"], ["ultraconvert", "local-macos"])
                    self.assertIn("github.actor == 'samuel-zhang01'", job["if"])
                    self.assertIn("github.repository == 'samuel-zhang01/UltraConvert'", job["if"])

    def test_external_pull_requests_cannot_start_owner_machine_jobs(self):
        for path in WORKFLOWS:
            workflow = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
            with self.subTest(workflow=path.name):
                self.assertNotIn("pull_request", workflow["on"])
                self.assertNotIn("pull_request_target", workflow["on"])
        native = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertNotIn("brew install", native)
        self.assertNotIn("actions/setup-python", native)

    def test_static_failures_stop_expensive_native_validation(self):
        workflow = yaml.load(
            (ROOT / ".github/workflows/ci.yml").read_text(), Loader=yaml.BaseLoader
        )
        self.assertEqual(workflow["jobs"]["macos"]["needs"], "static")

    def test_installer_tests_use_the_disposable_native_app(self):
        workflow = yaml.load(
            (ROOT / ".github/workflows/ci.yml").read_text(), Loader=yaml.BaseLoader
        )
        static_steps = str(workflow["jobs"]["static"]["steps"])
        self.assertNotIn("test_installer.py", static_steps)
        native_gate = (ROOT / "scripts/ci_macos.py").read_text()
        self.assertIn('"installer",', native_gate)
        self.assertIn('"ULTRACONVERT_TEST_APP": str(app)', native_gate)


if __name__ == "__main__":
    unittest.main()

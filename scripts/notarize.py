"""Apple notarization using a preconfigured Keychain profile, without plaintext secrets."""

import json
import subprocess


def notarize(path, profile):
    result = subprocess.run(
        [
            "/usr/bin/xcrun",
            "notarytool",
            "submit",
            str(path),
            "--keychain-profile",
            profile,
            "--wait",
            "--timeout",
            "20m",
            "--output-format",
            "json",
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    report = json.loads(result.stdout)
    if report.get("status") != "Accepted":
        raise RuntimeError(
            f"Apple notarization was not accepted (submission {report.get('id', 'unknown')}). Use notarytool log to review it. No release was approved."
        )
    return report["id"]


def staple(path):
    for action in ("staple", "validate"):
        subprocess.run(["/usr/bin/xcrun", "stapler", action, str(path)], check=True)

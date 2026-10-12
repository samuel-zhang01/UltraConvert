"""Create the app-only Sparkle archive and signed GitHub update feed."""

import subprocess
from pathlib import Path

import sparkle


def build_update_assets(app, output, version, architecture, channel=""):
    output = Path(output)
    name = f"UltraConvert-{version}-update-macos-{architecture}.zip"
    archive = output / name
    if archive.exists():
        raise RuntimeError("Update archive already exists; use a new output directory")
    subprocess.run(
        ["/usr/bin/ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True
    )
    with sparkle.distribution() as dependency:
        public = subprocess.check_output(
            [str(dependency / "bin/generate_keys"), "--account", sparkle.KEY_ACCOUNT, "-p"],
            text=True,
        ).strip()
        if public != sparkle.PUBLIC_KEY:
            raise RuntimeError("The Keychain update key does not match the app's public key")
        # Only the app-only update ZIP belongs in generate_appcast's directory.
        import tempfile

        with tempfile.TemporaryDirectory(prefix="ultraconvert-appcast-") as temp:
            staging = Path(temp)
            import shutil

            shutil.copyfile(archive, staging / name)
            notes = staging / (Path(name).stem + ".html")
            notes.write_text(
                f"<h2>UltraConvert {version}</h2><p>Signed app update. Your preferences, saved folder rules and separately installed conversion engines are preserved.</p>\n"
            )
            command = [
                str(dependency / "bin/generate_appcast"),
                "--account",
                sparkle.KEY_ACCOUNT,
                "--maximum-deltas",
                "0",
                "--embed-release-notes",
                "--download-url-prefix",
                f"https://github.com/samuel-zhang01/UltraConvert/releases/download/v{version}/",
                "--link",
                f"https://github.com/samuel-zhang01/UltraConvert/releases/tag/v{version}",
                "-o",
                str(staging / "appcast.xml"),
            ]
            if channel:
                command.extend(["--channel", channel])
            subprocess.run([*command, str(staging)], check=True)
            feed = output / "appcast.xml"
            shutil.copyfile(staging / "appcast.xml", feed)
            subprocess.run(
                [
                    str(dependency / "bin/sign_update"),
                    "--account",
                    sparkle.KEY_ACCOUNT,
                    "--verify",
                    str(feed),
                ],
                check=True,
            )
    return [archive, feed]

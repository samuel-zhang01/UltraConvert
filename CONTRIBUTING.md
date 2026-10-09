# Contributing

Use a small pull request that explains the input case and resulting behaviour. Include a minimal fixture or a reproducible command when fixing a format issue. Do not submit private documents, credentials, DRM-protected material, or full local conversion reports without redaction.

Install with `python3 install.py`, then install development tools in a separate virtual environment:

```sh
python3 -m venv build/dev-env
build/dev-env/bin/pip install -r requirements-dev.txt
build/dev-env/bin/ruff check src scripts tests install.py uninstall.py
build/dev-env/bin/ruff format --check src scripts tests install.py uninstall.py
build/dev-env/bin/bandit -r src scripts install.py uninstall.py -c pyproject.toml
build/dev-env/bin/pip-audit -r requirements.txt
```

Run engine tests with `~/Library/Application Support/UltraConvert/.venv/bin/python`:

```sh
UC_PY="$HOME/Library/Application Support/UltraConvert/.venv/bin/python"
"$UC_PY" tests/test_conversion.py
"$UC_PY" tests/test_edges.py
"$UC_PY" -m unittest discover -s tests -p 'test_security.py' -v
"$UC_PY" -m unittest discover -s tests -p 'test_batch.py' -v
"$UC_PY" -m unittest discover -s tests -p 'test_installer.py' -v
"$UC_PY" -m unittest discover -s tests -p 'test_diagnostics.py' -v
"$UC_PY" -m unittest discover -s tests -p 'test_release.py' -v
"$UC_PY" scripts/benchmark.py
```

Run the native AppKit layout check on macOS (uses public fixtures and does not convert files or change saved preferences):

```sh
mkdir -p build
"$UC_PY" src/convert.py --inspect -- examples/* > build/interface-inspection.json
xcrun swiftc -parse-as-library -D ULTRACONVERT_INTERFACE_TESTS -framework AppKit src/*.swift tests/test_interface.swift -o build/interface-test
build/interface-test build/interface-inspection.json
xcrun swiftc -Osize -parse-as-library -D ULTRACONVERT_INTERFACE_TESTS -framework AppKit src/*.swift tests/test_guidance.swift -o build/guidance-test
build/guidance-test
```

Run native folder-rule tests (uses temporary folders and an injected Trash operation, never user files):

```sh
xcrun swiftc -Osize -parse-as-library -D ULTRACONVERT_INTERFACE_TESTS -framework AppKit src/*.swift tests/test_automation.swift -o build/automation-test
build/automation-test
xcrun swiftc -Osize -parse-as-library -D ULTRACONVERT_INTERFACE_TESTS -framework AppKit src/*.swift tests/test_rule_editor.swift -o build/rule-editor-test
build/rule-editor-test
# Optional real-engine recognition/conversion in a standalone development app:
build/automation-test /Applications/UltraConvert.app
```

For installer tests without a source-installed app in `~/Applications`, point `ULTRACONVERT_TEST_APP` at a freshly built native app. This preserves the signature/resource-fork checks without copying the full engine bundle:

```sh
ULTRACONVERT_TEST_APP="$PWD/build/native/UltraConvert.app" "$UC_PY" -m unittest discover -s tests -p 'test_installer.py' -v
```

Generated reports go to ignored `evidence/local/`. Keep upstream research snapshots unchanged with their licences. Do not change policy to allow network resources, shell interpolation, arbitrary ImageMagick delegates, or execution of TeX. Add regression checks for actual preservation/security risks.

Brand source: `assets/logo.svg` and `scripts/render_icon.swift`; `python3 scripts/build_brand.py` rebuilds PNG and ICNS assets. After committing the source on macOS, `python3 scripts/build_release.py` packages only the public Git tree and the matching app into `dist/VERSION/`. Existing artifacts are preserved; choose a new `--output-dir` for another build. See [the macOS signing guide](docs/MACOS-RELEASE.md) for Developer ID and notarization.

Be kind, specific, and constructive in discussions. Support reports should identify macOS, architecture, engine version and source/target formats.

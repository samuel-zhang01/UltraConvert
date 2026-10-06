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
"$UC_PY" scripts/benchmark.py
```

Generated reports go to ignored `evidence/local/`. Keep upstream research snapshots unchanged with their licences. Do not change policy to allow network resources, shell interpolation, arbitrary ImageMagick delegates, or execution of TeX. Add regression checks for actual preservation/security risks.

Brand source: `assets/logo.svg` and `scripts/render_icon.swift`; `python3 scripts/build_brand.py` rebuilds PNG and ICNS assets. After committing the source on macOS, `python3 scripts/build_release.py` packages only the public Git tree and the matching app into `dist/`.

Be kind, specific, and constructive in discussions. Support reports should identify macOS, architecture, engine version and source/target formats.

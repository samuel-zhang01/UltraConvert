# Release audit — 1.1.0

Verified 2026-10-06 on Apple Silicon/macOS 27 with installed Homebrew engines. This is an adversarial code review and regression suite, not an independent penetration test or a guarantee about arbitrary files.

## Findings resolved

| Risk | Change and evidence |
| --- | --- |
| Archive traversal, symlinks, duplicates, encrypted members and decompression pressure | Archive preflight rejects unsafe members, limits entry count and declared expansion, and bounds XML members. Malicious archive cases are tested. |
| YAML tags, alias expansion, deep structures and silent type coercion | SafeLoader subclass, depth/alias/node budgets, bounded reads and typed round-trip comparison. Unsafe tags and repeated aliases are tested. |
| XML entities and GIS external styles/schemas | defusedxml preflight rejects DTD/entities; GDAL disables external KML style lookup, schema download and GML element resolution. A loopback server observed zero requests in document/KML regression checks. |
| Document image reads outside the selected folder | Resolved paths must remain inside the source folder or conversion staging folder. Parent traversal, absolute escapes, symlinks and remote resources fail. |
| ImageMagick delegates and unexpected pseudo-formats | A repository policy allows only the required coders, denies delegates/filters/indirect reads, limits resources, and avoids filename interpretation during probing. Disguised SVG is refused. |
| Unbounded subprocess diagnostics, engine thread multiplication and stuck cancellation | File-backed bounded diagnostics, bounded native capture, two engine threads, one to four jobs, process-group TERM followed by KILL. TERM-ignoring and oversized-stderr cases are tested. |
| Inputs changed after inspection and overwriting files | Fingerprints checked before conversion, unique batch folders, temporary staging and original hashes. Repeated runs and identical basenames are tested. |
| GML reader creating caches beside the original | GML is copied to staging before GDAL reads it, including an optional local bounded XSD. XML entities and arbitrary XSD includes/imports are refused; standard OGR/GML references are retained with schema fetching disabled. |
| Failed installation replacing working components | Full payload staging, atomic renames, cross-component rollback, ownership checks, verified archived app backups. An injected failure during the second component swap restores all originals; uninstall refuses unowned runtimes without creating files. Bootstrap code is checked against Python 3.9 syntax. |
| Native UI deadlock or surprising conversion | Concurrent stderr drain, bounded output capture, busy guards, remembered controls, queued incoming files, and folder-picker cancellation that starts no batch. |
| Public machine details and repository supply chain | Local installation/migration reports excluded from the public tree; the historical Moonvert dependency manifest retains exact bytes under `.snapshot` so it is not mistaken for an app dependency; source research licences retained; GitHub Actions pinned to commit hashes with read-only permissions. |
| Lost Finder icons during an update | Automator custom-image metadata and a native Finder document icon are installed together. `ditto` preserves FinderInfo and resource forks; the installer regression compares both before and after staging. |
| Setup checks hanging or claiming partial success | Fixed argument-array version probes have timeouts and bounded diagnostics. Missing tools, broken imports and malformed workflows report attention rather than aborting all checks. |
| Stale results or formats after a new batch | Incoming selection clears previous results, reports, summaries and category controls before inspection. Setup checks share the converter's engine resolver. |
| Development signing mistaken for public Apple approval | Exact valid Developer ID Application identity required; notarization must return Accepted before stapling and Gatekeeper checks. Tests reject development certificates and rejected submissions. Real Apple submission remains unverified until distribution credentials are provisioned. |

## Verification

- All **62 format entries** passed representative write, content detection and reverse-conversion checks, with **14 additional correctness checks**.
- **10 edge cases** passed: document image bytes/relative exports/missing and remote resources, sidecar selection, multipage TIFF, misleading media extension and cancellation preservation.
- **18 adversarial security**, **4 batch workflow**, **6 installer bootstrap/icon/ownership/rollback**, **5 diagnostics**, and **4 signing/notarization gate** tests passed. Together with format and edge checks, this is 123 representative checks.
- Ruff lint/format checks and Bandit passed. B404/B603 are documented exclusions for intentional argument-array subprocess calls; SafeLoader subclass use has a narrowly justified B506 annotation and executable-tag regression test.
- pip-audit reported no known vulnerabilities for the three pinned runtime packages on the audit date. This result does not audit every native engine or dev-tool dependency.
- Native Swift compilation, Hardened Runtime and ad-hoc signature verification passed. Offline Quick Start, Finder Settings navigation, branded Settings rows, setup diagnostics and setup-report copying were checked interactively. The two actions appear for mixed Finder selections. Menu dispatch could not be confirmed with the current UI automation session; prior 1.0.0 interactive batch evidence is retained separately and is not treated as a 1.1.0 check. Individual evidence and source hashes are in [release-verification.json](../evidence/release-verification.json).
- Reproducible small-file benchmark: 40 fixtures at one/two/four jobs. Timings are in [benchmark.json](../evidence/benchmark.json); these do not predict long video, huge TIFF or GIS workloads.

## Limits retained explicitly

The app and engines run with the current user's permissions; there is no OS-level parser sandbox. Guards reduce known attack surfaces, but complex third-party decoders remain a trust boundary. Output staging avoids incomplete published results, but a killed process or power loss can leave a temporary directory. Size/resource limits are deliberate and may reject large or unusual valid inputs. Archive header checks do not replace engine-level memory safety.

Reports contain local source paths, engine arguments and diagnostics. No conversion uploads or analytics are implemented. Install-time dependency downloads and user-selected result opening are expected.

The binary release is Apple Silicon, ad-hoc signed with Hardened Runtime and not notarized. The optional Developer ID/notarization/DMG pipeline is implemented; actual Apple acceptance and stapled-ticket checks require a real distribution certificate and Keychain profile. The app still needs a separately provisioned conversion runtime. Native deployment target is macOS 13; actual verification is macOS 27. Intel and older macOS are source-build paths and unverified. Formats use representative fixtures, not exhaustive codec/layout/schema coverage. See the README preservation limits and [macOS release guide](MACOS-RELEASE.md).

## Primary technical references

[Pandoc security](https://pandoc.org/demo/example33/22-a-note-on-security.html), [Pandoc manual](https://pandoc.org/MANUAL.html), [ImageMagick policy](https://imagemagick.org/script/security-policy.php), [GDAL LIBKML](https://gdal.org/en/stable/drivers/vector/libkml.html), [GDAL GML](https://gdal.org/en/stable/drivers/vector/gml.html), [Python subprocess](https://docs.python.org/3/library/subprocess.html), [GitHub runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Converter project research is in [research/REVIEW.md](../research/REVIEW.md).

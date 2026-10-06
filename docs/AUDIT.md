# Release audit — 1.3.0

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
| Inputs changed after inspection and overwriting files | Fingerprints checked before conversion, exclusive direct filenames for Convert Here, unique destination batch folders, temporary staging and original hashes. Repeated runs and identical basenames are tested. |
| GML reader creating caches beside the original | GML is copied to staging before GDAL reads it, including an optional local bounded XSD. XML entities and arbitrary XSD includes/imports are refused; standard OGR/GML references are retained with schema fetching disabled. |
| Failed installation replacing working components | Full payload staging, atomic renames, cross-component rollback, ownership checks, verified archived app backups. An injected failure during the second component swap restores all originals; uninstall refuses unowned runtimes without creating files. Bootstrap code is checked against Python 3.9 syntax. |
| Native UI deadlock or surprising conversion | Concurrent stderr drain, bounded output capture, busy guards, remembered controls, queued incoming files, and folder-picker cancellation that starts no batch. |
| Public machine details and repository supply chain | Local installation/migration reports excluded from the public tree; the historical Moonvert dependency manifest retains exact bytes under `.snapshot` so it is not mistaken for an app dependency; source research licences retained; GitHub Actions pinned to commit hashes with read-only permissions. |
| Lost Finder icons during an update | Automator custom-image metadata and a native Finder document icon are installed together. `ditto` preserves FinderInfo, resource forks and app bundle metadata; installer regressions compare metadata before/after staging and verify the copied app signature. |
| Setup checks hanging or claiming partial success | Fixed argument-array version probes have timeouts and bounded diagnostics. Missing tools, broken imports and malformed workflows report attention rather than aborting all checks. |
| Stale results or formats after a new batch | Incoming selection clears previous results, reports, summaries and category controls before inspection. Setup checks share the converter's engine resolver. |
| Development signing mistaken for public Apple approval | Exact valid Developer ID Application identity required; notarization must return Accepted before stapling and Gatekeeper checks. Tests reject development certificates and rejected submissions. Real Apple submission remains unverified until distribution credentials are provisioned. |

## Verification

This update improves native file/context actions, recovery, skipped-only feedback, Finder format presets and queue responsiveness. The conversion engine and direct-output placement remain unchanged.

- All **62 format entries**, **14 additional correctness checks**, **10 preservation edge checks**, **18 security checks**, **13 batch/placement checks**, **8 installer checks**, **5 diagnostic checks** and **4 release-gate checks** passed locally: **134 representative checks**, plus expanded native AppKit assertions. Main CI repeats the full corpus and native tests.
- The installed candidate completed a mixed batch with six successes and one unsupported-file failure, preserved originals, reloaded only the failure for retry, and retained the current batch on destination-picker cancellation. A skipped-only batch kept Report and hid Show Results.
- Both general Finder Quick Actions cold-launched with correct source/mode. Native WebP and MP3 presets delivered the correct selection/target; WebP conversion and row result reveal were verified. Image/audio menus showed their applicable presets.
- Native tests cover compact completion controls, compatible/unavailable presets, busy/invalid service requests, input bounds/deduplication, merged incoming selections, and fragmented 1,000-file completion events. Cached rows and coalesced changed-row refreshes avoid full rebuilds on every completion. [Performance evidence](../evidence/performance-1.3.0.json) and [UX scoring/limits](UX-AUDIT.md) separate synthetic UI measurements from conversion throughput.
- Ruff lint/format, Bandit and runtime dependency audit passed. Existing Apple Development signing verifies locally; public artifacts remain ad-hoc signed and unnotarized. No experimental workflow handoff helper is shipped.
- Current source hashes and checks are in [release-verification.json](../evidence/release-verification.json); the prior placement audit is retained in [1.2.1 evidence](../evidence/releases/1.2.1.json). The native format presets are allowlisted and use file-URL pasteboard input, the same recognition path and an explicit Convert action. Busy requests fail without changing the running batch.

## Limits retained explicitly

The app and engines run with the current user's permissions; there is no OS-level parser sandbox. Guards reduce known attack surfaces, but complex third-party decoders remain a trust boundary. Convert Here uses atomic exclusive hard links for standalone outputs where supported. On volumes without hard links, it uses exclusive creation and removes a failed or cancelled copy. Multipart outputs use one exclusively named folder. Abrupt process termination or power loss during a copy/folder publication can leave partial output; these cases cannot be made a filesystem-wide transaction. Destination staging can also leave temporary directories after a killed process. Size/resource limits are deliberate and may reject large or unusual valid inputs. Archive header checks do not replace engine-level memory safety.

Reports contain local source paths, engine arguments and diagnostics. No conversion uploads or analytics are implemented. Install-time dependency downloads and user-selected result opening are expected.

The binary release is Apple Silicon, ad-hoc signed with Hardened Runtime and not notarized. The optional Developer ID/notarization/DMG pipeline is implemented; actual Apple acceptance and stapled-ticket checks require a real distribution certificate and Keychain profile. The app still needs a separately provisioned conversion runtime. Native deployment target is macOS 13; actual verification is macOS 27. Intel and older macOS are source-build paths and unverified. Formats use representative fixtures, not exhaustive codec/layout/schema coverage. See the README preservation limits and [macOS release guide](MACOS-RELEASE.md).

## Primary technical references

[Pandoc security](https://pandoc.org/demo/example33/22-a-note-on-security.html), [Pandoc manual](https://pandoc.org/MANUAL.html), [ImageMagick policy](https://imagemagick.org/script/security-policy.php), [GDAL LIBKML](https://gdal.org/en/stable/drivers/vector/libkml.html), [GDAL GML](https://gdal.org/en/stable/drivers/vector/gml.html), [Python subprocess](https://docs.python.org/3/library/subprocess.html), [GitHub runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Converter project research is in [research/REVIEW.md](../research/REVIEW.md).

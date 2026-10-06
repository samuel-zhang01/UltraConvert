# Changelog

## 1.4.0 — in development

- Self-contained local-development app builder: private Python/packages, all conversion engines, dependent libraries, decoder modules and GIS data live inside the app.
- Native runtime selection with isolated Python startup; bundled tools never silently fall back to Homebrew or PATH.
- Native first-launch Finder Quick Action installation uses the actual app location, preserves owned earlier actions and refuses unrelated installations.
- Drag-to-Applications development DMG tooling, dependency provenance and standalone conversion verification.
- Public standalone binary distribution remains gated on corresponding-source/licence completion, Developer ID signing, notarization and quarantined clean-Mac checks. The current local engine bundle requires Apple Silicon/macOS 27.

## 1.3.0 — 2026-10-06

- Six native Finder Services presets: PNG, JPEG, WebP, MP3, Opus and MP4. Shortcuts choose a compatible format and open a reviewable batch; a running batch is never interrupted.
- File-row context actions for original/result reveal, file-name/error copying and removal; Retry Failed reloads failed files for recognition and review.
- Source → target previews, concise actionable error labels, separate status/action rows and compact-window checks for completed batches.
- Skipped-only batches no longer offer empty results or claim files were saved. Cancelled recognition has a specific message, and pending incoming file selections merge without losing earlier selections.
- Cached queue rows and coalesced updates replace repeated whole-queue rebuilding/redrawing. A five-sample synthetic benchmark reduced recognition-row preparation from 1.62s to 0.12s for 1,000 rows; this does not measure engine speed or real-user latency.
- Expanded native regression checks and documented a 9.0/10 developer UX assessment with remaining validation limits.

## 1.2.1 — 2026-10-06

- Convert Here places ordinary outputs directly beside their originals, with no batch or per-file folder. Existing names get numbered suffixes; originals and existing outputs are retained.
- Formats with linked media or multiple companion files use one adjacent folder, preserving relative references and GIS sidecars.
- Convert Here reports live separately in Application Support; Report still reveals them, and Show Results selects the actual converted files.
- Added real OPUS→MP3, repeat/concurrent/case-insensitive collision, symlink, unsupported-hard-link, cancellation, GPKG and document/sidecar placement regressions.

## 1.2.0 — 2026-10-06

- Modern native layout with rounded content cards, clearer typography, system colours and a fixed conversion bar. Liquid Glass on macOS 26+, with a native material fallback on older systems.
- File queue with Finder icons, detected types and per-file conversion results; drag and drop, Add Files, Remove Selected, Delete and Clear. Repeated paths are ignored when appending.
- Independently scrolling queue and grouped format selectors keep mixed batches compact. Chosen formats survive queue edits.
- Clearer destination choices, collapsible Batch options, file counts on Convert and distinct busy/completed/attention states.
- Updated offline Quick Start and README for the new controls. Public builds remain ad-hoc signed and unnotarized.

## 1.1.0 — 2026-10-06

- Matching logo icons in both Finder Quick Actions and macOS 27's Finder Settings list, with resource forks preserved during installation.
- Offline Quick Start, Finder Settings shortcut, local setup diagnostics and optional setup-report copying.
- Show Report, open the default destination, copy result counts, clearer destination paths and remembered file-picker folders.
- Category/control symbols and scrolling for mixed batches on smaller screens.
- Clear stale batch state after a new selection or conversion; friendly installer errors and numbered next steps.
- Expanded README with installation walkthroughs, first-batch examples, destination choices, permissions and troubleshooting.
- Hardened Runtime builds and optional Developer ID/notarization/stapling/Gatekeeper/DMG release pipeline. Published 1.1.0 remains ad-hoc signed and unnotarized pending distribution credentials.

## 1.0.0 — 2026-10-06

- Native AppKit app with a minimal U-arrow icon, six category format selectors and content-aware recognition.
- Two Finder actions: Convert Here and Convert to Destination, each supporting single files and mixed batches.
- Saved default destination, saved output formats, one to four jobs, skip-matching and open-results options.
- Fresh output folders, original preservation, result reports, failure isolation and reliable cancellation.
- 62 representative format round trips, geospatial sidecars/layers, document image resources and genuine Kindle/APE/ALAC routing.
- Archive/parser/resource safeguards, restricted engine policies, installer ownership checks, rollback and recoverable uninstall.
- Public source research, verification evidence, contribution/security guidance and pinned-action CI.

# Changelog

## 1.6.0 preview — 2026-10-09

- First-use Getting Started window with task guides and direct routes for manual conversion, Finder, folder rules and startup. Visible Settings and numbered conversion steps.
- Plain-language advice for all 62 output formats; clearer Quick Actions vs Services and login-off state.
- Mixed-selection shortcuts require compatible targets for every file. Finder presets that cannot apply to the whole selection block conversion until explicit per-category review.
- Persistent rule setup checklist, ALL/ANY/wait explanations, unsaved-state text and reachable read-only preview details with full output/archive paths. Run Existing Files respects saved-rule prerequisites.
- Discard resets hidden original-removal acknowledgement; source and cancellation protections remain covered.
- Developer ID/Xcode archive support with source provenance, strict signed-export/ticket/Gatekeeper gates and truthful per-artifact notarization metadata. Engines remain a separate public installation; the complete bundled development app retains its distribution gates.
- Canonical ICNS artwork for Finder document icons avoids a reproduced nonfatal macOS 27 IconServices fault during registration; Quick Action artwork stays in place.
- Automatic Finder setup recognises only the system/user Applications roots, including subfolders; launching Xcode archive candidates cannot repoint installed workflows.

## 1.5.1 preview — 2026-10-07

- Rule navigation/closing offers Save Changes, Keep Editing and Discard Changes. Discard actually restores the saved rule; failed saves block navigation.
- Cancellable, serialized read-only file tests. Edits, rule switches, window closing and quit invalidate late results; quit waits for test cleanup.
- Test previews refuse linked or changed sources and apply the same document/GIS source-action protections as conversion.
- Native Undo/Redo/Cut and Close Window commands; an explicit Cancel/Escape action in the Finder format chooser.
- Explicit app-delegate retention across the event loop so optimized builds keep their controllers/actions alive.
- Cached Activity date formatting and complete empty-row reset when table cells are reused.
- The neutral native glass design and existing format support remain in place. Public packaging retains the separate-runtime installer and is not notarized.

## 1.5.0 preview — 2026-10-07

- Native folder automation with a neutral native glass block rule builder, templates, ALL/ANY content/name conditions, ordered conversion and rename steps, output routing, and explicit after-success Keep/Archive/Trash policies.
- Event-driven watching, stable-file waiting, first-match priority, one automation job at a time, manual-batch priority, menu-bar pause/resume and persistent local activity. Existing files are ignored on startup; Run Existing Files is an explicit action.
- Safety limits, exclusive output publication, loop prevention, source-change/cancellation checks, linked-file exclusion and a cross-process watcher lock. Document/GIS originals must be kept because of companion resources.
- Finder “Convert Here with UltraConvert — Choose Format…” service with a grouped picker for all 62 formats; category/format submenus in the app's file-row menu. Finder Services/Quick Actions remain flat under macOS control.
- Optional start-in-menu-bar setting alongside Launch at Login and automatic Finder registration. Default startup preferences stay off unless enabled by the user.
- Size-optimised Swift compilation; no conversion subprocess or polling timer while folder watching is idle.
- Public preview retains the separate engine installer and is not notarized. The local standalone development app retains all engines and format support.

## 1.4.0 preview — 2026-10-06

- Native Settings (⌘,): optional Launch at Login with macOS approval/error status, automatic Finder registration preference, manual Quick Action repair, Services refresh and system settings shortcuts. Repair templates are included in every native app.
- Public preview includes the native app with the established runtime installer; engines are downloaded separately. It is ad-hoc signed and unnotarized.
- Self-contained local-development app builder: private Python/packages, all conversion engines, dependent libraries, decoder modules and GIS data live inside the app.
- Native runtime selection with isolated Python startup; bundled tools never silently fall back to Homebrew or PATH.
- Native first-launch Finder Quick Action installation uses the actual app location, preserves owned earlier actions and refuses unrelated installations.
- Smaller development bundles preserve all exported symbols, geographic precision grids and Calibre plugins while removing debug/local symbols and Python development headers.
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

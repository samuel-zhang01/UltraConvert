# Native UX crawl — 1.3.0

Developer assessment on Apple Silicon/macOS 27, 2026-10-06: **9.0/10** for the scoped native conversion and Finder flows. This is a judgment against the checks below, not an independent review, usability study or security rating. Scores weight each area equally. A 9 means the named checks pass and no known blocking issue remains in those checked flows; remaining validation gaps are explicit.

| Area | Before | After | Evidence and remaining gap |
| --- | --- | --- | --- |
| Clarity and feedback | 7 | 9 | Source → target previews, concise unsupported/failed labels, explicit skipped-only message, separate status/actions. Full error details remain accessible. Document/codec tradeoffs still require the guide/report. |
| Recovery and input handling | 6 | 9 | Mixed batch: six successes and one failure; Retry Failed reloads only the failure for review. Destination picker cancellation starts nothing. Incoming busy selections merge; bounds and deduplication apply to every entry. Completed reports remain on disk when a new selection replaces the window. |
| Finder and context actions | 7 | 9.5 | Both original Quick Actions delivered a WAV from cold launch with correct Here/saved-destination mode. Finder image/audio presets appeared; WebP and MP3 delivered the correct selection/target. File-row source/result/error/remove actions expose useful commands. Finder's type-based filtering can hide presets for a misleading extension; use the general actions then. |
| Responsiveness and bounded work | 7 | 9 | Cached queue rows; completion updates coalesce to changed-row reloads every 100ms. Fragmented 1,000-file event test retained every outcome and used one row refresh. Five alternating optimized-build samples measured row preparation at 1.619s before and 0.124s after. This is synthetic UI preparation, not engine speed, drawing or perceived latency. |
| Native layout and accessibility | 8 | 8.5 | Compact 760×570 layout checks keep Convert/Report/Results/Retry inside the window. Native keyboard commands, semantic labels, text statuses, independent scroll areas and system colours/materials. Manual VoiceOver, light appearance, older macOS and reduced-transparency combinations remain unverified. |

## Iterations

1. Read the coordinator, views, installer, engine and existing tests; crawled the public mixed-format fixtures with an unsupported file. Resolved whole-queue rebuilding/redraws, missing row actions, pending-selection replacement and incorrect empty-result actions.
2. Exercised the installed app: mixed conversion, retry, destination cancellation, WebP preset/conversion/result reveal, MP3 preset cold launch and both general Quick Actions. Refined verbose error labels and completion text; added preset/compact-footer/fragmented-event assertions.
3. Compared optimized native builds, ran engine throughput and the full preservation/security/installer corpus, and visually inspected completion. A proposed workflow reuse bridge failed cold-launch checks and was removed. The two general Quick Actions retain their established new-window behaviour; native format shortcuts reuse an idle app and reject busy requests. No experimental helper is shipped.

## Reproduce the checks

The native regression command is in [CONTRIBUTING.md](../CONTRIBUTING.md). It exercises the real AppKit hierarchy rather than a separate mock interface. [Performance evidence](../evidence/performance-1.3.0.json) records five samples and small-file engine throughput. The benchmark source is [benchmark_interface.swift](../scripts/benchmark_interface.swift); compile with the same app sources and `-O -D ULTRACONVERT_INTERFACE_TESTS`. The older source comparison adds `-D BENCHMARK_BASELINE` and uses the v1.2.1 App.swift/Interface.swift files.

Engine tests cover representative fixtures, not all codecs, large-media memory behaviour or document/GIS schemas. UI tests do not replace Instruments profiling or accessibility/user research. The unchanged parser trust boundaries and distribution limits are documented in [AUDIT.md](AUDIT.md).

Native Finder presets use [Apple's Services properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html) and [service-provider registration](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html). macOS chooses menu placement and applicable file types; these are not a custom Finder Sync extension.

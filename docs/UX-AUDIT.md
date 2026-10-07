# Native UX crawl — 1.5.0 preview

Developer assessment on Apple Silicon/macOS 27, 2026-10-07: **9.0/10** for the checked rule-builder, conversion and supported Finder flows. This is a scoped developer judgment, not an independent usability study, security certification or a promise about every file. Equal weighting of the six areas below gives 9.0.

| Area | Final score | Evidence and remaining limit |
| --- | --- | --- |
| Layout and visual fit | 9.2 | Actual window crawl corrected a narrow editor, removed the user's rejected accent stripes/outlines and adopted neutral `NSGlassEffectView` editing surfaces. Light/dark minimum-size bounds and opaque Reduce Transparency fallback pass. Older OS appearance remains unverified. |
| Clarity and modularity | 9.0 | WHEN/IF/THEN/SAVE/AFTER SUCCESS text, templates, ALL/ANY conditions, ordered convert/rename steps, explicit enabling, read-only test plans, priority controls and clear folder requirements. These are constrained safe blocks, not a general scripting language. |
| Recovery and source safety | 9.3 | Partial/growing inputs, failure/cancellation, collisions, source replacement, archive/Trash failure and recovery are covered. Existing names are never replaced. GIS/document source-removal is refused; companions remain bundled. Recovery paths appear in selectable Activity details if the original name becomes occupied. |
| Responsiveness and bounded work | 9.2 | Native coalesced events, utility-queue scans, stable-file waiting, no idle engine/polling timer, one automation job and manual-batch priority. Shared roots scan once. Activity uses reusable visible table rows instead of rebuilding 200 glass cards. Local five-second idle and 1,000-file scan evidence are linked below; large-media engine memory is unmeasured. |
| Finder and startup integration | 8.5 | Seven native Services, grouped format picker, all 62 targets in app context submenus, existing Quick Actions and real macOS login-service state/error handling. macOS Services/Quick Actions are flat; a custom nested Finder extension is not shipped. Actual login enabling remains untested and off by default. |
| Accessibility and motion | 8.8 | Native controls/keyboard behaviour, semantic labels, selectable diagnostics and text flow roles. No looping custom animation; native glass/popups use system behaviour, with explicit Reduce Transparency fallback. Manual VoiceOver, reduced-motion interaction and independent user testing remain gaps. |

## Iterations and verification

1. Added typed native models, persistence, an injectable conversion pipeline and the block editor. Tests exercise real FSEvents and actual bundled content recognition/conversion, alongside temporary deterministic fixtures.
2. Reviewed failures and concurrency: explicit first-match ordering, original-removal acknowledgement, post-success identity/hash checks, exclusive output publication, source quarantine/restoration, process cancellation and one watcher lock across app instances. Pause now persists across restarts; moved watch roots pause. Internal staging is excluded, including macOS path aliases.
3. The visual crawl found unused right-side space despite controls satisfying bounds. Corrected full-width editor layout and minimum widths for condition/rename values. The user's visual feedback removed coloured edge bars and outlines; native glass and neutral fallback cards replace them.
4. Replaced per-event full Activity stacks with a virtualized native table, bounded storage and source-safe recovery text. A second installed-app crawl corrected cramped outcome text; long editor diagnostics are capped with the full text in a tooltip. Shared-root scans, capped candidates/traversal and immutable startup baselines bound work. Disabled-draft saves leave active rules undisturbed.
5. Ran **231 automation checks**, existing native interface/backend tests, installer signature/resource-fork/rollback checks and the full sealed-runtime conversion/preservation/security/batch corpus. New tests use temporary folders and an injected Trash destination; they do not trash user files.

[Local automation/performance evidence](../evidence/automation-1.5.0.json) records a quiet five-second sample (0.005967 CPU seconds, about 0.12% of one core), a 1,000-small-file scan (0.0066 seconds) and a 33.1 MB test-process peak before creating the editor. This fixture process is separate from the installed GUI: one snapshot with the rule editor and one active watch measured about 114 MiB RSS and 0.0% CPU. Neither measurement captures engine peaks or long-duration energy use. The same-source signed native executable fell from 961,488 bytes (`-O`, unstripped) to 583,728 bytes (`-Osize`, local/debug names stripped), about 39.3%. Exported/runtime symbols and all engine capabilities stay present; the full app remains dominated by engines/data.

Reproduction commands are in [CONTRIBUTING.md](../CONTRIBUTING.md). [Apple's Services documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html) confirms the submenu limit. [Finder Sync](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) supports custom menus for monitored folders through a separate extension. Native glass uses [Apple's AppKit API](https://developer.apple.com/documentation/appkit/nsglasseffectview).

## Earlier conversion crawl — 1.3.0

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

# First-use crawl — 1.6.0 preview

An independent coding agent assessed first-use learnability on Apple Silicon/macOS 27 on 2026-10-09. The unchanged beginner-weighted rubric improved from **7.85/10 to 9.04/10**, rounded to **9.0/10**. This is a developer heuristic assessment, not a human usability study or a claim of functional perfection.

| Dimension | Weight | Before | After |
| --- | --- | --- | --- |
| Discovery and navigation | 25% | 7.0 | 9.2 |
| First manual conversion | 20% | 9.0 | 9.0 |
| Destinations and options | 15% | 8.5 | 9.1 |
| Learning folder automation | 20% | 7.5 | 9.0 |
| Finder and startup setup clarity | 10% | 6.5 | 9.0 |
| Safety and recovery | 5% | 9.0 | 9.0 |
| Native layout and accessibility | 5% | 8.5 | 8.5 |

The baseline crawl identified hidden settings, an unhelpful first-launch alert, unexplained format choices, disappearing rule setup guidance and ambiguous registration/status wording. The revised app has a nonmodal four-topic Getting Started guide with direct task buttons, visible Settings/help controls, numbered conversion stages, advice for all 62 formats, a persistent rule checklist, explicit ALL/ANY and settling explanations, and separate Quick Actions/Services setup instructions. Login opt-out has neutral wording; actual enable failures remain errors.

The grader observed the guide, settings and rule-editor improvements, Add Files/content recognition on a mixed PNG/WAV queue, and disabled incompatible single-target context commands. The baseline actual WAV-to-MP3 task succeeded beside its source with collision-safe naming. macOS ScreenCaptureKit failures interrupted the final revised-candidate Convert/full-preview interactions; those two final UI tasks are still pending and are not represented as independently observed successes.

Regression checks cover the real native AppKit hierarchy, first-use persistence and noninterruption, compact guide bounds, all format advice, mixed/unsupported context selections, Finder presets that require an explicit compatible choice, stale-preview invalidation, selectable full plans and Discard restoring Archive acknowledgement. **305 automation assertions pass**, including real filesystem events and bundled recognition/conversion. [Automation evidence](../evidence/automation-1.6.0.json) records a five-second idle fixture sample and a 1,000-file scan. The unchanged engine bundle also passes the full representative conversion, preservation, security and batch corpus.

Manual VoiceOver, older macOS, actual login activation, long-duration energy use and conversion-engine peak memory remain unverified. Native controls and system animation are retained; no additional custom animation or idle engine process was introduced.

A single idle 1.6 candidate snapshot with two queued files measured about **159 MiB RSS and 0.0% CPU**. The automation fixture used 0.0053 CPU seconds over five seconds and scanned 1,000 small files in 0.0068 seconds. These short local observations are not engine-peak or long-duration energy measurements. The signed native app is about 1.6 MiB on disk; the complete local engine app remains about 1.9 GiB and is dominated by unchanged conversion engines/data.

# Refinement crawl — 1.5.1 preview

The 1.5.0 scoped developer assessment remains **9.0/10**; this patch closes additional correctness and keyboard gaps found during a second code/UI review.

- Discard now reloads the saved rule instead of retaining edited fields in memory. Save commits before navigation; failed validation keeps the editor open.
- Read-only tests have Cancel Test/Escape, cancellation on rule changes/closing/quit, serialized engine work and suppression of stale plans. Quit waits for test work to drain.
- Previews reject linked/changed sources and document/GIS original policies that the actual pipeline would refuse.
- The app explicitly retains its weak AppKit delegate across the event loop, including optimized builds.
- Standard Mac text editing and Close Window commands are present; the grouped Finder chooser cancels with Escape. Activity reuses a date formatter and resets empty-row diagnostics.

All **265 local automation assertions passed**. [Regression evidence](../evidence/automation-1.5.1.json) covers these cases alongside the existing watcher, publication and source-integrity checks. The underlying conversion engines are unchanged. The independent accessibility/user-study, older-system and public standalone-distribution gaps below still apply.

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

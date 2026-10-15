# 1.9.0 interface and motion audit — 2026-10-15

The final reviewed interface passes the frozen **overall ≥9.5** gate at **9.53575/10**, rounded **9.54**. Every surface is ≥9.0 and no confirmed blocking overlap, clipping, hidden essential feedback or destructive ambiguity remains in the checked flows. This is an independent developer heuristic assessment, not a novice-user study or a claim of functional perfection. **Release publication and the actual installed Homebrew upgrade passed separate checks**, recorded in the [release evidence](../evidence/releases/1.9.0.json) and [upgrade evidence](../evidence/homebrew-upgrade-1.9.0.json). The UI score does not establish either result.

| Surface | Weight | Final score |
| --- | ---: | ---: |
| Converter | 20% | 9.530 |
| Settings | 20% | 9.555 |
| Puzzle builder | 25% | 9.575 |
| Activity | 10% | 9.460 |
| Finder format picker | 10% | 9.525 |
| Getting Started | 5% | 9.540 |
| Menus and dialogs, including conversion reports | 10% | 9.495 |

Each surface uses the same frozen criteria: alignment and spacing **25%**, comprehension **25%**, state and recovery **20%**, native behavior **15%**, and accessibility **15%**. Passing requires ≥9.5 overall, every surface ≥9.0, and no confirmed blocking defect in the checked flows. The readable report's standalone **9.565** assessment contributes to menus/dialogs; it is not counted again as an eighth surface. Exact criterion scores, source fingerprint and scope are in the [component evidence](../evidence/ui-components-1.9.0.json).

The final source was reviewed through actual native AppKit captures: all three Settings panes, five converter states, the puzzle builder/Activity/Activity Details, all four guide topics, and report success/failure and unavailable states at normal/minimum sizes in light/dark appearances. The fixed-size Finder picker was checked in both appearances. Compact endpoints also verified Settings' last Finder action, rule conditions/actions/original-file acknowledgements, Activity's last Details button, guide instructions, expanded Batch options and the Save location jump. Busy/error layout fixtures are explicitly simulated; separate real GUI conversions exercised six input categories and an audio quality change with a readable completed report. Raw audit captures remain private; representative current views are the [converter](images/converter.png), [General settings](images/settings.png), [updates](images/app-updates.png), [Finder settings](images/finder-settings.png), [conversion report](images/conversion-report.png) and [guide](images/getting-started.png).

The review held Settings below the gate until essential instructions/statuses used full semantic label colour. Other repairs align action columns, explain dependent startup options, retain a recovery menu icon for minimized login, keep the current destination visible beside conversion actions, label optional geospatial CRS explicitly, and make the Finder picker's controls span their row. Complete errors and results are readable through Activity Details and Conversion Report. The in-app context menu now hides incompatible formats and irrelevant result/error commands. Actual nested context menus were visually inspected; App/File/Window/Help menus were opened and verified through native accessibility state and source. Top-menu screenshots were unavailable, so they are not claimed as visual proof.

The user's later report of an odd Custom quality animation reopened the applicable gate. The repair settles stack visibility and layout immediately, makes one clamped minimal scroll adjustment, then applies only the shared **180 ms ease-in/ease-out** content fade. It avoids competing animated constraints and clip bounds. **85 native compression checks pass**, including a running AppKit event loop, nine rapid toggle changes sampled at 25 ms, interrupted-scroll cancellation, compact checkbox/full-estimate visibility, stable geometry after 300 ms, Reduce Motion endpoints, and switching to FLAC during an active fade. Fresh normal and compact native on/off/on captures were independently inspected: the footer stays fixed, estimates remain complete and repeated endpoints stay stable. The original **9.53575** grade was reaffirmed without an increase. These checks establish stable sampled behavior; perceived smoothness and frame-time distributions were not measured.

The design follows Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [materials](https://developer.apple.com/design/human-interface-guidelines/materials), [menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) and [context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) guidance. Native toolbar panes, standard checkboxes, readable content and restrained glass remain consistent across the app. Remaining deductions include nested scrolling, subdued quality explanations, Activity's implicit global-history scope, and the requested context hierarchy exceeding Apple's usual single-submenu preference. They are recorded limitations, not confirmed blockers.

Slider movement updates local controls and debounces preference writes; it starts no conversion engine and adds no recurring animation timer. The separate automation fixture used **0.009952 CPU seconds over five seconds**, scanned 1,000 small files in **0.005585 seconds**, and peaked at about **254 MiB RSS** across the stress suite. These are fixture observations, not normal idle-app RAM, engine peaks or a long-duration energy benchmark. Functional tests, final CI, signing/publication and Homebrew installation status are tracked separately in the [verification record](../evidence/verification-1.9.0.json).

Manual VoiceOver, novice participants, physical logout/login, older macOS appearance, physical Intel hardware/engine installation and long-duration energy use remain untested. Login presentation uses isolated events/preferences. The system Reduce Motion setting was not changed; explicit policy overrides were tested. QA helpers and disabled fixtures are separate from final installed-package verification.

---

# Component, layout and motion audit — 2026-10-12

The final 1.7.0 source passes the user's stricter **≥9.5** component gate at **9.585/10** (rounded **9.6**). An independent agent inspected the native app views after the implementation agent's repairs. Every component is ≥9.0 and no checked control overlap or safety blocker remains. This is a scoped developer heuristic assessment; it does not establish functional perfection or replace novice-user research. The earlier 9.0 beginner audit below uses a different rubric.

| Component | Weight | Score |
| --- | --- | --- |
| Puzzle geometry and joins | 20% | 9.8 |
| Padding and spacing | 20% | 9.6 |
| Readability | 20% | 9.5 |
| Control alignment | 15% | 9.6 |
| Navigation and state | 10% | 9.5 |
| Converter, guide and Settings consistency | 10% | 9.6 |
| Compact and appearance behaviour | 5% | 9.1 |

The first detailed pass held alignment below the gate: Convert and Rename toolbars ended in different columns, and stretched Settings buttons separated symbols from their titles. The final pass aligns the fields and every trailing action control; Settings buttons retain their natural icon/title width. A shared puzzle geometry fixes the one-point seam mismatch. Tests compare connector points and control columns within **0.01 pt**, with **13 pt** clearance below the top notch, **14 pt** at the lower body and **20 pt** side insets. Essential explanations use larger semantic text; selected-rule foregrounds adapt to the system accent.

The reviewer inspected **four views × two sizes × two appearances** in actual CUA screenshots: converter, Folder Rules, Getting Started and Settings. Additional checks covered long mixed conditions, reachable compact Archive/Trash acknowledgements, Settings' last Service button, expanded Batch options, Activity draft retention and guide topic scroll reset. **Physical grip dragging now visibly reorders actions**, confirmed in accessibility state, and Move Down restores the original order. No user's rules, startup settings or files changed. Raw captures use current production AppKit view classes with isolated, disabled public fixtures; bitmap-cached renders are excluded. [Representative action layout](images/folder-actions.png), [compact original policy](images/compact-original-policy.png) and [guide](images/getting-started.png) show the final source. [Independent rubric and limits](../evidence/usability-1.7.0.json) records the checked tasks; [component proof](../evidence/ui-components-1.7.0.json) records geometry and motion scope.

Motion uses one **180 ms ease-in/ease-out** native transition across rule jumps, Builder/Activity, guidance, window presentation and Batch options. State updates immediately; interrupted scrolling cancels the obsolete transition. Structural edits from Activity return to Builder. Hidden views skip motion, Reduce Motion uses immediate updates, and no recurring idle animation timer is added. **399 native editor checks pass**, including a running `NSApplication` event-loop regression, a 25 ms presentation-opacity check and interrupted-scroll/Reduce Motion endpoints after 300 ms. [Editor evidence](../evidence/rule-editor-1.7.0.json) records the result. Actual navigation endpoints were checked; perceived smoothness and frame-time distributions have not been profiled, and the system Reduce Motion preference was not changed during this crawl.

The native glass controls/navigation and readable content follow [Apple's Liquid Glass adoption guidance](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass). Compact views intentionally scroll later instructions; that is why compact behaviour remains the lowest-scoring component. VoiceOver, novice participants, older macOS appearance, Intel hardware/engines and long-duration energy use remain outside this audit. Final installed-app and release checks are separate from the disabled fixture helper.

The unchanged event-driven automation suite passes **330 checks**. Its latest five-second fixture sample used **0.006523 CPU seconds**, a 1,000-small-file scan took **0.006274 seconds**, and the whole stress test peaked at about **255 MiB RSS**; these are not normal idle-app or conversion-engine peaks. [Automation evidence](../evidence/automation-1.7.0.json) describes that scope. Required final CI rebuilds and runs the native, engine, preservation, security, installer and release suites against the committed tree.

---

# Initial installation and usability crawl — 2026-10-12

Three coding agents independently reviewed runtime correctness, installation/distribution and first-use usability. The renewed usability assessment is **9.0/10** (weighted **9.035**), passing the scoped ≥9.0 threshold. It is a developer heuristic review, not a novice-user study or a claim of functional perfection.

| Dimension | Weight | Score |
| --- | --- | --- |
| Discovery and navigation | 25% | 9.2 |
| First manual conversion | 20% | 9.2 |
| Destinations and recovery | 20% | 9.0 |
| Folder automation comprehension | 20% | 9.0 |
| Finder and startup clarity | 10% | 8.7 |
| Layout and accessibility | 5% | 8.5 |

The crawl corrected stale Service names and THEN terminology, an order-dependent rename explanation, ambiguous selected-only queue review, Settings button accessibility labels and window/content minimum-size mismatches. The README now leads with installation and the three manual conversion stages; real current-interface screenshots use public fixtures and neutral demo paths. Detailed settings, rule safety, limits and recovery remain in the [usage guide](USAGE.md).

Actual native UI checks covered WAV→MP3 and PNG→WebP in one batch, unchanged original hashes, connected rule pieces, the action palette, section jumps, keyboard action ordering, matching previews, selectable read-only Details, preview invalidation and Settings labels. Screenshots use the current AppKit classes in an isolated helper; no user's rules or startup settings were changed. [Initial usability evidence](../evidence/usability-initial-1.7.0.json) records tasks and limits.

The runtime audit reproduced and fixed queue overflow, repeated existing-file starvation, settling-wait resets, early single-watcher lock release during cancellation and hidden skipped-arrival feedback. Paused saves now describe the actual watcher state. **330 automation checks and 310 editor checks pass**, including real filesystem events, cancellation/lock contention and source preservation. Guidance, interface, backend, 20 installer/removal and 28 release checks also pass. Installation now reuses the owned system/user Applications copy and rejects unowned, ambiguous or linked destinations; removal handles the same resolved app.

The universal native app contains verified arm64 and x86_64 slices. Developer ID signature, secure timestamp, Hardened Runtime, sealed source/architecture provenance, Apple acceptance, the stapled ticket and Gatekeeper assessment pass. Engines remain separately installed. [Artifact evidence](../evidence/releases/1.7.0.json) records the status.

The event-driven fixture used **0.00439 CPU seconds over five seconds** and scanned 1,000 small files in **0.00717 seconds**. The complete temporary stress suite peaked at about **257 MiB RSS**; this is not the normal idle app or conversion-engine peak. Physical dragging through the UI automation wrapper did not visibly reorder and remains unverified; native drop callbacks and Move Up/Down have separate passing tests. VoiceOver, novice participants, actual login activation, Intel hardware/engine operation, older macOS and long-duration energy use remain unchecked.

---

# Puzzle rule editor — earlier 1.7.0 candidate

The user rejected the earlier form-style editor. This audit treats that feedback as a new requirement; the previous beginner-guidance score does not establish that the rule editor is easy or pleasant to use.

The first actual puzzle candidate scored **8.61/10** against the revised weighted rubric. Matching/nonmatching previews, ALL/ANY and action ordering passed, but disconnected pieces, offscreen route guidance, large inline preview plans and implicit filename illustrations prevented a pass. The second iteration joins adjacent tabs/notches, provides persistent action controls and stage navigation, limits inline plans while retaining full selectable Details, and labels the assumed input in every illustration.

The editor shows the existing execution model: one arrival, an ALL/ANY decision, ordered conversion/rename blocks, one output folder, and an after-success original-file policy. A nonmatch tries later eligible saved rules; a conversion failure keeps the original and does not trigger a fallback. The canvas does not imply arbitrary graph wiring or loops.

Regression work includes actual native button/popup callbacks, active text editors, stale views and drag sessions, custom wait intervals, unknown values, action/condition limits, disabled-draft storage bounds, original preservation, eligibility, source-format examples and minimum-size layouts. Source audit found and repaired an existing-file queue feedback race, a stale table-row crash, lost filename condition text, incompatible default targets, impossible conversion chains and ALAC extension mismatches. Real-engine ALAC now publishes `.m4a` and retains the source.

The independent second review scores **9.04/10**, passing the scoped threshold with no confirmed blocking defect in the checked editor tasks:

| Dimension | Weight | Score |
|---|---:|---:|
| Execution and branch understanding | 25% | 9.1 |
| Editing and ordering | 20% | 9.0 |
| Preview and validation | 15% | 9.2 |
| State and original-file safety | 15% | 9.1 |
| Discovery | 10% | 9.2 |
| Accessibility and layout | 10% | 8.5 |
| Playful visual clarity | 5% | 9.0 |

Actual UI observation checked connected pieces, the persistent palette, four jumps, both preview branches, ALL/ANY, full selectable read-only Details and order-dependent filenames. The final native suites pass **310 editor checks and 312 automation checks**, including original-policy acknowledgement, all five jumps, light/dark layouts at the declared 900×620 minimum content size, stale callbacks and new/duplicate/reordered rule identity. [Editor evidence](../evidence/rule-editor-1.7.0.json) and [automation evidence](../evidence/automation-1.7.0.json) record the fixture results. Interface, guidance and 22 release verification tests also pass; a separate real-engine ALAC check confirmed the `.m4a` container and preserved source.

Passing requires ≥9.0 overall, ≥8.5 for execution/editing/safety, and no known blocking defect in the checked tasks. **Limits:** these are scoped developer assessments. Physical mouse dragging was not verified because the UI automation pointer wrapper failed before sending input; native drag/drop callbacks and session isolation were tested. VoiceOver, a novice usability study, older-system coverage and long-duration energy measurements remain unverified. A late Mac lock stopped additional pointer testing.

No conversion subprocess or polling animation was added to the idle editor. The event-driven fixture used 0.0081 CPU seconds during a five-second idle sample; a 1,000-file scan took 0.0053 seconds. The complete UI/history/long-preview stress suite peaked at about **260 MiB RSS**. A separate single idle snapshot of the open preview was about **154 MiB RSS / 0% CPU**; this is not a controlled energy benchmark. The native bundle is about **1.7 MiB**, roughly 44 KiB more than the preceding installed app, with no new runtime dependency.


---

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

The grader observed the guide, settings and rule-editor improvements, mixed-file recognition and disabled incompatible single-target context commands. The final installed Developer ID signed, Apple-notarized app also passed actual Add Files and WAV→MP3/PNG→WebP conversion through the native UI: both outputs appeared directly beside their sources with numbered collision names, completion showed two successes, and original/existing-target hashes stayed unchanged. The grader then observed the full rule-preview plan, reached its final “No files changed” line, selected text and confirmed it remained read-only. Editing invalidated the plan; Discard and removal of the test rule restored the empty rule table. These final visual tasks completed after macOS screen capture recovered. [Preview UI evidence](../evidence/preview-ui-1.6.0.json) records the independent checks.

Regression checks cover the real native AppKit hierarchy, first-use persistence and noninterruption, compact guide bounds, all format advice, mixed/unsupported context selections, Finder presets that require an explicit compatible choice, stale-preview invalidation, selectable full plans and Discard restoring Archive acknowledgement. **305 automation assertions pass**, including real filesystem events and bundled recognition/conversion. [Automation evidence](../evidence/automation-1.6.0.json) records a five-second idle fixture sample and a 1,000-file scan. [Controller evidence](../evidence/controller-1.6.0.json) records 33 programmatic controller/real-engine assertions and the final installed native UI conversion. The extracted public source with the existing separate runtime passes all 62 format round trips, 14 preservation checks, 10 edge checks, 18 security tests and 13 batch tests.

A final diagnostic review reproduced a nonfatal macOS 27 IconServices fault when Finder registration converted the 128px PNG into a document icon. Registration now uses the existing canonical ICNS family; the Settings artwork remains PNG. The isolated canonical-icon case and revised backend test produced no fault messages/reports, and native tests verify small, large and Retina icon blocks, unchanged Quick Action artwork, repair/idempotence and preservation of unrelated workflows.

Automatic Finder setup also checks the actual system/user Applications roots and their subfolders. An Xcode archive's `Products/Applications` folder or a download folder with the same name no longer repoints owned workflows. Location-boundary regressions pass; explicit manual setup remains available for other app locations.

Manual VoiceOver, older macOS, actual login activation, long-duration energy use and conversion-engine peak memory remain unverified. Native controls and system animation are retained; no additional custom animation or idle engine process was introduced.

A single idle 1.6 candidate snapshot with two queued files measured about **159 MiB RSS and 0.0% CPU**; an empty installed notarized-app snapshot measured about **110 MiB RSS and 0.0% CPU**. The automation fixture used 0.0053 CPU seconds over five seconds and scanned 1,000 small files in 0.0068 seconds. These short local observations are not engine-peak or long-duration energy measurements. The installed notarized native app is about 1.6 MiB on disk and uses the existing external runtime. The retained local bundled-engine development app remains about 1.9 GiB and is dominated by unchanged conversion engines/data.

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

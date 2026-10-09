import AppKit

final class FixtureAutomationEngine: AutomationEngine {
    var fail = false
    var onConvert: (() throws -> Void)?
    var count = 0
    func inspect(_ url: URL, cancellation: AutomationCancellation) throws -> RecognizedFile {
        try cancellation.check()
        let format = url.pathExtension.lowercased()
        guard let group = FormatCatalog.groups.first(where: { $0.formats.contains(format) }) else { throw AutomationIssue("Unsupported fixture") }
        return .init(url: url, format: format, category: group.id, targets: group.formats + (group.id == "video" ? FormatCatalog.groups[0].formats : []))
    }
    func convert(_ file: RecognizedFile, to format: String, staging: URL, cancellation: AutomationCancellation) throws -> URL {
        count += 1; try cancellation.check(); try onConvert?()
        if fail { throw AutomationIssue("Fixture conversion failure") }
        guard file.targets.contains(format) else { throw AutomationIssue("Incompatible fixture target") }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let output = staging.appendingPathComponent("result." + format)
        try Data(contentsOf: file.url).write(to: output)
        return output
    }
}
final class ControlledInspectionEngine: AutomationEngine {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didStart = false
    let beforeReturn: () throws -> Void
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    init(beforeReturn: @escaping () throws -> Void = {}) { self.beforeReturn = beforeReturn }
    func inspect(_ url: URL, cancellation: AutomationCancellation) throws -> RecognizedFile {
        lock.lock(); didStart = true; lock.unlock()
        guard release.wait(timeout: .now() + 10) == .success else { throw AutomationIssue("Test fixture timed out") }
        try cancellation.check(); try beforeReturn()
        return try FixtureAutomationEngine().inspect(url, cancellation: cancellation)
    }
    func convert(_ file: RecognizedFile, to format: String, staging: URL, cancellation: AutomationCancellation) throws -> URL { throw AutomationIssue("Read-only tests must never convert") }
}
@main
struct AutomationTests {
    static var checks = 0
    static func fail(_ label: String) -> Never { FileHandle.standardError.write(Data(("FAIL: " + label + "\n").utf8)); exit(1) }
    static func check(_ value: @autoclosure () throws -> Bool, _ label: String) {
        do { if try !value() { fail(label) } } catch { fail(label + ": " + error.localizedDescription) }
        checks += 1
    }
    static func rejects(_ label: String, _ operation: () throws -> Void) { do { try operation(); fail(label + " (operation did not reject)") } catch { checks += 1 } }
    static func spin(_ until: () -> Bool, timeout: TimeInterval = 12) {
        let deadline = Date().addingTimeInterval(timeout)
        while !until(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
        check(until(), "Timed out waiting for native watcher")
    }
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("UltraConvert automation \(UUID())")
        defer { try? fm.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox"), outbox = root.appendingPathComponent("Out"), archive = root.appendingPathComponent("Archive")
        for directory in [inbox, outbox, archive] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        var rule = WatchRule(); rule.name = "Audio flow"; rule.inputFolder = inbox.path; rule.destination = outbox.path; rule.settleSeconds = 2; rule.conditions = [.init(field: .category, value: "audio")]; rule.steps = [.init(kind: .convert, value: "wav"), .init(kind: .rename, value: "{name}-{format}")]
        let roots = [inbox.path]
        try rule.validate(roots: roots)
        check(FormatCatalog.all.count == 62, "Full requested format catalog")
        for group in FormatCatalog.groups { for format in group.formats {
            let file = RecognizedFile(url: inbox.appendingPathComponent("Sample." + format), format: format, category: group.id, targets: group.formats)
            check(RuleCondition(field: .format, value: format.uppercased()).matches(file), "Detected format condition")
            check(RuleCondition(field: .category, value: group.id).matches(file), "Category condition")
        } }
        let source = inbox.appendingPathComponent("Song.mp3"); try Data("ORIGINAL".utf8).write(to: source)
        let file = RecognizedFile(url: source, format: "mp3", category: "audio", targets: ["mp3", "wav"])
        check(RuleCondition(field: .format, value: "jpeg").matches(.init(url: source, format: "jpg", category: "image", targets: [])), "JPEG alias matches detected format")
        check(RuleCondition(field: .format, value: "yml").matches(.init(url: source, format: "yaml", category: "config", targets: [])), "YAML alias matches detected format")
        for condition in [RuleCondition(field: .nameContains, value: "ONG"), .init(field: .namePrefix, value: "SON"), .init(field: .nameSuffix, value: ".MP3")] { check(condition.matches(file), "Case-insensitive names") }
        var combined = rule; combined.conditions = [.init(field: .format, value: "mp3"), .init(field: .nameContains, value: "missing")]
        check(!combined.matches(file), "All conditions"); combined.matchAll = false; check(combined.matches(file), "Any condition")
        for bad in ["../escape", "/absolute", "..", ".hidden", "unknown-{token}", "a/b", "a\\b", "a:b", "a\nname", String(repeating: "x", count: 181)] { rejects("Unsafe rename", { _ = try RuleNaming.render(bad, name: "Song", format: "wav") }) }
        check(try RuleNaming.render("{name}-{format}-{date}", name: "Song", format: "wav", date: Date(timeIntervalSince1970: 0)) == "Song-wav-1970-01-01", "Safe tokens")
        for destination in [inbox.path, inbox.appendingPathComponent("nested").path] { var bad = rule; bad.destination = destination; rejects("Output loop", { try bad.validate(roots: roots) }) }
        if fm.fileExists(atPath: inbox.path.uppercased()) { check(RulePaths.contains(root: inbox.path, path: inbox.path.uppercased()), "Directory identity catches case aliases on this test volume") }
        let secondInbox = root.appendingPathComponent("Second"); try fm.createDirectory(at: secondInbox, withIntermediateDirectories: false)
        var cross = rule; cross.destination = secondInbox.path; rejects("Cross-rule loop", { try cross.validate(roots: roots + [secondInbox.path]) })
        let link = root.appendingPathComponent("linked-out"); try fm.createSymbolicLink(at: link, withDestinationURL: inbox)
        var linked = rule; linked.destination = link.path; rejects("Symlink output loop", { try linked.validate(roots: roots) })
        var bad = rule; bad.settleSeconds = .nan; rejects("Finite settle interval", { try bad.validate(roots: roots) })
        bad = rule; bad.steps[0].value = "evil"; rejects("Unknown conversion", { try bad.validate(roots: roots) })
        bad = rule; bad.originalPolicy = .trash; rejects("Removal needs acknowledgement", { try bad.validate(roots: roots) })
        let engine = FixtureAutomationEngine(), pipeline = AutomationPipeline(engine: engine, scratch: root.appendingPathComponent("Scratch"))
        let preview = try pipeline.preview(source, rule: rule, cancellation: AutomationCancellation())
        check(preview.contains("No files changed") && engine.count == 0, "Read-only preview")
        check(preview.contains("Detected: MP3 (Audio)") && preview.contains("After success: Keep the original in its inbox."), "Preview explains detected category and Keep original")
        let longArchive = archive.appendingPathComponent(String(repeating: "A clear archive folder ", count: 8)).appendingPathComponent("Original files remain recoverable")
        try fm.createDirectory(at: longArchive, withIntermediateDirectories: true)
        let originalBytes = try Data(contentsOf: source), inboxBefore = try fm.contentsOfDirectory(atPath: inbox.path).sorted(), outboxBefore = try fm.contentsOfDirectory(atPath: outbox.path).sorted(), archiveBefore = try fm.contentsOfDirectory(atPath: archive.path).sorted()
        var longArchivePlan = ""
        for originalPolicy in OriginalPolicy.allCases {
            var previewRule = rule; previewRule.originalPolicy = originalPolicy; previewRule.archiveFolder = longArchive.path; previewRule.acknowledgedRemoval = true
            let plan = try pipeline.preview(source, rule: previewRule, cancellation: AutomationCancellation())
            check(plan.contains("Source: " + source.path) && plan.contains("Save in: " + outbox.path) && plan.contains("No files changed"), "Every preview keeps full source/destination paths and read-only assurance")
            if originalPolicy == .archive { longArchivePlan = plan; check(plan.contains("After success: Move the original to archive: " + longArchive.path), "Archive preview names the full archive destination") }
            if originalPolicy == .trash { check(plan.contains("After success: Send the original to Trash (recoverable in Finder)."), "Trash preview describes the original-file consequence") }
        }
        check(try Data(contentsOf: source) == originalBytes && fm.contentsOfDirectory(atPath: inbox.path).sorted() == inboxBefore && fm.contentsOfDirectory(atPath: outbox.path).sorted() == outboxBefore && fm.contentsOfDirectory(atPath: archive.path).sorted() == archiveBefore && engine.count == 0 && !fm.fileExists(atPath: pipeline.scratch.path), "Keep/Archive/Trash previews create no outputs, staging, archive moves or conversions")
        let first = try pipeline.run(source, rule: rule, roots: roots, cancellation: AutomationCancellation())
        check(first.output?.lastPathComponent == "Song-wav.wav", "Direct named output")
        check(try Data(contentsOf: source) == Data("ORIGINAL".utf8), "Original preserved")
        let second = try pipeline.run(source, rule: rule, roots: roots, cancellation: AutomationCancellation())
        check(second.output?.lastPathComponent == "Song-wav (1).wav", "Collision safety")
        check(try Data(contentsOf: first.output!) == Data("ORIGINAL".utf8), "Existing output preserved")
        engine.fail = true; rejects("Conversion failure", { _ = try pipeline.run(source, rule: rule, roots: roots, cancellation: AutomationCancellation()) }); check(fm.fileExists(atPath: source.path), "Failed original kept"); engine.fail = false
        let token = AutomationCancellation(); engine.onConvert = { token.cancel() }; rejects("Cancellation", { _ = try pipeline.run(source, rule: rule, roots: roots, cancellation: token) }); check(fm.fileExists(atPath: source.path), "Cancelled original kept"); engine.onConvert = nil
        engine.onConvert = { try Data("CHANGED".utf8).write(to: source) }; rejects("Changed source", { _ = try pipeline.run(source, rule: rule, roots: roots, cancellation: AutomationCancellation()) }); check(try Data(contentsOf: source) == Data("CHANGED".utf8), "Changed source kept"); engine.onConvert = nil
        var archived = rule; archived.originalPolicy = .archive; archived.archiveFolder = archive.path; archived.acknowledgedRemoval = true
        _ = try pipeline.run(source, rule: archived, roots: roots, cancellation: AutomationCancellation())
        check(!fm.fileExists(atPath: source.path) && fm.fileExists(atPath: archive.appendingPathComponent(source.lastPathComponent).path), "Archive after success")
        try Data("TRASH FIXTURE".utf8).write(to: source)
        var trashed = rule; trashed.originalPolicy = .trash; trashed.acknowledgedRemoval = true
        let trashRoot = root.appendingPathComponent("Fixture Trash"); try fm.createDirectory(at: trashRoot, withIntermediateDirectories: false)
        let trashPipeline = AutomationPipeline(engine: engine, scratch: root.appendingPathComponent("Scratch"), trash: { try fm.moveItem(at: $0, to: trashRoot.appendingPathComponent($0.lastPathComponent)) })
        _ = try trashPipeline.run(source, rule: trashed, roots: roots, cancellation: AutomationCancellation())
        check(!fm.fileExists(atPath: source.path) && fm.fileExists(atPath: trashRoot.appendingPathComponent(source.lastPathComponent).path), "Trash only after success")
        try Data("RESTORE FIXTURE".utf8).write(to: source)
        let failingTrash = AutomationPipeline(engine: engine, scratch: root.appendingPathComponent("Scratch"), trash: { _ in throw AutomationIssue("Trash unavailable") })
        let restored = try failingTrash.run(source, rule: trashed, roots: roots, cancellation: AutomationCancellation())
        check(restored.output != nil && restored.message.contains("restored") && fm.fileExists(atPath: source.path), "Failed Trash restores original atomically")
        let racingTrash = AutomationPipeline(engine: engine, scratch: root.appendingPathComponent("Scratch"), trash: { _ in try Data("NEW SOURCE".utf8).write(to: source); throw AutomationIssue("Trash unavailable") })
        let recovery = try racingTrash.run(source, rule: trashed, roots: roots, cancellation: AutomationCancellation())
        check(try recovery.message.contains("preserved at") && Data(contentsOf: source) == Data("NEW SOURCE".utf8), "Source replacement is never overwritten during restoration")
        let heldDirectories = try fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".ultraconvert-original-") }
        check(try heldDirectories.count == 1 && Data(contentsOf: heldDirectories[0].appendingPathComponent("Song.mp3")) == Data("RESTORE FIXTURE".utf8), "Recoverable quarantined original retained")
        let doc = inbox.appendingPathComponent("Book.docx"); try Data("doc".utf8).write(to: doc)
        var docRule = trashed; docRule.conditions = [.init(field: .category, value: "document")]; docRule.steps = [.init(kind: .convert, value: "md")]
        rejects("Companion original protected", { _ = try trashPipeline.run(doc, rule: docRule, roots: roots, cancellation: AutomationCancellation()) }); check(fm.fileExists(atPath: doc.path), "Document source retained")
        rejects("Preview refuses document source removal", { _ = try pipeline.preview(doc, rule: docRule, cancellation: AutomationCancellation()) })
        var renameDocument = docRule; renameDocument.originalPolicy = .keep; renameDocument.steps = [.init(kind: .rename, value: "Copy-{name}")]
        rejects("Preview refuses document routing without companion preservation", { _ = try pipeline.preview(doc, rule: renameDocument, cancellation: AutomationCancellation()) })
        let sourceLink = inbox.appendingPathComponent("linked.mp3"); try fm.createSymbolicLink(at: sourceLink, withDestinationURL: doc)
        rejects("Input symlink", { _ = try FileStamp.read(sourceLink) })
        rejects("Preview refuses linked sources", { _ = try pipeline.preview(sourceLink, rule: rule, cancellation: AutomationCancellation()) })
        let hardLink = inbox.appendingPathComponent("hard.mp3"); try fm.linkItem(at: doc, to: hardLink); rejects("Input hard link", { _ = try FileStamp.read(hardLink) }); rejects("Preview refuses hard-linked sources", { _ = try pipeline.preview(hardLink, rule: rule, cancellation: AutomationCancellation()) }); try fm.removeItem(at: hardLink)
        let hidden = inbox.appendingPathComponent(".hidden.mp3"), partial = inbox.appendingPathComponent("unfinished.part")
        for item in [hidden, partial] { try Data("fixture".utf8).write(to: item); check(!RulePaths.eligible(item), "Temporary/hidden ignored") }
        let support = root.appendingPathComponent("Support"), store = try AutomationStore(support: support)
        try store.save([rule]); check(try store.load() == [rule], "Rule persistence")
        try Data("broken".utf8).write(to: store.url("rules.json")); rejects("Corrupt rule store", { _ = try store.load() }); try store.save([rule])
        rejects("Duplicate IDs", { try store.save([rule, rule]) })
        let persisted = try JSONEncoder().encode(AutomationDocument(schema: 99, rules: [rule])); try store.write(persisted, "rules.json"); rejects("Schema rejected", { _ = try store.load() }); try store.save([rule])
        let runtime = try FolderAutomation(support: support, engine: { engine })
        rule.enabled = true; try runtime.save([rule])
        check(!runtime.canRunExisting && runtime.runExisting() == nil && runtime.pendingCount == 0, "Run Existing explicitly rejects the initial baseline scan without claiming or queueing work")
        spin({ runtime.canRunExisting })
        check(runtime.pendingCount == 0 && engine.count > 0, "Existing baseline ignored")
        var fallback = rule; fallback.id = UUID(); fallback.name = "Lower-priority fallback"; fallback.steps = [.init(kind: .convert, value: "flac")]
        try runtime.save([rule, fallback]); spin({ runtime.canRunExisting })
        let count = engine.count
        let arrival = inbox.appendingPathComponent("New.mp3"); try Data("ARRIVAL".utf8).write(to: arrival)
        spin({ runtime.activities.contains { $0.file == "New.mp3" && $0.output != nil } })
        check(engine.count == count + 1 && fm.fileExists(atPath: outbox.appendingPathComponent("New-wav.wav").path), "FSEvents arrival processed once")
        runtime.requestScan(); spin({ runtime.pendingCount == 0 && !runtime.running }); check(engine.count == count + 1, "No unchanged replay")
        let secondRuntime = try FolderAutomation(support: support, engine: { engine }); secondRuntime.configure(); check(secondRuntime.status.contains("already open"), "Single watcher lock")
        runtime.setPaused(true); check(!runtime.canRunExisting && runtime.runExisting() == nil, "Paused watchers explicitly reject Run Existing")
        let paused = inbox.appendingPathComponent("Paused.mp3"); try Data("paused".utf8).write(to: paused)
        let pausedRestart = try FolderAutomation(support: support, engine: { engine }); check(pausedRestart.paused, "Pause survives app restart")
        runtime.setPaused(false)
        check(!runtime.canRunExisting && runtime.runExisting() == nil && runtime.pendingCount == 0, "Resume rejects Run Existing until its replacement baseline is ready")
        spin({ runtime.canRunExisting }); check(runtime.pendingCount == 0, "Resume establishes new baseline")
        var manual = true; runtime.manualBusy = { manual }
        let blocked = inbox.appendingPathComponent("Manual.mp3"); try Data("manual".utf8).write(to: blocked)
        spin({ runtime.pendingCount > 0 }); check(!runtime.running, "Manual batch priority")
        manual = false; runtime.manualBatchFinished(); spin({ runtime.activities.contains { $0.file == "Manual.mp3" && $0.output != nil } })
        // A file that continues changing must wait for a new stable interval.
        let growing = inbox.appendingPathComponent("Growing.mp3"); try Data("first".utf8).write(to: growing); spin({ runtime.pendingCount > 0 }); try Data("second and longer".utf8).write(to: growing)
        spin({ runtime.activities.contains { $0.file == "Growing.mp3" && $0.output != nil } }); check(try Data(contentsOf: outbox.appendingPathComponent("Growing-wav.wav")) == Data("second and longer".utf8), "Settled content used")
        let movedInbox = root.appendingPathComponent("Moved Inbox")
        try fm.moveItem(at: inbox, to: movedInbox); spin({ runtime.paused }); check(runtime.paused && !runtime.status.hasPrefix("Watching"), "Moved roots pause watching")
        try fm.moveItem(at: movedInbox, to: inbox); runtime.setPaused(false); spin({ runtime.canRunExisting })
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let idleStart = Date(), idleCount = engine.count
        while Date().timeIntervalSince(idleStart) < 5 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        var after = rusage(); getrusage(RUSAGE_SELF, &after)
        let idleCPU = Double(after.ru_utime.tv_sec - before.ru_utime.tv_sec + after.ru_stime.tv_sec - before.ru_stime.tv_sec) + Double(after.ru_utime.tv_usec - before.ru_utime.tv_usec + after.ru_stime.tv_usec - before.ru_stime.tv_usec) / 1_000_000
        check(engine.count == idleCount && runtime.pendingCount == 0 && !runtime.running, "No engine or pending timer while idle")
        // Bulk scan is bounded and includes recursive files, while packages and
        // symlink directories never become a route into another tree.
        let bulk = root.appendingPathComponent("Bulk"); try fm.createDirectory(at: bulk, withIntermediateDirectories: false)
        for index in 0..<1000 { try Data("fixture".utf8).write(to: bulk.appendingPathComponent("file-\(index).mp3")) }
        var bulkRule = rule; bulkRule.inputFolder = bulk.path
        let scanStart = Date(), bulkScan = WatchScan.run([bulkRule]), scanSeconds = Date().timeIntervalSince(scanStart)
        check(bulkScan.files.count == 1000 && bulkScan.issue == nil, "Bulk scan")
        check(WatchScan.run([bulkRule, bulkRule]).files.count == 1000, "Shared roots scan once")
        let nested = bulk.appendingPathComponent("Nested"); try fm.createDirectory(at: nested, withIntermediateDirectories: false); try Data("nested".utf8).write(to: nested.appendingPathComponent("inside.mp3"))
        try fm.createSymbolicLink(at: bulk.appendingPathComponent("Outside"), withDestinationURL: outbox)
        bulkRule.recursive = true; check(WatchScan.run([bulkRule]).files.count == 1001, "Recursive scan excludes symlink trees")
        check(WatchScan.run([bulkRule], excluding: [nested]).files.count == 1000, "Internal staging storage excluded")
        let rulesWindow = FolderRulesWindow(runtime: runtime)
        rulesWindow.message.stringValue = String(repeating: "A detailed diagnostic must keep the controls reachable. ", count: 100)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            rulesWindow.window!.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 1040, height: 750), NSSize(width: 900, height: 620)] {
                rulesWindow.window!.setContentSize(size); rulesWindow.window!.contentView!.layoutSubtreeIfNeeded()
                for view in [rulesWindow.save, rulesWindow.test, rulesWindow.existing, rulesWindow.viewPreviewDetails, rulesWindow.setupGuide, rulesWindow.stateLabel, rulesWindow.message] {
                    let frame = view.convert(view.bounds, to: rulesWindow.window!.contentView)
                    check(frame.minX >= 0 && frame.maxX <= size.width && frame.minY >= 0 && frame.maxY <= size.height, "Rule controls visible in light/dark at minimum size")
                }
            }
        }
        check(rulesWindow.message.frame.height <= 70 && rulesWindow.message.toolTip == rulesWindow.message.stringValue, "Long diagnostics stay bounded and retain their full tooltip")
        check(rulesWindow.conditions.count == rule.conditions.count && rulesWindow.steps.count == rule.steps.count, "Modular editor mirrors model")
        check(rulesWindow.setupGuide.stringValue.contains("Preview a file; nothing changes") && rulesWindow.setupGuide.stringValue.contains("Enable and Save Rule"), "Setup checklist remains visible after choosing a rule")
        check(rulesWindow.matching.toolTip?.contains("ALL requires every condition") == true && rulesWindow.settle.toolTip?.contains("wait starts over") == true, "Matching and stable-file wait controls explain their meaning")
        check(!rulesWindow.viewPreviewDetails.isEnabled && rulesWindow.previewDetails == nil, "Preview details start unavailable")
        let longDetails = RulePreviewDetails(text: String(repeating: longArchivePlan + "\n\n", count: 20))
        longDetails.window!.setContentSize(NSSize(width: 540, height: 320)); longDetails.window!.contentView!.layoutSubtreeIfNeeded()
        longDetails.text.layoutManager?.ensureLayout(for: longDetails.text.textContainer!)
        check(!longDetails.text.isEditable && longDetails.text.isSelectable && longDetails.scroll.hasVerticalScroller && longDetails.text.string.contains(longArchive.path), "Long preview details retain full paths in a selectable read-only scrolling view")
        check(longDetails.text.layoutManager!.usedRect(for: longDetails.text.textContainer!).height > longDetails.scroll.contentView.bounds.height, "Long plans can scroll beyond the visible viewport")
        check(longDetails.text.frame.height >= longDetails.text.layoutManager!.usedRect(for: longDetails.text.textContainer!).height, "The scrolling document reaches the entire long preview instead of clipping its tail")
        let detailsButtonFrame = longDetails.done.convert(longDetails.done.bounds, to: longDetails.window!.contentView)
        check(detailsButtonFrame.minY >= 0 && detailsButtonFrame.maxY <= 320 && detailsButtonFrame.maxX <= 540, "Preview details remain closable at minimum size")
        let fallbackCard = RuleBlock(content: NSTextField(labelWithString: "Accessible fallback"), allowGlass: false)
        check(!fallbackCard.usesGlass, "Reduce Transparency fallback has no glass or accent stripes")
        let nativeCard = RuleBlock(content: NSTextField(labelWithString: "Native glass"))
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { check(nativeCard.usesGlass, "Native macOS glass API") }
        #endif
        var pickerCommitted = false
        let picker = FormatPicker(count: 3, choose: { _ in pickerCommitted = true }); picker.category.selectItem(at: 5); picker.refreshFormats(); check(picker.format.numberOfItems == 5, "Grouped Finder picker")
        picker.window!.contentView!.layoutSubtreeIfNeeded()
        for button in [picker.cancel, picker.review] {
            let frame = button.convert(button.bounds, to: picker.window!.contentView)
            check(frame.minX >= 0 && frame.maxX <= 560 && frame.minY >= 0 && frame.maxY <= 265, "Finder chooser actions stay inside their window")
        }
        picker.window!.orderFront(nil)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: picker.window!.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        check(picker.window!.performKeyEquivalent(with: escape) && !picker.window!.isVisible && !pickerCommitted, "Escape closes the format chooser without committing a batch")
        let menu = FormatCatalog.menu(target: NSObject(), action: #selector(NSApplication.terminate(_:))); check(menu.items.count == 6 && menu.items.reduce(0) { $0 + ($1.submenu?.items.count ?? 0) } == 62, "Native category submenus")
        rulesWindow.refreshActivity()
        check(rulesWindow.activityTable.numberOfRows == runtime.activities.count, "Virtualized history retains all outcomes")
        check(rulesWindow.numberOfRows(in: rulesWindow.activityTable) == runtime.activities.count, "Activity uses native table data source")
        let largeHistory = AutomationActivity(rule: "Test", file: "Example.mp3", message: String(repeating: "detailed outcome ", count: 100), output: nil)
        runtime.activities = Array(repeating: largeHistory, count: 200); rulesWindow.refreshActivity()
        check(rulesWindow.activityTable.numberOfRows == 200, "History table stays bounded at 200 records")
        let activityCell = ActivityCell(frame: NSRect(x: 0, y: 0, width: 600, height: 90))
        activityCell.configure(AutomationActivity(rule: "Audio → MP3", file: "Arrival.wav", message: "Finished · original kept", output: outbox.path))
        activityCell.layoutSubtreeIfNeeded()
        check(activityCell.details.frame.width > 400 && activityCell.reveal.frame.maxX == 588, "Activity text fills the row with a trailing Reveal control")
        let detailFrame = activityCell.details.convert(activityCell.details.bounds, to: activityCell)
        check(detailFrame.minY >= 0 && detailFrame.maxY <= 90 && activityCell.details.stringValue.contains("Finished"), "Activity outcome stays visible within the row")
        activityCell.configure(nil)
        check(activityCell.reveal.isHidden && activityCell.details.toolTip == activityCell.details.stringValue && activityCell.accessibilityLabel() == "No files processed yet", "Reused empty Activity rows clear old output details")
        runtime.setPaused(true)
        rulesWindow.refreshStatus(); check(!rulesWindow.existing.isEnabled, "Paused rules cannot run existing files from the editor")
        runtime.setPaused(false); rulesWindow.refreshStatus()
        check(!rulesWindow.existing.isEnabled && rulesWindow.existing.toolTip?.contains("still scanning") == true, "Existing-file UI stays disabled while resume establishes its baseline")
        spin({ runtime.canRunExisting }); rulesWindow.refreshStatus(); check(rulesWindow.existing.isEnabled, "Saved enabled rules can run existing files when watching resumes")
        let enabledSavedRules = runtime.rules
        try runtime.save(enabledSavedRules.map { var value = $0; value.enabled = false; return value })
        rulesWindow.draft = runtime.rules.first!; rulesWindow.rebuildEditor(); rulesWindow.refreshStatus()
        check(!rulesWindow.existing.isEnabled && runtime.enabledRules.isEmpty, "Saved disabled drafts cannot run existing files")
        rulesWindow.enabled.state = .on; rulesWindow.editorControlChanged(rulesWindow.enabled); rulesWindow.refreshStatus()
        check(!rulesWindow.existing.isEnabled && rulesWindow.editingStatus.stringValue.contains("Unsaved changes"), "An unsaved enable edit does not enable existing-file execution")
        rulesWindow.runExisting(); check(runtime.pendingCount == 0 && rulesWindow.message.stringValue.contains("Enable and save"), "Existing-file handler also rejects unsaved enabling without queueing work")
        try runtime.save(enabledSavedRules); spin({ runtime.canRunExisting }); runtime.setPaused(true)
        rulesWindow.draft = runtime.rules.first!; rulesWindow.rebuildEditor(); rulesWindow.refreshStatus()
        let savedDraft = runtime.rules.first!
        rulesWindow.name.stringValue = "Unsaved edit"
        check(!rulesWindow.resolveUnsavedChanges(.alertSecondButtonReturn) && rulesWindow.name.stringValue == "Unsaved edit", "Keep Editing preserves unsaved controls")
        check(rulesWindow.resolveUnsavedChanges(.alertThirdButtonReturn) && rulesWindow.draft == savedDraft && rulesWindow.name.stringValue == savedDraft.name, "Discard restores the saved rule and controls")
        rulesWindow.window!.makeKeyAndOrderFront(nil); rulesWindow.window!.makeFirstResponder(rulesWindow.name)
        guard let liveEditor = rulesWindow.name.currentEditor() else { preconditionFailure("Rule name must support native text editing") }
        liveEditor.string = "Live field-editor input"; rulesWindow.gather()
        check(rulesWindow.draft.name == "Live field-editor input", "Unsaved-change checks include active field-editor text")
        _ = rulesWindow.resolveUnsavedChanges(.alertThirdButtonReturn)
        check(rulesWindow.name.currentEditor() == nil && rulesWindow.name.stringValue == savedDraft.name, "Discard ends live text editing before restoring saved controls")
        rulesWindow.draft.destination = inbox.path; rulesWindow.rebuildEditor()
        check(!rulesWindow.resolveUnsavedChanges(.alertFirstButtonReturn) && runtime.rules.first == savedDraft, "Invalid enabled-rule saves block navigation without changing saved data")
        _ = rulesWindow.resolveUnsavedChanges(.alertThirdButtonReturn)
        rulesWindow.name.stringValue = "Saved from close prompt"
        check(rulesWindow.resolveUnsavedChanges(.alertFirstButtonReturn) && runtime.rules.first?.name == "Saved from close prompt", "Save Changes commits before navigation")
        rulesWindow.draft.originalPolicy = .archive; rulesWindow.draft.archiveFolder = longArchive.path; rulesWindow.draft.acknowledgedRemoval = true; rulesWindow.rebuildEditor(); rulesWindow.gather()
        runtime.engine = { engine }; let previewConversions = engine.count
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ rulesWindow.previewWorkCount == 0 })
        check(rulesWindow.viewPreviewDetails.isEnabled && rulesWindow.previewDetails?.contains(longArchive.path) == true && engine.count == previewConversions && fm.fileExists(atPath: source.path), "Successful preview enables full details without converting or archiving")
        rulesWindow.showPreviewDetails()
        let shownDetails = rulesWindow.previewDetailsWindow!
        check(shownDetails.window!.isVisible && shownDetails.text.string == rulesWindow.previewDetails && !shownDetails.text.isEditable, "Details action opens exactly the current read-only plan")
        rulesWindow.name.stringValue = "Changed after preview"; rulesWindow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: rulesWindow.name))
        check(rulesWindow.previewDetails == nil && !rulesWindow.viewPreviewDetails.isEnabled && !shownDetails.window!.isVisible, "Editing immediately invalidates and closes displayed preview details")
        _ = rulesWindow.resolveUnsavedChanges(.alertThirdButtonReturn)
        rulesWindow.gather()
        check(rulesWindow.draft == runtime.rules.first! && rulesWindow.acknowledge.state == .off, "Discard restores hidden original-action acknowledgement instead of creating phantom edits")
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ rulesWindow.previewWorkCount == 0 })
        let rulesBeforeNewDraft = runtime.rules
        rulesWindow.newRule(template: 1)
        check(rulesWindow.previewDetails == nil && !rulesWindow.viewPreviewDetails.isEnabled && !rulesWindow.draft.enabled && rulesWindow.selectedID == runtime.rules.last?.id && rulesWindow.draft.id == runtime.rules.last?.id,
              "New rules clear old preview details and remain disabled drafts; selectedNew=\(rulesWindow.selectedID == runtime.rules.last?.id), enabled=\(rulesWindow.draft.enabled), details=\(rulesWindow.previewDetails != nil), count=\(runtime.rules.count), result=\(rulesWindow.message.stringValue)")
        try runtime.save(rulesBeforeNewDraft); rulesWindow.selectedID = rulesBeforeNewDraft.first!.id; rulesWindow.draft = rulesBeforeNewDraft.first!; rulesWindow.rebuildEditor(); rulesWindow.reloadList()
        let delayed = ControlledInspectionEngine(); runtime.engine = { delayed }; rulesWindow.gather()
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ delayed.started })
        check(rulesWindow.previewRunning && !rulesWindow.test.isEnabled && !rulesWindow.cancelTest.isHidden && !rulesWindow.viewPreviewDetails.isEnabled, "Read-only previews expose cancellation and disable repeated starts and old details")
        rulesWindow.window!.setContentSize(NSSize(width: 900, height: 620)); rulesWindow.window!.contentView!.layoutSubtreeIfNeeded()
        let cancelFrame = rulesWindow.cancelTest.convert(rulesWindow.cancelTest.bounds, to: rulesWindow.window!.contentView)
        check(cancelFrame.minX >= 0 && cancelFrame.maxX <= 900 && cancelFrame.minY >= 0 && cancelFrame.maxY <= 620, "Cancel Test remains reachable at minimum window size")
        rulesWindow.name.stringValue = "Edited during test"; delayed.release.signal(); spin({ rulesWindow.previewWorkCount == 0 })
        check(rulesWindow.message.stringValue.contains("changed during its preview") && rulesWindow.test.isEnabled && !rulesWindow.viewPreviewDetails.isEnabled, "A late plan cannot describe edited rule controls or enable stale details")
        _ = rulesWindow.resolveUnsavedChanges(.alertThirdButtonReturn)
        let cancelledPreview = ControlledInspectionEngine(); runtime.engine = { cancelledPreview }; rulesWindow.gather()
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ cancelledPreview.started }); rulesWindow.cancelTest.invoke()
        check(!rulesWindow.previewRunning && !rulesWindow.test.isEnabled && !rulesWindow.viewPreviewDetails.isEnabled && rulesWindow.previewDetails == nil, "Cancelled previews stay serialized and clear details until their work finishes")
        cancelledPreview.release.signal(); spin({ rulesWindow.previewWorkCount == 0 })
        check(rulesWindow.message.stringValue == "Preview cancelled. No files changed." && rulesWindow.test.isEnabled && !rulesWindow.viewPreviewDetails.isEnabled, "Cancelled preview completion does not overwrite current feedback or restore stale details")
        let switchedPreview = ControlledInspectionEngine(); runtime.engine = { switchedPreview }; rulesWindow.gather()
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ switchedPreview.started })
        rulesWindow.selectedID = fallback.id; rulesWindow.draft = runtime.rules.first { $0.id == fallback.id }!; rulesWindow.rebuildEditor(); rulesWindow.message.stringValue = "Current rule feedback"
        switchedPreview.release.signal(); spin({ rulesWindow.previewWorkCount == 0 })
        check(rulesWindow.message.stringValue == "Current rule feedback" && !rulesWindow.previewRunning, "Rule switches cancel tests and suppress their late completion")
        let changedSource = ControlledInspectionEngine(beforeReturn: { try Data("Changed during preview recognition".utf8).write(to: source) }); changedSource.release.signal()
        let changedPipeline = AutomationPipeline(engine: changedSource, scratch: root.appendingPathComponent("Preview Scratch"))
        rejects("Preview refuses a source changed during recognition", { _ = try changedPipeline.preview(source, rule: rule, cancellation: AutomationCancellation()) })
        let closingPreview = ControlledInspectionEngine(); runtime.engine = { closingPreview }; rulesWindow.gather()
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ closingPreview.started })
        rulesWindow.windowWillClose(Notification(name: NSWindow.willCloseNotification)); closingPreview.release.signal(); spin({ rulesWindow.previewWorkCount == 0 })
        check(!rulesWindow.previewRunning && rulesWindow.cancelTest.isHidden, "Closing the rule window cancels and drains its test")
        let quittingPreview = ControlledInspectionEngine(); runtime.engine = { quittingPreview }; rulesWindow.gather()
        rulesWindow.startPreview(source, rule: rulesWindow.draft); spin({ quittingPreview.started })
        let quittingApp = ConverterApp(); quittingApp.rulesController = rulesWindow
        check(quittingApp.applicationShouldTerminate(NSApp) == .terminateLater && !rulesWindow.previewRunning, "Quit cancels a file test and waits for its work to drain")
        quittingPreview.release.signal(); spin({ rulesWindow.previewWorkCount == 0 }); quittingApp.waitingForAutomationQuit = false
        check(quittingApp.applicationShouldTerminate(NSApp) == .terminateNow, "Quit proceeds after file-test cleanup")
        runtime.stop(); secondRuntime.stop()
        let existingInbox = root.appendingPathComponent("Existing Inbox"), existingOut = root.appendingPathComponent("Existing Out")
        for directory in [existingInbox, existingOut] { try fm.createDirectory(at: directory, withIntermediateDirectories: false) }
        let existingSource = existingInbox.appendingPathComponent("Already here.mp3"); try Data("EXISTING".utf8).write(to: existingSource)
        var existingRule = rule; existingRule.inputFolder = existingInbox.path; existingRule.destination = existingOut.path
        let existingEngine = FixtureAutomationEngine(), existingRuntime = try FolderAutomation(support: root.appendingPathComponent("Existing Support"), engine: { existingEngine })
        defer { existingRuntime.stop() }
        try existingRuntime.save([existingRule]); spin({ existingRuntime.canRunExisting })
        check(existingEngine.count == 0 && existingRuntime.pendingCount == 0, "Run Existing fixture establishes an ignored startup baseline")
        check(existingRuntime.runExisting() == 1 && existingRuntime.pendingCount == 1, "Ready Run Existing reports exactly the file it queues from the saved baseline")
        spin({ existingRuntime.activities.contains { $0.file == existingSource.lastPathComponent && $0.output != nil } })
        check(try existingEngine.count == 1 && Data(contentsOf: existingOut.appendingPathComponent("Already here-wav.wav")) == Data("EXISTING".utf8) && Data(contentsOf: existingSource) == Data("EXISTING".utf8), "Explicit existing-file execution produces the promised output once and keeps the original")
        existingRuntime.stop()
        if CommandLine.arguments.count > 1 {
            let contents = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents")
            let native = NativeAutomationEngine(backend: try BackendPaths(contents: contents, support: support))
            let wav = root.appendingPathComponent("Misnamed.bin")
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples/Tone.wav")
            try fm.copyItem(at: fixture, to: wav)
            let recognized = try native.inspect(wav, cancellation: AutomationCancellation()); check(recognized.category == "audio" && recognized.format == "wav", "Actual content recognition ignores misleading extension")
            let output = try native.convert(recognized, to: "mp3", staging: root.appendingPathComponent("Real engine"), cancellation: AutomationCancellation()); check(output.pathExtension == "mp3" && fm.fileExists(atPath: output.path), "Real private engine conversion")
        }
        var finalUsage = rusage(); getrusage(RUSAGE_SELF, &finalUsage)
        let evidence: [String: Any] = ["checks": checks, "passed": true, "native_events": true, "real_engine": CommandLine.arguments.count > 1, "idle_sample_seconds": 5, "idle_cpu_seconds": idleCPU, "test_peak_rss_bytes": finalUsage.ru_maxrss, "scan_1000_files_seconds": scanSeconds]
        print(String(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}

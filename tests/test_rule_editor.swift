import AppKit
import Darwin
import QuartzCore

/// A local engine keeps native editor regressions independent of installed
/// converters, user rules, watched folders, and original-file removal.
final class RuleEditorFixtureEngine: AutomationEngine {
    var conversions = 0
    func inspect(_ url: URL, cancellation: AutomationCancellation) throws -> RecognizedFile {
        try cancellation.check()
        guard let group = FormatCatalog.groups.first(where: { $0.formats.contains(url.pathExtension.lowercased()) }) else {
            throw AutomationIssue("Unsupported editor fixture")
        }
        return .init(url: url, format: url.pathExtension.lowercased(), category: group.id, targets: group.formats)
    }
    func convert(_ file: RecognizedFile, to format: String, staging: URL, cancellation: AutomationCancellation) throws -> URL {
        try cancellation.check(); conversions += 1
        guard file.targets.contains(format) else { throw AutomationIssue("Incompatible editor fixture") }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let output = staging.appendingPathComponent("result." + format)
        try Data(contentsOf: file.url).write(to: output)
        return output
    }
}

@main
struct RuleEditorTests {
    static var checks = 0
    static func fail(_ label: String) -> Never {
        FileHandle.standardError.write(Data(("FAIL: " + label + "\n").utf8)); exit(1)
    }
    static func check(_ value: @autoclosure () throws -> Bool, _ label: String) {
        do { if try !value() { fail(label) } } catch { fail(label + ": " + error.localizedDescription) }
        checks += 1
    }
    static func rejects(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fail(label + " (operation did not reject)") } catch { checks += 1 }
    }
    static func spin(_ until: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !until(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
        check(until(), "Local native preview finishes within five seconds")
    }
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    static func within(_ view: NSView, _ ancestor: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current { if candidate === ancestor { return true }; current = candidate.superview }
        return false
    }
    static func visibleFrame(_ view: NSView, in editor: FolderRulesWindow, _ label: String) {
        let content = editor.window!.contentView!, frame = view.convert(view.bounds, to: content)
        check(frame.width > 0 && frame.height > 0 && frame.minX >= -1 && frame.maxX <= content.bounds.width + 1 && frame.minY >= -1 && frame.maxY <= content.bounds.height + 1, label)
    }
    static func button(_ editor: FolderRulesWindow, _ label: String) -> RuleButton {
        guard let result = descendants(editor.window!.contentView!).compactMap({ $0 as? RuleButton }).first(where: { $0.accessibilityLabel() == label }) else {
            fail("Missing native button: " + label)
        }
        return result
    }
    static func conditionType(_ editor: FolderRulesWindow, _ index: Int) -> RulePopup {
        guard let result = descendants(editor.body).compactMap({ $0 as? RulePopup }).first(where: { $0.accessibilityLabel() == "Condition \(index + 1) type" }) else {
            fail("Missing condition type popup")
        }
        return result
    }
    static func select(_ popup: NSPopUpButton, value: String) {
        guard let item = popup.itemArray.first(where: { $0.representedObject as? String == value }) else {
            fail("Missing popup value: " + value)
        }
        popup.select(item)
    }
    static func actionBlocks(_ editor: FolderRulesWindow) -> [RulePuzzleBlock] {
        descendants(editor.body).compactMap { $0 as? RulePuzzleBlock }.filter { $0.drop != nil }
    }
    static func exampleNames(_ editor: FolderRulesWindow) -> [String] {
        editor.exampleLabels.map { $0.stringValue.components(separatedBy: " → ").last ?? "" }
    }
    static func editLive(_ field: NSTextField, value: String, editor: FolderRulesWindow) {
        editor.window!.makeKeyAndOrderFront(nil)
        check(editor.window!.makeFirstResponder(field), "Editable value accepts native focus")
        guard let live = field.currentEditor() else { fail("Native field editor is required") }
        live.string = value
    }
    static func install(_ rule: WatchRule, in editor: FolderRulesWindow) throws {
        editor.window?.makeFirstResponder(nil)
        check(!rule.enabled, "Editor fixtures never start watching user files")
        try editor.runtime.save([rule])
        editor.selectedID = rule.id; editor.draft = rule
        editor.rebuildEditor(resetScroll: true); editor.reloadList()
    }
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UltraConvert rule editor \(UUID())")
        let inbox = root.appendingPathComponent("Inbox"), output = root.appendingPathComponent("Output")
        for folder in [inbox, output] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let engine = RuleEditorFixtureEngine()
        let runtime = try FolderAutomation(support: root.appendingPathComponent("Support"), engine: { engine })
        let editor = FolderRulesWindow(runtime: runtime)
        defer { editor.window?.orderOut(nil); runtime.stop(); try? fm.removeItem(at: root) }
        check(editor.window!.contentMinSize == NSSize(width: 900, height: 620), "The declared minimum is a usable content size, including the sidebar and footer")

        check(editor.selectedID == nil && editor.conditions.isEmpty && editor.steps.isEmpty && editor.exampleLabels.isEmpty, "Empty editor contains no stale rule controls")
        check(!editor.save.isEnabled && !editor.test.isEnabled && editor.flowSummary.stringValue.contains("WHEN a file arrives"), "Empty editor explains the flow before enabling actions")
        check(!button(editor, "Add Convert action").isEnabled && !button(editor, "Add Rename action").isEnabled, "The persistent action palette waits until a rule is selected")
        check(["Audio → MP3", "Images → WebP", "Blank Flow"].allSatisfy { button(editor, $0).isEnabled }, "Empty editor offers concrete starting templates")
        button(editor, "Audio → MP3").invoke()
        check(runtime.rules.count == 1 && editor.selectedID == runtime.rules.first?.id && !editor.draft.enabled, "Template button creates a saved disabled rule")
        check(editor.draft.conditions == [.init(field: .category, value: "audio")] && editor.draft.steps == [.init(kind: .convert, value: "mp3")], "Audio template has the promised condition and action")

        var rule = WatchRule(); rule.name = "Editor fixture"; rule.inputFolder = inbox.path; rule.destination = output.path
        rule.conditions = [.init(field: .format, value: "wav")]; rule.steps = [.init(kind: .convert, value: "mp3")]; rule.settleSeconds = 7
        try install(rule, in: editor)
        let reopened = FolderRulesWindow(runtime: runtime)
        check(reopened.selectedID == rule.id && reopened.message.stringValue.contains("check this saved flow") && !reopened.message.stringValue.contains("Choose a template"), "Cold loaded rule guidance matches the selected saved flow")
        reopened.window?.orderOut(nil)
        editor.gather()
        check(editor.draft == rule && editor.settle.selectedItem?.representedObject as? Double == 7, "A valid custom seven-second wait round-trips without phantom edits")
        check(!editor.editingStatus.stringValue.contains("Unsaved"), "Opening an unchanged custom-wait rule stays clean")
        button(editor, "Arrival Options…").invoke()
        check(editor.showsArrivalOptions && editor.settle.superview != nil && editor.draft.settleSeconds == 7, "Arrival options reveal the selected custom wait")
        button(editor, "Hide Arrival Options").invoke()
        check(!editor.showsArrivalOptions && editor.draft.settleSeconds == 7, "Hiding arrival options preserves their values")

        let oldAddCondition = button(editor, "Add Condition")
        oldAddCondition.invoke()
        check(editor.draft.conditions.count == 2 && editor.conditions.count == 2 && runtime.rules == [rule], "Add Condition changes the draft and actual native controls only")
        let afterAdd = editor.draft
        oldAddCondition.invoke()
        check(editor.draft == afterAdd, "A previous Add Condition callback cannot act after rebuild")
        let oldType = conditionType(editor, 1)
        select(oldType, value: MatchField.nameContains.rawValue); oldType.invoke()
        check(editor.draft.conditions[1] == .init(field: .nameContains, value: ""), "Condition popup changes the correct model field and starts with an empty filename test")
        let afterType = editor.draft
        select(oldType, value: MatchField.category.rawValue); oldType.invoke()
        check(editor.draft == afterType, "A stale condition type callback cannot overwrite a rebuilt row")
        editLive(editor.conditions[1].1 as! NSTextField, value: "Session", editor: editor)
        button(editor, "Add Condition").invoke()
        check(editor.draft.conditions[1].value == "Session", "Adding a condition gathers active filename text before rebuilding")
        let oldRemove = button(editor, "Remove condition 1")
        oldRemove.invoke()
        check(editor.draft.conditions.count == 2 && editor.draft.conditions[0] == .init(field: .nameContains, value: "Session"), "Removing a condition retains the other row's type and value")
        let afterRemove = editor.draft; oldRemove.invoke()
        check(editor.draft == afterRemove, "A removed condition's callback cannot delete its replacement")
        editLive(editor.conditions[0].1 as! NSTextField, value: "Edited while removing", editor: editor)
        button(editor, "Remove condition 2").invoke()
        check(editor.draft.conditions == [.init(field: .nameContains, value: "Edited while removing")], "Removing another row preserves active condition input")
        check(!button(editor, "Remove condition 1").isEnabled, "The last condition has a disabled remove affordance")
        button(editor, "Remove condition 1").invoke()
        check(editor.draft.conditions.count == 1, "The model guard preserves the last condition even if its callback is invoked")
        editor.matching.selectItem(at: 1)
        check(editor.matching.sendAction(editor.matching.action, to: editor.matching.target), "Matching popup dispatches its installed native action")
        check(!editor.draft.matchAll && editor.flowSummary.stringValue.contains("match any 1 condition"), "ANY selection updates the model and live flow summary")
        editLive(editor.conditions[0].1 as! NSTextField, value: "Do not lose this", editor: editor)
        let prefixType = conditionType(editor, 0); select(prefixType, value: MatchField.namePrefix.rawValue); prefixType.invoke()
        check(editor.draft.conditions[0] == .init(field: .namePrefix, value: "Do not lose this"), "Changing filename Contains to Prefix preserves active text")
        let suffixType = conditionType(editor, 0); select(suffixType, value: MatchField.nameSuffix.rawValue); suffixType.invoke()
        check(editor.draft.conditions[0] == .init(field: .nameSuffix, value: "Do not lose this"), "Changing between filename condition kinds keeps the user's value")

        try install(rule, in: editor)
        let oldAddRename = button(editor, "Add Rename action"); oldAddRename.invoke()
        check(editor.draft.steps == [.init(kind: .convert, value: "mp3"), .init(kind: .rename, value: "{name}-{format}")] && editor.exampleLabels.count == 2, "Add Rename builds the expected second action and filename illustration")
        oldAddRename.invoke()
        check(editor.draft.steps.count == 3 && oldAddRename === button(editor, "Add Rename action"), "The persistent Add Rename palette still edits the current flow after a rebuild")
        button(editor, "Remove action 3").invoke()
        let outputFormat = editor.steps[0].1 as! NSPopUpButton
        select(outputFormat, value: "flac")
        check(outputFormat.sendAction(outputFormat.action, to: outputFormat.target), "Output-format popup dispatches its installed native action")
        check(editor.draft.steps[0].value == "flac" && exampleNames(editor)[1] == "Example-flac.flac", "Choosing an output format refreshes both the conversion and downstream rename example")
        select(outputFormat, value: "mp3"); _ = outputFormat.sendAction(outputFormat.action, to: outputFormat.target)
        let renameField = editor.steps[1].1 as! NSTextField
        editLive(renameField, value: "{name}-finished-{format}", editor: editor)
        let liveExample = editor.exampleLabels[1]
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: renameField))
        check(editor.draft.steps[1].value == "{name}-finished-{format}" && exampleNames(editor)[1] == "Example-finished-mp3.mp3" && liveExample.stringValue.hasPrefix("Illustration using WAV input"), "Typing a rename template immediately updates an explicitly illustrative output example")
        check(editor.exampleLabels[1] === liveExample && runtime.rules == [rule] && editor.editingStatus.stringValue.contains("Unsaved changes"), "Live typing preserves the control hierarchy and keeps changes unsaved")
        editLive(renameField, value: "{name}-live-{format}", editor: editor)
        let oldUp = button(editor, "Move action 2 up"); oldUp.invoke()
        check(editor.draft.steps[0] == .init(kind: .rename, value: "{name}-live-{format}") && editor.draft.steps[1].kind == .convert, "Moving an action commits active rename text before changing order")
        check(exampleNames(editor) == ["Example-live-wav.wav", "Example-live-wav.mp3"], "Examples honor rename-before-conversion order and current source format")
        let afterMove = editor.draft; oldUp.invoke()
        check(editor.draft == afterMove, "A stale Move Up callback cannot move a different rebuilt action")
        button(editor, "Move action 1 down").invoke()
        check(editor.draft.steps[0].kind == .convert && exampleNames(editor)[1] == "Example-live-mp3.mp3", "Move Down returns the action and its illustration to conversion-first order")
        editLive(editor.steps[1].1 as! NSTextField, value: "{name}-saved-{format}", editor: editor)
        button(editor, "Add Convert action").invoke()
        check(editor.draft.steps[1].value == "{name}-saved-{format}" && editor.steps.count == 3, "Adding an action preserves an active rename template")
        let oldActionRemove = button(editor, "Remove action 1"); oldActionRemove.invoke()
        check(editor.draft.steps.map(\.kind) == [.rename, .convert] && editor.draft.steps[0].value == "{name}-saved-{format}", "Removing an action preserves the remaining order and rename value")
        let afterActionRemove = editor.draft; oldActionRemove.invoke()
        check(editor.draft == afterActionRemove, "A removed action callback cannot delete its replacement")
        button(editor, "Remove action 2").invoke()
        check(!button(editor, "Remove action 1").isEnabled && !button(editor, "Move action 1 up").isEnabled && !button(editor, "Move action 1 down").isEnabled, "One-action flows expose disabled remove and out-of-range moves")
        button(editor, "Remove action 1").invoke(); button(editor, "Move action 1 up").invoke(); button(editor, "Move action 1 down").invoke()
        check(editor.draft.steps.count == 1, "One-action guards hold when disabled callbacks are invoked directly")
        editor.save.invoke()
        check(runtime.rules == [editor.draft] && editor.draft.settleSeconds == 7 && !editor.editingStatus.stringValue.contains("Unsaved changes"), "Save Rule persists the edited block flow and custom wait through its actual native callback")
        check(try runtime.store.load() == [editor.draft], "A saved editor flow reloads from disk with the same actions, conditions and settings")
        let previousRuleID = editor.selectedID; editor.newRule(template: 1)
        check(runtime.rules.count == 2 && editor.selectedID == runtime.rules.last?.id && editor.selectedID != previousRuleID && editor.draft.id == runtime.rules.last?.id && !editor.draft.enabled, "Adding a new rule selects its disabled draft instead of the old cached table row")
        let newRuleID = editor.selectedID
        button(editor, "Move Up").invoke()
        check(runtime.rules.first?.id == newRuleID && editor.selectedID == newRuleID && editor.draft.id == newRuleID, "Moving a saved rule up preserves its identity across native table reload")
        button(editor, "Move Down").invoke()
        check(runtime.rules.last?.id == newRuleID && editor.selectedID == newRuleID, "Moving a saved rule down keeps editing that rule rather than its former row")
        button(editor, "Duplicate").invoke()
        check(runtime.rules.count == 3 && editor.selectedID == runtime.rules.last?.id && editor.selectedID != newRuleID && editor.draft == runtime.rules.last && !editor.draft.enabled, "Duplicate selects the new disabled copy after table reload instead of another cached row")

        var imageRule = rule; imageRule.conditions = [.init(field: .category, value: "image")]; imageRule.steps = [.init(kind: .convert, value: "webp")]
        try install(imageRule, in: editor); button(editor, "Add Convert action").invoke()
        check(editor.draft.steps.last == .init(kind: .convert, value: "webp"), "Adding another Convert to an image flow picks an image-compatible default")
        var impossible = imageRule; impossible.steps.append(.init(kind: .convert, value: "mp3")); impossible.enabled = true
        rejects("An enabled WebP-to-MP3 chain is rejected before files arrive") { try impossible.validate(roots: [inbox.path]) }
        impossible = rule; impossible.conditions = [.init(field: .format, value: "png")]; impossible.steps = [.init(kind: .convert, value: "mp3")]
        rejects("An ALL input-format condition rejects an impossible first conversion") { try impossible.validate(roots: [inbox.path]) }
        var extraction = rule; extraction.conditions = [.init(field: .format, value: "mp4")]; extraction.steps = [.init(kind: .convert, value: "mp3"), .init(kind: .convert, value: "opus")]; extraction.enabled = true
        try extraction.validate(roots: [inbox.path]); check(extraction.steps.count == 2, "Video-to-audio extraction followed by another audio conversion remains valid")

        try install(rule, in: editor)
        select(editor.policy, value: "archive"); editor.policy.invoke()
        check(editor.draft.originalPolicy == .archive && editor.acknowledge.window === editor.window && button(editor, "Archive originals here — choose folder").isEnabled, "The actual original policy popup reveals archive destination and acknowledgement controls")
        editor.acknowledge.state = .on
        check(editor.acknowledge.sendAction(editor.acknowledge.action, to: editor.acknowledge.target) && editor.draft.acknowledgedRemoval, "Original-removal acknowledgement dispatches its installed action and updates the draft")
        select(editor.policy, value: "trash"); editor.policy.invoke()
        check(editor.draft.originalPolicy == .trash && editor.acknowledge.window === editor.window && editor.flowSummary.stringValue.contains("sent to Trash"), "Selecting Trash updates its original-file consequence in the live flow")
        select(editor.policy, value: "keep"); editor.policy.invoke()
        check(editor.draft.originalPolicy == .keep && editor.acknowledge.window == nil && editor.flowSummary.stringValue.contains("original kept"), "Keep hides destructive acknowledgement and explains that the source remains")
        try install(rule, in: editor)
        let previewFile = inbox.appendingPathComponent("Preview.wav"); try Data("PREVIEW".utf8).write(to: previewFile)
        editor.startPreview(previewFile, rule: editor.draft)
        editor.window!.setContentSize(NSSize(width: 900, height: 620)); editor.window!.contentView!.layoutSubtreeIfNeeded()
        check(!editor.cancelTest.isHidden && !editor.test.isEnabled, "An active native preview offers cancellation before its asynchronous completion")
        visibleFrame(editor.cancelTest, in: editor, "Cancel Preview stays reachable in the minimum-size window while work is active")
        spin { editor.previewWorkCount == 0 }
        check(editor.branchStatus.stringValue.hasPrefix("↓ MATCH") && engine.conversions == 0 && editor.viewPreviewDetails.isEnabled, "A matching read-only preview identifies the action branch without converting")
        editor.name.stringValue = "Edited after decision preview"; editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.name))
        check(editor.branchStatus.stringValue == "Preview a file to see which path it takes." && !editor.viewPreviewDetails.isEnabled, "Editing clears a previously matched decision path instead of presenting stale guidance")
        var noMatch = rule; noMatch.conditions = [.init(field: .nameContains, value: "not-in-the-fixture-name")]
        try install(noMatch, in: editor); editor.startPreview(previewFile, rule: editor.draft); spin { editor.previewWorkCount == 0 }
        check(try editor.branchStatus.stringValue.hasPrefix("↳ NO MATCH") && engine.conversions == 0 && Data(contentsOf: previewFile) == Data("PREVIEW".utf8), "A nonmatching preview identifies the unchanged-original branch and keeps file contents")

        var unknown = rule; unknown.conditions = [.init(field: .format, value: "future-format")]; unknown.steps = [.init(kind: .convert, value: "future-format")]
        try install(unknown, in: editor); editor.gather()
        check(editor.draft == unknown && (editor.conditions[0].1 as! NSPopUpButton).selectedItem?.representedObject as? String == "future-format" && (editor.steps[0].1 as! NSPopUpButton).selectedItem?.representedObject as? String == "future-format", "Unknown saved formats remain visible and invalid rather than silently becoming MP3")
        rejects("Unknown output format cannot become an enabled valid rule") { try editor.draft.validate(roots: [inbox.path]) }
        var incomplete = rule; incomplete.conditions = []; incomplete.steps = []
        try install(incomplete, in: editor)
        check(editor.conditions.isEmpty && editor.steps.isEmpty && editor.exampleLabels.isEmpty, "An incomplete disabled flow can open without indexing nonexistent rows")
        button(editor, "Add Condition").invoke(); button(editor, "Add Rename action").invoke()
        check(editor.conditions.count == 1 && editor.steps.count == 1 && editor.draft.steps[0].kind == .rename, "An incomplete flow can recover through actual add controls")

        var maximum = rule; maximum.conditions = Array(repeating: .init(field: .category, value: "audio"), count: 12); maximum.steps = Array(repeating: .init(kind: .convert, value: "mp3"), count: 8)
        try install(maximum, in: editor)
        check(!button(editor, "Add Condition").isEnabled && !button(editor, "Add Convert action").isEnabled && !button(editor, "Add Rename action").isEnabled, "Editor advertises condition and action limits before a click")
        button(editor, "Add Condition").invoke(); button(editor, "Add Convert action").invoke(); button(editor, "Add Rename action").invoke()
        editor.removeCondition(-1); editor.removeCondition(12); editor.changeCondition(12, to: .format); editor.removeStep(-1); editor.removeStep(8); editor.moveAction(from: -1, to: 1); editor.moveAction(from: 0, to: 8); editor.moveStep(0, -1)
        check(editor.draft == maximum, "Limit and bounds guards reject invalid structural operations without corrupting the draft")
        for tooManyConditions in [true, false] {
            var oversized = maximum
            if tooManyConditions { oversized.conditions.append(.init()) } else { oversized.steps.append(.init()) }
            rejects("Disabled draft saves cannot exceed the native editor's block limits") { try runtime.store.save([oversized]) }
            check(try runtime.store.load() == [maximum], "Rejecting an oversized draft leaves the saved flow intact")
            try runtime.store.write(JSONEncoder().encode(AutomationDocument(rules: [oversized])), "rules.json")
            rejects("Imported disabled drafts cannot allocate more blocks than the editor supports") { _ = try runtime.store.load() }
            try runtime.store.save([maximum])
        }

        var dragRule = rule; dragRule.steps = [.init(kind: .convert, value: "mp3"), .init(kind: .rename, value: "{name}-ready"), .init(kind: .convert, value: "flac")]
        try install(dragRule, in: editor)
        let token = editor.dragToken(0)
        check(editor.acceptActionDrag(token) && !editor.acceptActionDrag("garbage") && !editor.acceptActionDrag(editor.dragToken(-1)) && !editor.acceptActionDrag(editor.dragToken(3)), "Action drag tokens accept only a valid current action")
        check(!editor.dropAction(token, at: -1, below: false) && !editor.dropAction(token, at: 3, below: true) && editor.draft == dragRule, "An invalid drag target cannot reorder the flow")
        check(actionBlocks(editor)[2].drop?(token, true) == true && editor.draft.steps == [dragRule.steps[1], dragRule.steps[2], dragRule.steps[0]], "Dropping below the last block moves the first action to the end without swapping other actions")
        check(!editor.acceptActionDrag(token), "A completed structural drag invalidates its old revision token")
        let lastToken = editor.dragToken(2)
        check(actionBlocks(editor)[0].drop?(lastToken, false) == true && editor.draft == dragRule, "Dropping above the first block restores the ordered flow")
        let oldTarget = actionBlocks(editor)[0]; editor.rebuildEditor()
        let freshToken = editor.dragToken(2)
        check(oldTarget.acceptsDrop?(freshToken) == false && oldTarget.drop?(freshToken, true) == false && editor.draft == dragRule, "A retained old target block cannot accept a fresh token for its stale positional index")
        let otherEditor = FolderRulesWindow(runtime: runtime)
        defer { otherEditor.window?.orderOut(nil) }
        check(!otherEditor.acceptActionDrag(freshToken), "Another editor session rejects a token even for the same rule")
        var otherRule = dragRule; otherRule.id = UUID(); otherRule.name = "Other flow"
        try runtime.save([dragRule, otherRule]); editor.selectedID = otherRule.id; editor.draft = otherRule; editor.rebuildEditor()
        check(!editor.acceptActionDrag(freshToken), "A token cannot cross from one saved rule into another")

        try install(maximum, in: editor)
        editor.window!.setContentSize(NSSize(width: 900, height: 620)); editor.window!.contentView!.layoutSubtreeIfNeeded()
        let clip = editor.editorScroll.contentView
        check(editor.editorScroll.documentView!.bounds.height > clip.bounds.height + 200, "Large modular flows use a scrolling editor")
        clip.scroll(to: NSPoint(x: 0, y: 180)); editor.editorScroll.reflectScrolledClipView(clip)
        let beforeScroll = clip.bounds.origin.y
        button(editor, "Remove condition 12").invoke()
        check(abs(clip.bounds.origin.y - beforeScroll) < 2, "A structural edit preserves the current editor scroll position")
        for (title, key) in [("Inbox", "WHEN"), ("Match", "IF"), ("Actions", "DO"), ("Output", "SAVE"), ("Original", "AFTER")] {
            button(editor, "Jump to " + title + " block").invoke()
            let node = editor.flowNodes[key]!, canvas = editor.editorScroll.documentView!
            check(node.convert(node.bounds, to: canvas).intersects(clip.bounds), "A persistent flow navigator brings its actual block into the visible editor")
        }
        let tabs = editor.viewTabs!
        tabs.selectedSegment = 1; _ = tabs.sendAction(tabs.action, to: tabs.target)
        check(editor.editorScroll.isHidden && !editor.activityScroll.isHidden, "Activity tab dispatches its installed native action")
        button(editor, "Jump to Actions block").invoke()
        check(tabs.selectedSegment == 0 && !editor.editorScroll.isHidden && editor.activityScroll.isHidden, "Flow navigation returns from Activity to the visible rule builder")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            editor.window!.appearance = NSAppearance(named: appearance)
            editor.window!.contentView!.layoutSubtreeIfNeeded()
            let content = editor.window!.contentView!
            for control in ([editor.save, editor.test, editor.existing, editor.pause, editor.flowSummary, editor.stateLabel] as [NSView]) + editor.actionPaletteButtons {
                visibleFrame(control, in: editor, "Essential flow controls remain inside the minimum-size light/dark window")
            }
            for control in descendants(content).compactMap({ $0 as? NSControl }).filter({ !$0.isHiddenOrHasHiddenAncestor && !within($0, editor.editorScroll) && !within($0, editor.activityScroll) }) {
                visibleFrame(control, in: editor, "Every visible non-scrolling control fits in the minimum window: " + (control.accessibilityLabel() ?? String(describing: type(of: control))))
            }
            for label in descendants(content).compactMap({ $0 as? NSTextField }).filter({ $0.accessibilityLabel() == "Folder watcher lifetime" }) {
                visibleFrame(label, in: editor, "Sidebar watcher lifetime explanation stays visible at minimum size")
            }
            for block in actionBlocks(editor) {
                for control in descendants(block).filter({ $0 is RuleDragHandle || $0 is RuleButton || ($0 is NSPopUpButton) }) {
                    let frame = control.convert(control.bounds, to: block)
                    check(frame.width > 0 && frame.minX >= -1 && frame.maxX <= block.bounds.width + 1, "Action values, drag grips and keyboard move/remove buttons fit inside the narrow connected block")
                }
            }
        }
        check(Set(descendants(editor.body).compactMap { ($0 as? RulePuzzleBlock)?.tone.color }).count >= 4, "Connected blocks distinguish arrival, decision, action, destination and original policy")
        for pair in zip(editor.body.arrangedSubviews, editor.body.arrangedSubviews.dropFirst()) {
            guard let first = pair.0 as? RulePuzzleBlock, let second = pair.1 as? RulePuzzleBlock else { continue }
            let join = first.convert(first.bounds, to: editor.body).intersection(second.convert(second.bounds, to: editor.body))
            check(abs(join.height - RulePuzzleGeometry.connectionOverlap) < 0.01, "Adjacent puzzle blocks visually connect instead of leaving separated card gaps")
            let canvas = editor.editorScroll.documentView!
            let upperSeam = first.convert(NSPoint(x: 64, y: RulePuzzleGeometry.connectorBaseline(height: first.bounds.height, top: false)), to: canvas).y
            let lowerSeam = second.convert(NSPoint(x: 64, y: RulePuzzleGeometry.connectorBaseline(height: second.bounds.height, top: true)), to: canvas).y
            let upperTip = first.convert(NSPoint(x: 64, y: RulePuzzleGeometry.connectorTip(height: first.bounds.height, top: false)), to: canvas).y
            let lowerNotch = second.convert(NSPoint(x: 64, y: RulePuzzleGeometry.connectorTip(height: second.bounds.height, top: true)), to: canvas).y
            check(abs(upperSeam - lowerSeam) < 0.01 && abs(upperTip - lowerNotch) < 0.01, "Puzzle body seam and tab/notch points meet exactly, without the previous one-point offset")
        }
        for piece in descendants(editor.body).compactMap({ $0 as? RulePuzzleBlock }) {
            guard let contents = piece.subviews.first else { fail("Puzzle content is required") }
            let frame = contents.convert(contents.bounds, to: piece)
            check(abs(frame.minX - 20) < 0.01 && abs(piece.bounds.width - frame.maxX - 20) < 0.01, "Puzzle content has equal twenty-point horizontal padding")
            check(frame.minY - RulePuzzleGeometry.connectorTip(height: piece.bounds.height, top: true) >= 13 && RulePuzzleGeometry.connectorBaseline(height: piece.bounds.height, top: false) - frame.maxY >= 14, "Puzzle content clears the notch by thirteen points and bottom body edge by fourteen points")
        }
        var columnRule = dragRule
        columnRule.conditions = [.init(field: .category, value: "audio"), .init(field: .namePrefix, value: "A long descriptive recording name"), .init(field: .format, value: "wav")]
        try install(columnRule, in: editor)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            editor.window!.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 900, height: 620), NSSize(width: 1040, height: 750)] {
                editor.window!.setContentSize(size); editor.window!.contentView!.layoutSubtreeIfNeeded()
                let blocks = actionBlocks(editor)
                for tool in ["up", "down", "Remove"] {
                    let labels = (1...blocks.count).map { tool == "Remove" ? "Remove action \($0)" : "Move action \($0) " + tool }
                    let columns = zip(labels, blocks).map { label, block in button(editor, label).convert(button(editor, label).bounds, to: block).minX }
                    check(columns.allSatisfy { abs($0 - columns[0]) < 0.01 }, "Convert and Rename actions align every trailing toolbar control at normal and compact widths in both appearances: \(tool) \(columns)")
                }
                let decision = editor.flowNodes["IF"]!
                let starts = editor.conditions.map { $0.1.convert($0.1.alignmentRect(forFrame: $0.1.bounds), to: decision).minX }
                check(starts.allSatisfy { abs($0 - starts[0]) < 0.01 }, "Format, category and filename condition values share a stable column")
            }
        }
        editor.window!.setContentSize(NSSize(width: 900, height: 620))
        let opaque = RuleBlock(content: NSTextField(labelWithString: "Opaque accessibility fallback"), allowGlass: false)
        check(!opaque.usesGlass && !descendants(opaque).contains(where: { $0 is NSVisualEffectView }), "Reduce Transparency fallback contains an opaque native surface without blur")
        check(InterfaceMotion.duration(reduceMotion: true, running: true) == 0 && InterfaceMotion.duration(reduceMotion: false, running: false) == 0, "Reduced Motion and nonrunning native test hosts use immediate transitions")
        check(InterfaceMotion.duration(reduceMotion: false, running: true) == 0.18, "Interactive transitions share one short native duration")
        for background in [NSColor.systemYellow, .systemBlue, .systemPink, .white, .black, .gray] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    let light = RuleSelectionText.luminance(background), foreground = RuleSelectionText.foreground(on: background)
                    let contrast = foreground == .black ? (light + 0.05) / 0.05 : 1.05 / (light + 0.05)
                    check(contrast >= 4.5, "Rule selection chooses a readable foreground for bright and dark accents in both appearances")
                }
            }
        }
        editor.body.alphaValue = 0.4; InterfaceMotion.reveal(editor.body, reduceMotion: true)
        check(editor.body.alphaValue == 1, "Reduced Motion immediately reveals complete content instead of leaving a faded previous transition")
        for key in ["DO", "WHEN", "SAVE", "IF", "AFTER"] { editor.jumpToBlock(key) }
        let latestNode = editor.flowNodes["AFTER"]!, latestCanvas = editor.editorScroll.documentView!
        check(latestNode.convert(latestNode.bounds, to: latestCanvas).intersects(editor.editorScroll.contentView.bounds), "Rapid flow navigation leaves the final requested stage visible without a stale callback")
        InterfaceMotion.scroll(editor.editorScroll, to: .zero, reduceMotion: true)
        check(editor.editorScroll.contentView.bounds.origin == .zero, "Reduced Motion scroll jumps synchronously to the requested destination")
        try install(rule, in: editor)
        tabs.selectedSegment = 1; editor.changeTab(tabs)
        button(editor, "Add Rename action").invoke()
        check(tabs.selectedSegment == 0 && !editor.editorScroll.isHidden && editor.activityScroll.isHidden, "Adding an action from Activity returns to its visible builder instead of changing a hidden flow")
        try install(maximum, in: editor)
        // Exercise the production animation path in a real NSApplication.run
        // event loop, then interrupt it with rebuilding, tab changes and an
        // explicit Reduce Motion snap. These fixtures never run a conversion.
        editor.window!.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            check(NSApp.isRunning, "Animation regression uses the live AppKit event loop")
            // Finish the first ordered window's layout/display transaction
            // before measuring interruption. NSApplication.run may still be
            // completing launch and its initial window sizing on this turn.
            editor.window!.contentView!.layoutSubtreeIfNeeded()
            editor.window!.displayIfNeeded(); CATransaction.flush()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                editor.window!.contentView!.layoutSubtreeIfNeeded()
                let viewport = editor.editorScroll.contentView.bounds.size
                check(viewport.width > 0 && viewport.height > 0 && editor.editorScroll.documentView!.bounds.height > viewport.height, "Live animation interruption starts with a laid-out scrollable editor")
                editor.jumpToBlock("DO"); editor.jumpToBlock("SAVE")
                editor.rebuildEditor(resetScroll: true)
                editor.jumpToBlock("AFTER"); tabs.selectedSegment = 1; editor.changeTab(tabs)
                tabs.selectedSegment = 0; editor.changeTab(tabs)
                InterfaceMotion.scroll(editor.editorScroll, to: NSPoint(x: 0, y: 100), reduceMotion: false)
                InterfaceMotion.scroll(editor.editorScroll, to: .zero, reduceMotion: true)
                InterfaceMotion.reveal(editor.body, reduceMotion: false); InterfaceMotion.reveal(editor.body, reduceMotion: true)
                let endpoint = editor.editorScroll.contentView.bounds
                func atRequestedOrigin() -> Bool {
                    let origin = editor.editorScroll.contentView.bounds.origin
                    // Core Animation can finish a native scroll with subpixel
                    // floating-point residue. 0.01pt is far below one display pixel.
                    return abs(origin.x) < 0.01 && abs(origin.y) < 0.01
                }
                check(atRequestedOrigin(), "Reduced Motion reaches the requested live origin synchronously: \(endpoint.origin)")
                check(abs(editor.body.alphaValue - 1) < 0.0001, "Reduced Motion reaches full model opacity synchronously: \(editor.body.alphaValue)")
                CATransaction.flush()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                    check(atRequestedOrigin(), "No stale scroll takes over during the interrupted animation: \(editor.editorScroll.contentView.bounds.origin)")
                    check((editor.body.layer?.presentation()?.opacity ?? editor.body.layer?.opacity ?? 1) >= 0.999, "Reduced Motion cancels pending native opacity animation immediately, including before transaction commit")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    check(atRequestedOrigin(), "Interrupted live animations cannot restore an old scroll destination: origin=\(editor.editorScroll.contentView.bounds.origin), expected=\(endpoint.origin)")
                    check(abs(editor.body.alphaValue - 1) < 0.0001, "Interrupted live animations cannot leave reduced-motion content faded: model=\(editor.body.alphaValue), presentation=\(String(describing: editor.body.layer?.presentation()?.opacity))")
                    let finalViewport = editor.editorScroll.contentView.bounds.size
                    check(abs(finalViewport.width - viewport.width) < 0.01 && abs(finalViewport.height - viewport.height) < 0.01, "The interruption test retains a stable viewport instead of measuring initial window sizing")
                    check(tabs.selectedSegment == 0 && !editor.editorScroll.isHidden && editor.activityScroll.isHidden, "Rapid animated tab changes retain the latest visible builder state")
                    check(!(editor.editorScroll.contentView.layer?.animationKeys() ?? []).contains(where: { $0.lowercased().contains("bounds") }), "Reduced Motion and rebuilding leave no previous bounds animation")
                    NSApp.stop(nil)
                    if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
                }
            }
        }
        NSApp.run()
        for policy in [OriginalPolicy.archive, .trash] {
            var removal = maximum; removal.originalPolicy = policy; removal.acknowledgedRemoval = false
            removal.archiveFolder = root.appendingPathComponent("Archive").path
            try install(removal, in: editor)
            editor.window!.setContentSize(NSSize(width: 900, height: 620)); editor.window!.contentView!.layoutSubtreeIfNeeded()
            let original = editor.flowNodes["AFTER"]!
            let acknowledgement = editor.acknowledge.convert(editor.acknowledge.bounds, to: original)
            check(!editor.acknowledge.isHiddenOrHasHiddenAncestor && acknowledgement.minX >= 20 && acknowledgement.maxX <= original.bounds.width - 20, "Archive and Trash acknowledgement fits within compact puzzle content padding")
            for label in descendants(original).compactMap({ $0 as? NSTextField }) {
                check((label.font?.pointSize ?? 0) >= 12, "Original-file instructions remain legible at compact width")
            }
        }

        // Simulate AppKit requesting rows cached before the model shrinks.
        let removedIndex = runtime.rules.count - 1
        try runtime.save([])
        check(editor.tableView(editor.table, viewFor: editor.table.tableColumns.first, row: removedIndex) == nil && editor.tableView(editor.table, viewFor: editor.table.tableColumns.first, row: -1) == nil, "Stale rule table rows return no cell instead of indexing removed rules")
        check(!editor.tableView(editor.table, shouldSelectRow: removedIndex) && !editor.tableView(editor.table, shouldSelectRow: -1), "Stale rule row selection is rejected before attempting an unsaved-change prompt")
        let longActivityMessage = String(repeating: "The conversion could not finish; the original was retained. ", count: 30) + "Recovery details remain complete."
        let longActivity = AutomationActivity(rule: "Flow", file: "Example.wav", message: longActivityMessage, output: output.path)
        runtime.activities = [longActivity]
        let activityCell = editor.tableView(editor.activityTable, viewFor: editor.activityTable.tableColumns.first, row: 0) as! ActivityCell
        for width in [520.0, 660.0] {
            activityCell.frame = NSRect(x: 0, y: 0, width: width, height: editor.activityTable.rowHeight)
            activityCell.layoutSubtreeIfNeeded()
            for button in [activityCell.detailsButton, activityCell.reveal] {
                let frame = button.convert(button.bounds, to: activityCell)
                check(frame.minX >= 0 && frame.maxX <= width && frame.minY >= 0 && frame.maxY <= activityCell.bounds.height, "Activity Details and Reveal remain inside a compact history row")
                check(button.bounds.width >= button.intrinsicContentSize.width, "Activity action labels fit without truncation")
            }
            check(activityCell.details.font!.pointSize == 13, "Activity results use legible body text")
        }
        activityCell.detailsButton.invoke()
        let activityDetails = editor.activityDetailsWindow!
        check(activityDetails.text.string.contains(longActivityMessage) && activityDetails.text.string.contains(output.path), "Details retains the entire long activity result and output location")
        check(!activityDetails.text.isEditable && activityDetails.text.isSelectable && activityDetails.window!.title == "Activity Details — UltraConvert", "Activity Details is selectable, read only and distinguished from a preview")
        activityDetails.window!.setFrame(NSRect(origin: activityDetails.window!.frame.origin, size: activityDetails.window!.minSize), display: false)
        activityDetails.window!.contentView!.layoutSubtreeIfNeeded()
        let detailsDone = activityDetails.done.convert(activityDetails.done.bounds, to: activityDetails.window!.contentView!)
        check(detailsDone.minX >= 0 && detailsDone.maxX <= activityDetails.window!.contentView!.bounds.width && detailsDone.minY >= 0, "Activity Details keeps its close action visible at minimum size")
        activityDetails.close()
        editor.refreshActivity(); runtime.activities = []
        let emptyCell = editor.tableView(editor.activityTable, viewFor: editor.activityTable.tableColumns.first, row: 7) as! ActivityCell
        check(emptyCell.reveal.isHidden && emptyCell.detailsButton.isHidden && emptyCell.accessibilityLabel() == "No files processed yet", "A stale activity row clears its old output and Details action when history shrinks")
        editor.selectedID = nil; editor.draft = WatchRule(); editor.rebuildEditor(); editor.reloadList()
        check(editor.conditions.isEmpty && editor.steps.isEmpty && editor.exampleLabels.isEmpty && !editor.save.isEnabled && editor.flowSummary.stringValue.contains("IF it matches"), "Returning to no rules clears all prior examples and editor state")
        check(["Inbox", "Match", "Actions", "Output", "Original"].allSatisfy { !button(editor, "Jump to " + $0 + " block").isEnabled }, "The flow navigator disables targets when there is no selected rule")

        var examples = rule; examples.steps = [.init(kind: .convert, value: "mp3"), .init(kind: .rename, value: "{name}-{format}-{date}")]
        check(RuleFlowExample.names(examples, date: Date(timeIntervalSince1970: 0)) == ["Example.mp3", "Example-mp3-1970-01-01.mp3"], "Live examples expand safe tokens using the action's current format")
        examples.steps.reverse()
        check(RuleFlowExample.names(examples, date: Date(timeIntervalSince1970: 0)) == ["Example-wav-1970-01-01.wav", "Example-wav-1970-01-01.mp3"], "Reordering examples retains names already produced by earlier actions")
        examples.steps = [.init(kind: .rename, value: "../unsafe")]
        check(RuleFlowExample.names(examples).first?.hasPrefix("Invalid name template") == true, "Invalid live rename examples explain the problem instead of suggesting an escaped filename")

        let source = inbox.appendingPathComponent("Original.wav"), sourceData = Data("ORIGINAL".utf8)
        try sourceData.write(to: source)
        var renameOnly = rule; renameOnly.steps = [.init(kind: .rename, value: "{name}-copy")]
        let pipeline = AutomationPipeline(engine: engine, scratch: root.appendingPathComponent("Scratch"))
        let result = try pipeline.run(source, rule: renameOnly, roots: [inbox.path], cancellation: AutomationCancellation())
        check(result.output?.lastPathComponent == "Original-copy.wav" && engine.conversions == 0, "Rename-only output does not unnecessarily invoke a converter")
        check(try Data(contentsOf: source) == sourceData && fm.fileExists(atPath: source.path) && Data(contentsOf: result.output!) == sourceData, "Rename blocks create a named output copy while preserving the original filename and contents")
        var lossless = rule; lossless.steps = [.init(kind: .convert, value: "alac"), .init(kind: .rename, value: "{name}-{format}")]
        check(RuleFlowExample.names(lossless) == ["Example.m4a", "Example-alac.m4a"], "ALAC illustrations use the actual M4A container extension while preserving the requested format token")
        let losslessPreview = try pipeline.preview(source, rule: lossless, cancellation: AutomationCancellation())
        check(losslessPreview.contains("Planned output: Original-alac.m4a"), "ALAC preview agrees with its filename illustration")
        let losslessResult = try pipeline.run(source, rule: lossless, roots: [inbox.path], cancellation: AutomationCancellation())
        check(losslessResult.output?.lastPathComponent == "Original-alac.m4a", "ALAC pipeline publishes the real container extension instead of an unsupported .alac filename")
        let nested = inbox.appendingPathComponent("Nested"); try fm.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedFile = nested.appendingPathComponent("Nested.wav"); try sourceData.write(to: nestedFile)
        rejects("Preview follows the watcher setting and refuses a subfolder when recursion is off") { _ = try pipeline.preview(nestedFile, rule: rule, cancellation: AutomationCancellation()) }
        var recursiveRule = rule; recursiveRule.recursive = true
        check(try pipeline.preview(nestedFile, rule: recursiveRule, cancellation: AutomationCancellation()).contains("Planned output: Nested.mp3"), "Enabling Include subfolders allows preview of the same nested file")
        for filename in [".hidden.wav", "incoming.part", "incoming.download"] {
            let skipped = inbox.appendingPathComponent(filename); try sourceData.write(to: skipped)
            rejects("Preview refuses the hidden and in-progress arrivals skipped by watching") { _ = try pipeline.preview(skipped, rule: rule, cancellation: AutomationCancellation()) }
            check(try Data(contentsOf: skipped) == sourceData, "Rejecting a skipped arrival preserves its bytes")
        }
        let hiddenFolder = inbox.appendingPathComponent(".Hidden Folder"), package = inbox.appendingPathComponent("Fixture.app")
        for folder in [hiddenFolder, package] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            let skipped = folder.appendingPathComponent("Hidden.wav"); try sourceData.write(to: skipped)
            rejects("Recursive preview refuses hidden-folder and package descendants skipped by the watcher") { _ = try pipeline.preview(skipped, rule: recursiveRule, cancellation: AutomationCancellation()) }
        }
        for (name, target) in [("Linked Nested", nested), ("Linked Inbox", inbox)] {
            let link = inbox.appendingPathComponent(name); try fm.createSymbolicLink(at: link, withDestinationURL: target)
            let linkedFile = link.appendingPathComponent(target == inbox ? "Original.wav" : "Nested.wav")
            rejects("Recursive preview refuses a symlink ancestor even when it resolves inside the same inbox") { _ = try pipeline.preview(linkedFile, rule: recursiveRule, cancellation: AutomationCancellation()) }
        }
        check(runtime.enabledRules.isEmpty && runtime.pendingCount == 0, "Native editor tests do not enqueue a watch-folder conversion")
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "passed": true, "actual_editor_callbacks": true, "source_preserved": true], options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}

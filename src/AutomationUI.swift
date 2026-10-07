import AppKit

final class RuleButton: NSButton {
    var invoke: () -> Void = {}
    convenience init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        invoke = action; target = self; self.action = #selector(performAction)
        bezelStyle = .rounded
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); imagePosition = .imageLeading }
        setAccessibilityLabel(title)
    }
    @objc fileprivate func performAction() { invoke() }
}
final class RulePopup: NSPopUpButton {
    var invoke: () -> Void = {}
    func changed(_ closure: @escaping () -> Void) { invoke = closure; target = self; action = #selector(performAction) }
    @objc fileprivate func performAction() { invoke() }
}
final class RuleMessageField: NSTextField {
    override var stringValue: String { didSet { toolTip = stringValue } }
}
/// Native glass around editing controls, with a neutral opaque fallback for
/// older systems and Reduce Transparency. Flow meaning comes from text labels.
final class RuleBlock: NSView {
    private(set) var usesGlass = false
    init(content: NSView, allowGlass: Bool = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) {
        super.init(frame: .zero)
        var surface: NSView?
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), allowGlass {
            let glass = NSGlassEffectView(); glass.style = .regular; glass.cornerRadius = 16
            let host = NSView(); glass.contentView = host
            pin(content, in: host, inset: 16); surface = glass; usesGlass = true
        }
        #endif
        if surface == nil {
            let card = RoundedCard(); pin(content, in: card, inset: 16); surface = card
        }
        pin(surface!, in: self, inset: 0)
        heightAnchor.constraint(equalTo: content.heightAnchor, constant: 32).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class FolderRulesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let runtime: FolderAutomation
    let table = NSTableView()
    let body = NSStackView()
    let activityTable = NSTableView()
    let editorScroll = NSScrollView()
    let activityScroll = NSScrollView()
    let stateLabel = NSTextField(wrappingLabelWithString: "")
    let message = RuleMessageField(wrappingLabelWithString: "Choose a template or create a rule. Rules stay off until you save and enable them.")
    let pause = RuleButton()
    let save = RuleButton()
    let test = RuleButton()
    let name = NSTextField()
    let enabled = NSButton(checkboxWithTitle: "Enable this rule after saving", target: nil, action: nil)
    let recursive = NSButton(checkboxWithTitle: "Include subfolders", target: nil, action: nil)
    let acknowledge = NSButton(checkboxWithTitle: "I allow originals to leave the inbox after successful output", target: nil, action: nil)
    let settle = NSPopUpButton()
    let matching = NSPopUpButton()
    let policy = RulePopup()
    var selectedID: UUID?
    var draft = WatchRule()
    var conditions: [(MatchField, NSControl)] = []
    var steps: [(StepKind, NSControl)] = []
    var activityCount = -1
    var activityDate: Date?
    var onClose: (() -> Void)?
    var ruleTools: [NSButton] = []

    init(runtime: FolderAutomation) {
        self.runtime = runtime
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 750), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Folder Rules — UltraConvert"; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 900, height: 620); window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let main = NSStackView(); main.orientation = .vertical; main.alignment = .leading; main.spacing = 16
        main.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(main)
        NSLayoutConstraint.activate([main.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), main.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), main.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18), main.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18)])
        let titles = vertical([uiLabel("Folder Rules", size: 25, weight: .semibold), uiLabel("Build a flow. New files do the rest.", size: 12, color: .secondaryLabelColor)])
        pause.title = "Pause All"; pause.bezelStyle = .rounded; pause.target = pause; pause.action = #selector(RuleButton.performAction)
        pause.invoke = { [weak self] in guard let self else { return }; self.runtime.setPaused(!self.runtime.paused); self.refreshStatus() }
        let settings = RuleButton("Startup & Finder…", symbol: "gearshape", action: { (NSApp.delegate as? ConverterApp)?.showSettings() })
        let header = horizontal([titles, NSView(), settings, pause]); full(header, in: main)
        stateLabel.font = .systemFont(ofSize: 12, weight: .medium); stateLabel.setAccessibilityLabel("Folder watcher status"); full(stateLabel, in: main)
        let area = NSStackView(); area.orientation = .horizontal; area.alignment = .top; area.spacing = 20; full(area, in: main)
        area.setContentHuggingPriority(.defaultLow, for: .vertical)
        let sidebar = vertical([]); sidebar.spacing = 10; sidebar.widthAnchor.constraint(equalToConstant: 220).isActive = true
        full(uiLabel("RULES · FIRST MATCH WINS", size: 10, weight: .semibold, color: .secondaryLabelColor), in: sidebar)
        let new = RulePopup(); new.addItem(withTitle: "＋ New Rule…")
        for title in ["Blank rule", "Audio → MP3", "Images → WebP", "Data → YAML"] { new.addItem(withTitle: title) }
        new.changed { [weak self, weak new] in guard let self, let new, new.indexOfSelectedItem > 0 else { return }; self.newRule(template: new.indexOfSelectedItem); new.selectItem(at: 0) }
        full(new, in: sidebar)
        let list = NSScrollView(); list.hasVerticalScroller = true; list.autohidesScrollers = true; list.borderType = .noBorder
        let column = NSTableColumn(identifier: .init("rules")); column.width = 215; table.addTableColumn(column); table.headerView = nil; table.rowHeight = 49
        table.dataSource = self; table.delegate = self; table.style = .sourceList; table.setAccessibilityLabel("Folder rule priority list")
        list.documentView = table; full(list, in: sidebar)
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let tools = horizontal([RuleButton("Duplicate", action: { [weak self] in self?.duplicate() }), RuleButton("Remove", action: { [weak self] in self?.remove() })]); full(tools, in: sidebar)
        let order = horizontal([RuleButton("Move Up", symbol: "arrow.up", action: { [weak self] in self?.reorder(-1) }), RuleButton("Move Down", symbol: "arrow.down", action: { [weak self] in self?.reorder(1) })]); full(order, in: sidebar)
        ruleTools = (tools.arrangedSubviews + order.arrangedSubviews).compactMap { $0 as? NSButton }
        full(uiLabel("Closing the converter keeps enabled rules running. Quit UltraConvert to stop them. Files already present when watching starts are ignored.", size: 11, color: .secondaryLabelColor), in: sidebar)
        area.addArrangedSubview(sidebar)
        let right = vertical([]); right.spacing = 12; area.addArrangedSubview(right)
        right.widthAnchor.constraint(equalTo: area.widthAnchor, constant: -240).isActive = true
        let tabs = NSSegmentedControl(labels: ["Rule Builder", "Activity"], trackingMode: .selectOne, target: self, action: #selector(changeTab(_:))); tabs.selectedSegment = 0; tabs.setAccessibilityLabel("Folder rules view")
        full(tabs, in: right)
        setupScroll(editorScroll, stack: body)
        activityScroll.hasVerticalScroller = true; activityScroll.autohidesScrollers = true; activityScroll.drawsBackground = false
        let activityColumn = NSTableColumn(identifier: .init("activity")); activityColumn.width = 700; activityColumn.minWidth = 400; activityTable.addTableColumn(activityColumn)
        activityTable.headerView = nil; activityTable.rowHeight = 90; activityTable.style = .fullWidth; activityTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        activityTable.dataSource = self; activityTable.delegate = self; activityTable.setAccessibilityLabel("Last 200 local folder-rule outcomes")
        activityScroll.documentView = activityTable
        full(editorScroll, in: right); full(activityScroll, in: right); activityScroll.isHidden = true
        editorScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true; activityScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        message.font = .systemFont(ofSize: 12); message.isSelectable = true; message.maximumNumberOfLines = 4; message.lineBreakMode = .byTruncatingTail; message.setAccessibilityLabel("Rule editor result"); full(message, in: right)
        save.title = "Save Rule"; save.bezelStyle = .rounded; save.target = save; save.action = #selector(RuleButton.performAction); save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
        save.invoke = { [weak self] in self?.saveRule() }
        test.title = "Test a File…"; test.bezelStyle = .rounded; test.target = test; test.action = #selector(RuleButton.performAction); test.invoke = { [weak self] in self?.testFile() }
        let existing = RuleButton("Run Existing Files…", action: { [weak self] in self?.runExisting() })
        let footer = horizontal([test, existing, NSView(), save]); full(RuleBlock(content: footer), in: right)
        NSLayoutConstraint.activate([area.heightAnchor.constraint(equalTo: main.heightAnchor, constant: -112), sidebar.heightAnchor.constraint(equalTo: area.heightAnchor), right.heightAnchor.constraint(equalTo: area.heightAnchor)])
        if let first = runtime.rules.first { selectedID = first.id; draft = first }
        rebuildEditor(); reloadList(); refreshStatus(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func vertical(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8; return stack }
    func horizontal(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = 8; return stack }
    func full(_ view: NSView, in stack: NSStackView) { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    func setupScroll(_ scroll: NSScrollView, stack: NSStackView) {
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let canvas = FlippedView(); canvas.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = canvas
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(stack)
        NSLayoutConstraint.activate([canvas.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 2), stack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -10)])
    }
    func block(_ title: String, subtitle: String? = nil, views: [NSView]) {
        let contents = vertical([uiLabel(title, size: 13, weight: .semibold)] + (subtitle.map { [uiLabel($0, size: 11, color: .secondaryLabelColor)] } ?? []) + views)
        for view in contents.arrangedSubviews { view.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true }
        full(RuleBlock(content: contents), in: body)
    }
    func popup(_ entries: [(String, String)], selected: String) -> NSPopUpButton {
        let popup = NSPopUpButton()
        for (title, value) in entries { popup.addItem(withTitle: title); popup.lastItem?.representedObject = value }
        if let item = popup.itemArray.first(where: { $0.representedObject as? String == selected }) { popup.select(item) }
        return popup
    }
    func formatPopup(_ selected: String) -> NSPopUpButton { popup(FormatCatalog.groups.flatMap { group in group.formats.map { (group.title + " · " + $0.uppercased(), $0) } }, selected: selected) }
    func folderRow(_ path: String, label: String, choose: @escaping (String) -> Void) -> NSView {
        let text = uiLabel(path.isEmpty ? "Choose a folder…" : path, size: 12, color: path.isEmpty ? .secondaryLabelColor : .labelColor)
        text.isSelectable = true; text.lineBreakMode = .byTruncatingMiddle; text.maximumNumberOfLines = 2; text.toolTip = path; text.setAccessibilityLabel(label + ": " + path)
        let button = RuleButton("Choose…", symbol: "folder", action: { [weak self] in
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.message = label
            if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
            if panel.runModal() == .OK, let url = panel.url { self?.gather(); choose(url.path); self?.rebuildEditor() }
        })
        return horizontal([text, button])
    }
    func rebuildEditor() {
        for view in body.arrangedSubviews { body.removeArrangedSubview(view); view.removeFromSuperview() }
        conditions = []; steps = []
        save.isEnabled = selectedID != nil; test.isEnabled = selectedID != nil
        guard selectedID != nil else {
            block("Make your first flow", subtitle: "Choose Audio → MP3, Images → WebP or Data → YAML on the left. Pick two folders, test a file, then enable your rule.", views: [uiLabel("WHEN a file arrives → IF it matches → THEN run your blocks → SAVE the result", size: 13, weight: .medium)])
            return
        }
        name.stringValue = draft.name; name.placeholderString = "Rule name"; name.setAccessibilityLabel("Rule name")
        enabled.state = draft.enabled ? .on : .off
        full(name, in: body); full(enabled, in: body)
        recursive.state = draft.recursive ? .on : .off
        settle.removeAllItems(); for value in [2, 3, 5, 10, 30, 60, 120] { settle.addItem(withTitle: "Wait \(value) seconds after last change"); settle.lastItem?.representedObject = Double(value) }
        settle.select(settle.itemArray.first(where: { $0.representedObject as? Double == draft.settleSeconds }) ?? settle.itemArray[1])
        block("WHEN · A new file arrives", subtitle: "Existing files are ignored at start. Hidden, temporary and linked files are skipped.", views: [folderRow(draft.inputFolder, label: "Watch this inbox", choose: { [weak self] in self?.draft.inputFolder = $0 }), horizontal([recursive, settle])])
        matching.removeAllItems(); matching.addItems(withTitles: ["Match ALL conditions", "Match ANY condition"]); matching.selectItem(at: draft.matchAll ? 0 : 1)
        var conditionViews: [NSView] = [matching]
        for (index, condition) in draft.conditions.enumerated() {
            let field = RulePopup(); for choice in MatchField.allCases { field.addItem(withTitle: choice.title); field.lastItem?.representedObject = choice.rawValue }; field.selectItem(at: MatchField.allCases.firstIndex(of: condition.field)!)
            field.changed { [weak self, weak field] in guard let self, let field, let value = field.selectedItem?.representedObject as? String, let kind = MatchField(rawValue: value) else { return }; self.gather(); self.draft.conditions[index] = .init(field: kind, value: kind == .format ? "mp3" : kind == .category ? "audio" : ""); self.rebuildEditor() }
            let value: NSControl
            if condition.field == .format { value = formatPopup(condition.value.lowercased()) }
            else if condition.field == .category { value = popup(FormatCatalog.groups.map { ($0.title, $0.id) }, selected: condition.value.lowercased()) }
            else { let text = NSTextField(string: condition.value); text.placeholderString = "Case-insensitive text"; value = text }
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            value.setAccessibilityLabel(condition.field.title + " value"); conditions.append((condition.field, value))
            let remove = RuleButton("−", action: { [weak self] in self?.gather(); self?.draft.conditions.remove(at: index); self?.rebuildEditor() }); remove.setAccessibilityLabel("Remove condition \(index + 1)"); remove.isEnabled = draft.conditions.count > 1
            conditionViews.append(horizontal([field, value, remove]))
        }
        let addCondition = RuleButton("Add Condition", symbol: "plus", action: { [weak self] in self?.gather(); self?.draft.conditions.append(.init()); self?.rebuildEditor() }); addCondition.isEnabled = draft.conditions.count < 12; conditionViews.append(addCondition)
        block("IF · The file matches", subtitle: "File formats are detected from content before rules run. Conditions use that detected format.", views: conditionViews)
        for (index, step) in draft.steps.enumerated() {
            let value: NSControl = step.kind == .convert ? formatPopup(step.value) : NSTextField(string: step.value)
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if let text = value as? NSTextField { text.placeholderString = "{name}-{format}" }
            value.setAccessibilityLabel(step.kind == .convert ? "Action \(index + 1) output format" : "Action \(index + 1) rename template"); steps.append((step.kind, value))
            let up = RuleButton("↑", action: { [weak self] in self?.moveStep(index, -1) }); up.isEnabled = index > 0; up.setAccessibilityLabel("Move action \(index + 1) up")
            let down = RuleButton("↓", action: { [weak self] in self?.moveStep(index, 1) }); down.isEnabled = index + 1 < draft.steps.count; down.setAccessibilityLabel("Move action \(index + 1) down")
            let remove = RuleButton("−", action: { [weak self] in self?.gather(); self?.draft.steps.remove(at: index); self?.rebuildEditor() }); remove.isEnabled = draft.steps.count > 1; remove.setAccessibilityLabel("Remove action \(index + 1)")
            block("THEN \(index + 1) · " + (step.kind == .convert ? "Convert" : "Rename output"), subtitle: step.kind == .rename ? "Filename without extension. Tokens: {name}, {format}, {date}. Original names stay unchanged." : "Steps run in order. Another conversion can consume a single-file result.", views: [horizontal([value, up, down, remove])])
        }
        let add = RulePopup(); add.addItems(withTitles: ["＋ Add Action…", "Convert to a format", "Rename output"]); add.isEnabled = draft.steps.count < 8
        add.changed { [weak self, weak add] in guard let self, let add, add.indexOfSelectedItem > 0 else { return }; self.gather(); self.draft.steps.append(.init(kind: add.indexOfSelectedItem == 1 ? .convert : .rename, value: add.indexOfSelectedItem == 1 ? "mp3" : "{name}-{format}")); self.rebuildEditor() }; full(add, in: body)
        block("SAVE · Route the result", subtitle: "Choose a folder outside all watched inboxes. Name collisions get a numbered suffix. Companion files stay together.", views: [folderRow(draft.destination, label: "Save converted results here", choose: { [weak self] in self?.draft.destination = $0 })])
        policy.removeAllItems(); for (title, value) in [("Keep the original", "keep"), ("Move the original to archive", "archive"), ("Send the original to Trash", "trash")] { policy.addItem(withTitle: title); policy.lastItem?.representedObject = value }; policy.selectItem(at: OriginalPolicy.allCases.firstIndex(of: draft.originalPolicy)!)
        policy.changed { [weak self] in self?.gather(); self?.rebuildEditor() }
        var originalViews: [NSView] = [policy]
        if draft.originalPolicy == .archive { originalViews.append(folderRow(draft.archiveFolder, label: "Archive originals here", choose: { [weak self] in self?.draft.archiveFolder = $0 })) }
        if draft.originalPolicy != .keep { acknowledge.state = draft.acknowledgedRemoval ? .on : .off; originalViews.append(acknowledge) }
        block("AFTER SUCCESS · Original file", subtitle: "Failure, cancellation or a changed source always keeps the original. Geospatial and document originals must be kept because they may have companion files.", views: originalViews)
    }
    func gather() {
        guard selectedID != nil else { return }
        draft.name = name.stringValue; draft.enabled = enabled.state == .on; draft.recursive = recursive.state == .on; draft.settleSeconds = settle.selectedItem?.representedObject as? Double ?? 3; draft.matchAll = matching.indexOfSelectedItem == 0
        draft.conditions = conditions.map { field, control in .init(field: field, value: (control as? NSPopUpButton)?.selectedItem?.representedObject as? String ?? (control as? NSTextField)?.stringValue ?? "") }
        draft.steps = steps.map { kind, control in .init(kind: kind, value: (control as? NSPopUpButton)?.selectedItem?.representedObject as? String ?? (control as? NSTextField)?.stringValue ?? "") }
        draft.originalPolicy = OriginalPolicy(rawValue: policy.selectedItem?.representedObject as? String ?? "keep") ?? .keep
        draft.acknowledgedRemoval = acknowledge.state == .on
    }
    func saveRule() {
        gather(); guard let index = runtime.rules.firstIndex(where: { $0.id == selectedID }) else { return }
        var next = runtime.rules; next[index] = draft
        do { try runtime.save(next); message.textColor = .secondaryLabelColor; message.stringValue = draft.enabled ? "Saved and watching. Only new or changed files arriving from now on will run." : "Draft saved. Turn on Enable this rule, then save to start watching."; reloadList() }
        catch { message.textColor = .systemRed; message.stringValue = error.localizedDescription }
    }
    func newRule(template: Int) {
        guard mayDiscard() else { return }
        var rule = WatchRule()
        if template > 1 {
            let choice = [("Audio → MP3", "audio", "mp3"), ("Images → WebP", "image", "webp"), ("Data → YAML", "config", "yaml")][template - 2]
            rule.name = choice.0; rule.conditions = [.init(field: .category, value: choice.1)]; rule.steps = [.init(kind: .convert, value: choice.2)]
        }
        do { try runtime.save(runtime.rules + [rule]); selectedID = rule.id; draft = rule; rebuildEditor(); reloadList(); message.stringValue = "Choose an inbox and an output folder. Test a file before enabling." }
        catch { message.stringValue = error.localizedDescription }
    }
    func mayDiscard() -> Bool {
        gather()
        guard let saved = runtime.rules.first(where: { $0.id == selectedID }), saved != draft else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to this rule?"; alert.informativeText = "Your edits have not been saved."; alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func duplicate() {
        guard selectedID != nil, mayDiscard() else { return }
        var rule = draft; rule.id = UUID(); rule.name = String((rule.name + " copy").prefix(100)); rule.enabled = false
        do { try runtime.save(runtime.rules + [rule]); selectedID = rule.id; draft = rule; rebuildEditor(); reloadList() } catch { message.stringValue = error.localizedDescription }
    }
    func remove() {
        guard let id = selectedID else { return }
        let alert = NSAlert(); alert.messageText = "Remove this folder rule?"; alert.informativeText = "This removes its configuration and stops its queued work. Files and completed results are kept."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Remove Rule")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try runtime.save(runtime.rules.filter { $0.id != id }); selectedID = runtime.rules.first?.id; draft = runtime.rules.first ?? WatchRule(); rebuildEditor(); reloadList(); message.stringValue = "Rule removed. Files and completed results were kept." } catch { message.stringValue = error.localizedDescription }
    }
    func reorder(_ delta: Int) {
        guard mayDiscard(), let index = runtime.rules.firstIndex(where: { $0.id == selectedID }), runtime.rules.indices.contains(index + delta) else { return }
        var next = runtime.rules; next.swapAt(index, index + delta)
        do { try runtime.save(next); reloadList() } catch { message.stringValue = error.localizedDescription }
    }
    func moveStep(_ index: Int, _ delta: Int) { gather(); draft.steps.swapAt(index, index + delta); rebuildEditor() }
    func testFile() {
        gather(); let rule = draft
        do { try rule.validate(roots: runtime.enabledRules.map(\.inputFolder) + [rule.inputFolder]) } catch { message.stringValue = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.message = "Test matching and preview this rule. No files will change."; panel.directoryURL = URL(fileURLWithPath: rule.inputFolder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        test.isEnabled = false; message.stringValue = "Checking content and building a read-only plan…"
        let factory = runtime.engine, scratch = runtime.store.url("Staging")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text: String
            do { text = try AutomationPipeline(engine: factory(), scratch: scratch).preview(url, rule: rule, cancellation: AutomationCancellation()) } catch { text = error.localizedDescription }
            DispatchQueue.main.async { self?.test.isEnabled = true; self?.message.stringValue = text }
        }
    }
    func runExisting() {
        guard !runtime.enabledRules.isEmpty, !runtime.paused else { message.stringValue = "Enable and save a rule first, then resume watching."; return }
        let alert = NSAlert(); alert.messageText = "Run enabled rules on existing files?"; alert.informativeText = "This queues up to 1,000 files already in your inboxes. Saved original-file actions also apply. Normal watching only handles new or changed arrivals."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Run Existing Files")
        if alert.runModal() == .alertSecondButtonReturn { runtime.runExisting(); message.stringValue = "Existing files queued using saved rules." }
    }
    @objc func changeTab(_ sender: NSSegmentedControl) { editorScroll.isHidden = sender.selectedSegment == 1; activityScroll.isHidden = sender.selectedSegment == 0; if sender.selectedSegment == 1 { refreshActivity() } }
    func refreshStatus() { stateLabel.stringValue = runtime.status; pause.title = runtime.paused ? "Resume All" : "Pause All"; pause.isEnabled = !runtime.enabledRules.isEmpty; if !activityScroll.isHidden { refreshActivity() } }
    func refreshActivity() {
        guard activityCount != runtime.activities.count || activityDate != runtime.activities.last?.date else { return }
        activityCount = runtime.activities.count; activityDate = runtime.activities.last?.date
        activityTable.reloadData()
    }
    func reloadList() {
        let selectedIndex = runtime.rules.firstIndex(where: { $0.id == selectedID })
        for button in ruleTools { button.isEnabled = selectedIndex != nil }
        if ruleTools.count == 4 { ruleTools[2].isEnabled = (selectedIndex ?? 0) > 0; ruleTools[3].isEnabled = selectedIndex.map { $0 + 1 < runtime.rules.count } ?? false }
        table.reloadData(); if let index = runtime.rules.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) } }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView == activityTable ? max(1, runtime.activities.count) : runtime.rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == activityTable {
            let identifier = NSUserInterfaceItemIdentifier("automationActivityCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ActivityCell ?? ActivityCell()
            cell.identifier = identifier
            if runtime.activities.isEmpty { cell.configure(nil) }
            else { cell.configure(runtime.activities[runtime.activities.count - 1 - row]) }
            return cell
        }
        let rule = runtime.rules[row]; let text = NSTextField(wrappingLabelWithString: rule.name + "\n" + (rule.enabled ? "Enabled" : "Draft · off")); text.font = .systemFont(ofSize: 12); text.maximumNumberOfLines = 2; text.setAccessibilityLabel(rule.name + ", " + (rule.enabled ? "enabled" : "disabled")); return text
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { tableView == activityTable || runtime.rules[row].id == selectedID || mayDiscard() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { mayDiscard() }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === table, runtime.rules.indices.contains(table.selectedRow), runtime.rules[table.selectedRow].id != selectedID else { return }
        selectedID = runtime.rules[table.selectedRow].id; draft = runtime.rules[table.selectedRow]; rebuildEditor(); reloadList(); message.stringValue = "Edit blocks, test a file, then save. Changes take effect after saving."
    }
}

/// Reuse only visible history rows; hundreds of per-row glass effects and
/// full-stack rebuilding would waste memory and frame time during bulk work.
final class ActivityCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let details = NSTextField(wrappingLabelWithString: "")
    let reveal = RuleButton()
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .semibold); title.lineBreakMode = .byTruncatingMiddle
        details.font = .systemFont(ofSize: 11); details.textColor = .secondaryLabelColor; details.maximumNumberOfLines = 3; details.isSelectable = true
        let text = NSStackView(views: [title, details]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 4
        reveal.title = "Reveal"; reveal.bezelStyle = .rounded; reveal.target = reveal; reveal.action = #selector(RuleButton.performAction)
        text.translatesAutoresizingMaskIntoConstraints = false; reveal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text); addSubview(reveal)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: reveal.leadingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            text.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            reveal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            reveal.widthAnchor.constraint(equalToConstant: 72),
            reveal.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        title.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true; details.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ event: AutomationActivity?) {
        guard let event else { title.stringValue = "No files processed yet"; details.stringValue = "Test your rule, then add a new file to its inbox. Activity stays local; the last 200 outcomes are retained."; reveal.isHidden = true; return }
        title.stringValue = event.file
        let date = DateFormatter.localizedString(from: event.date, dateStyle: .short, timeStyle: .short)
        details.stringValue = event.rule + " · " + date + "\n" + event.message; details.toolTip = event.message
        reveal.isHidden = event.output == nil; reveal.setAccessibilityLabel("Reveal output for " + event.file)
        reveal.invoke = { if let output = event.output { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output)]) } }
        setAccessibilityLabel(event.file + ", " + event.message)
    }
}

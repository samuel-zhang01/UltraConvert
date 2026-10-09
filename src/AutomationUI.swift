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

final class FolderRulesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate {
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
    let cancelTest = RuleButton()
    let viewPreviewDetails = RuleButton()
    let existing = RuleButton()
    let setupGuide = NSTextField(wrappingLabelWithString: "1. Choose a template.\n2. Pick an inbox and a separate output folder.\n3. Preview a file; nothing changes.\n4. Enable and Save Rule.")
    let editingStatus = NSTextField(wrappingLabelWithString: "")
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
    let flowSummary = NSTextField(wrappingLabelWithString: "Choose a template to build your first flow.")
    var exampleLabels: [NSTextField] = []
    let branchStatus = NSTextField(wrappingLabelWithString: "Preview a file to see which path it takes.")
    private(set) var flowRevision = 0
    private let flowSession = UUID().uuidString
    var showsArrivalOptions = false
    var flowNodes: [String: NSView] = [:]
    var actionPaletteButtons: [NSButton] = []
    var navigationButtons: [NSButton] = []
    var viewTabs: NSSegmentedControl?
    private var reloadingList = false
    var activityCount = -1
    var activityDate: Date?
    var onClose: (() -> Void)?
    var ruleTools: [NSButton] = []
    private var previewID: UUID?
    private var previewCancellation: AutomationCancellation?
    private var detailsRule: WatchRule?
    private(set) var previewDetails: String?
    private(set) var previewDetailsWindow: RulePreviewDetails?
    var previewRunning: Bool { previewID != nil }
    private(set) var previewWorkCount = 0
    var onPreviewFinished: (() -> Void)?

    init(runtime: FolderAutomation) {
        self.runtime = runtime
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 750), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Folder Rules — UltraConvert"; window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 900, height: 620); window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let main = NSStackView(); main.orientation = .vertical; main.alignment = .leading; main.spacing = 16
        main.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(main)
        NSLayoutConstraint.activate([main.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), main.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), main.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18), main.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18)])
        let titles = vertical([uiLabel("Folder Rules", size: 25, weight: .semibold), uiLabel("Snap together a flow. Let new files do the rest.", size: 12, color: .secondaryLabelColor)])
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
        setupGuide.font = .systemFont(ofSize: 11); setupGuide.textColor = .secondaryLabelColor; setupGuide.setAccessibilityLabel("Folder rule setup checklist")
        full(setupGuide, in: sidebar)
        let palette = horizontal([RuleButton("Convert", symbol: "plus", action: { [weak self] in self?.addStep(.convert) }), RuleButton("Rename", symbol: "plus", action: { [weak self] in self?.addStep(.rename) })])
        actionPaletteButtons = palette.arrangedSubviews.compactMap { $0 as? NSButton }
        for button in actionPaletteButtons { button.setAccessibilityLabel("Add " + button.title + " action") }
        full(uiLabel("ADD AN ACTION BLOCK", size: 10, weight: .semibold, color: .secondaryLabelColor), in: sidebar); full(palette, in: sidebar)
        let list = NSScrollView(); list.hasVerticalScroller = true; list.autohidesScrollers = true; list.borderType = .noBorder
        let column = NSTableColumn(identifier: .init("rules")); column.width = 215; table.addTableColumn(column); table.headerView = nil; table.rowHeight = 49
        table.dataSource = self; table.delegate = self; table.style = .sourceList; table.allowsEmptySelection = false; table.setAccessibilityLabel("Folder rule priority list")
        list.documentView = table; full(list, in: sidebar)
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 145).isActive = true
        let tools = horizontal([RuleButton("Duplicate", action: { [weak self] in self?.duplicate() }), RuleButton("Remove", action: { [weak self] in self?.remove() })]); full(tools, in: sidebar)
        let order = horizontal([RuleButton("Move Up", symbol: "arrow.up", action: { [weak self] in self?.reorder(-1) }), RuleButton("Move Down", symbol: "arrow.down", action: { [weak self] in self?.reorder(1) })]); full(order, in: sidebar)
        ruleTools = (tools.arrangedSubviews + order.arrangedSubviews).compactMap { $0 as? NSButton }
        full(uiLabel("Closing the converter keeps enabled rules running. Quit UltraConvert to stop them. Files already present when watching starts are ignored.", size: 11, color: .secondaryLabelColor), in: sidebar)
        area.addArrangedSubview(sidebar)
        let right = vertical([]); right.spacing = 12; area.addArrangedSubview(right)
        right.widthAnchor.constraint(equalTo: area.widthAnchor, constant: -240).isActive = true
        let tabs = NSSegmentedControl(labels: ["Rule Builder", "Activity"], trackingMode: .selectOne, target: self, action: #selector(changeTab(_:))); tabs.selectedSegment = 0; tabs.setAccessibilityLabel("Folder rules view"); viewTabs = tabs
        full(tabs, in: right)
        flowSummary.font = .systemFont(ofSize: 12, weight: .medium); flowSummary.maximumNumberOfLines = 3
        flowSummary.setAccessibilityLabel("Live flow summary"); full(flowSummary, in: right)
        let navigation = horizontal([])
        for (key, title) in [("WHEN", "Inbox"), ("IF", "Match"), ("DO", "Actions"), ("SAVE", "Output"), ("AFTER", "Original")] {
            if !navigation.arrangedSubviews.isEmpty { navigation.addArrangedSubview(uiLabel("→", size: 11, color: .secondaryLabelColor)) }
            let button = RuleButton(title, action: { [weak self] in self?.jumpToBlock(key) }); button.identifier = .init(key); button.setAccessibilityLabel("Jump to " + title + " block"); navigationButtons.append(button); navigation.addArrangedSubview(button)
        }
        navigation.addArrangedSubview(NSView()); full(navigation, in: right)
        setupScroll(editorScroll, stack: body)
        activityScroll.hasVerticalScroller = true; activityScroll.autohidesScrollers = true; activityScroll.drawsBackground = false
        let activityColumn = NSTableColumn(identifier: .init("activity")); activityColumn.width = 700; activityColumn.minWidth = 400; activityTable.addTableColumn(activityColumn)
        activityTable.headerView = nil; activityTable.rowHeight = 90; activityTable.style = .fullWidth; activityTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        activityTable.dataSource = self; activityTable.delegate = self; activityTable.setAccessibilityLabel("Last 200 local folder-rule outcomes")
        activityScroll.documentView = activityTable
        full(editorScroll, in: right); full(activityScroll, in: right); activityScroll.isHidden = true
        editorScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true; activityScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        message.font = .systemFont(ofSize: 12); message.isSelectable = true; message.maximumNumberOfLines = 4; message.lineBreakMode = .byTruncatingTail; message.setAccessibilityLabel("Rule editor result"); full(message, in: right)
        message.heightAnchor.constraint(lessThanOrEqualToConstant: 62).isActive = true
        message.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        save.title = "Save Rule"; save.bezelStyle = .rounded; save.target = save; save.action = #selector(RuleButton.performAction); save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
        save.invoke = { [weak self] in self?.saveRule() }
        test.title = "Preview a File…"; test.bezelStyle = .rounded; test.target = test; test.action = #selector(RuleButton.performAction); test.invoke = { [weak self] in self?.testFile() }; test.toolTip = "Recognise one inbox file and show this rule's plan. No files change or convert."
        cancelTest.title = "Cancel Preview"; cancelTest.bezelStyle = .rounded; cancelTest.target = cancelTest; cancelTest.action = #selector(RuleButton.performAction); cancelTest.isHidden = true
        cancelTest.keyEquivalent = "\u{1b}"
        cancelTest.keyEquivalentModifierMask = []
        cancelTest.invoke = { [weak self] in self?.cancelPreview(); self?.message.textColor = .secondaryLabelColor; self?.message.stringValue = "Preview cancelled. No files changed." }
        viewPreviewDetails.title = "View Preview Details…"; viewPreviewDetails.bezelStyle = .rounded; viewPreviewDetails.target = viewPreviewDetails; viewPreviewDetails.action = #selector(RuleButton.performAction); viewPreviewDetails.invoke = { [weak self] in self?.showPreviewDetails() }; viewPreviewDetails.isEnabled = false; viewPreviewDetails.toolTip = "Read the full plan, including output and original-file locations."
        full(horizontal([viewPreviewDetails, NSView()]), in: right)
        existing.title = "Run Existing Files…"; existing.bezelStyle = .rounded; existing.target = existing; existing.action = #selector(RuleButton.performAction); existing.invoke = { [weak self] in self?.runExisting() }
        let footer = horizontal([test, cancelTest, existing, NSView(), save]); full(RuleBlock(content: footer), in: right)
        for control in [enabled, recursive, acknowledge, settle, matching] as [NSControl] { control.target = self; control.action = #selector(editorControlChanged(_:)) }
        name.delegate = self
        editingStatus.font = .systemFont(ofSize: 11); editingStatus.textColor = .secondaryLabelColor; editingStatus.setAccessibilityLabel("Rule edit status")
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
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(stack)
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
        else { popup.addItem(withTitle: "Unavailable: " + selected); popup.lastItem?.representedObject = selected; popup.selectItem(at: popup.numberOfItems - 1) }
        popup.target = self; popup.action = #selector(editorControlChanged(_:))
        return popup
    }
    func formatPopup(_ selected: String) -> NSPopUpButton {
        let control = popup(FormatCatalog.groups.flatMap { group in group.formats.map { (group.title + " · " + $0.uppercased(), $0) } }, selected: selected)
        control.toolTip = "Choose a format. Preview a real file to check that this conversion is supported."
        return control
    }
    func folderRow(_ path: String, label: String, choose: @escaping (String) -> Void) -> NSView {
        let text = uiLabel(path.isEmpty ? "Choose a folder…" : path, size: 12, color: path.isEmpty ? .secondaryLabelColor : .labelColor)
        text.isSelectable = true; text.lineBreakMode = .byTruncatingMiddle; text.maximumNumberOfLines = 2; text.toolTip = path; text.setAccessibilityLabel(label + ": " + path)
        let button = RuleButton(path.isEmpty ? "Choose Folder…" : "Change…", symbol: "folder", action: { [weak self] in
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.message = label
            if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
            if panel.runModal() == .OK, let url = panel.url { self?.gather(); choose(url.path); self?.rebuildEditor() }
        })
        button.setAccessibilityLabel(label + " — choose folder")
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return horizontal([text, button])
    }
    @discardableResult
    func puzzle(_ title: String, symbol: String, tone: FlowTone, views: [NSView]) -> RulePuzzleBlock {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = tone.color; icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let heading = horizontal([icon, uiLabel(title, size: 14, weight: .semibold), NSView()])
        let contents = vertical([heading] + views); contents.spacing = 8
        for view in contents.arrangedSubviews { view.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true }
        let piece = RulePuzzleBlock(content: contents, tone: tone)
        if let previous = body.arrangedSubviews.last as? RulePuzzleBlock { body.setCustomSpacing(-20, after: previous) }
        full(piece, in: body)
        let key = title.components(separatedBy: " ").first ?? ""
        if flowNodes[key] == nil { flowNodes[key] = piece }
        return piece
    }
    func rebuildEditor(resetScroll: Bool = false) {
        let offset = resetScroll ? NSPoint.zero : editorScroll.contentView.bounds.origin
        window?.makeFirstResponder(nil)
        cancelPreview(); flowRevision += 1
        for view in body.arrangedSubviews { body.removeArrangedSubview(view); view.removeFromSuperview() }
        conditions = []; steps = []; exampleLabels = []; flowNodes = [:]
        for button in navigationButtons { button.isEnabled = false }
        for button in actionPaletteButtons { button.isEnabled = selectedID != nil && draft.steps.count < 8 }
        save.isEnabled = selectedID != nil; test.isEnabled = selectedID != nil && previewWorkCount == 0
        guard selectedID != nil else {
            puzzle("Your first flow starts here", symbol: "sparkles", tone: .arrival, views: [uiLabel("Pick a template, then choose two folders. Preview a file before turning the flow on.", size: 13), horizontal([RuleButton("Audio → MP3", action: { [weak self] in self?.newRule(template: 2) }), RuleButton("Images → WebP", action: { [weak self] in self?.newRule(template: 3) }), RuleButton("Blank Flow", action: { [weak self] in self?.newRule(template: 1) })])])
            flowSummary.stringValue = "WHEN a file arrives → IF it matches → DO your actions → SAVE a new result"
            return
        }
        let revision = flowRevision
        name.stringValue = draft.name; name.placeholderString = "Give your flow a name"; name.setAccessibilityLabel("Rule name")
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        enabled.state = draft.enabled ? .on : .off
        let intro = vertical([name, horizontal([enabled, NSView()]), editingStatus]); intro.spacing = 7
        full(RuleBlock(content: intro), in: body)
        recursive.state = draft.recursive ? .on : .off
        settle.removeAllItems()
        let intervals = Array(Set([2.0, 3, 5, 10, 30, 60, 120, draft.settleSeconds].filter { $0.isFinite && $0 >= 2 && $0 <= 120 })).sorted()
        for value in intervals { settle.addItem(withTitle: "Wait \(value.formatted()) seconds after last change"); settle.lastItem?.representedObject = value }
        if let selected = settle.itemArray.first(where: { $0.representedObject as? Double == draft.settleSeconds }) { settle.select(selected) }
        else { settle.addItem(withTitle: "Invalid wait: \(draft.settleSeconds)"); settle.lastItem?.representedObject = draft.settleSeconds; settle.selectItem(at: settle.numberOfItems - 1) }
        settle.setAccessibilityLabel("Wait for the file to stop changing"); settle.toolTip = "The wait starts over whenever a file changes, allowing incoming copies to settle before conversion."
        let options = RuleButton(showsArrivalOptions ? "Hide Arrival Options" : "Arrival Options…", symbol: "slider.horizontal.3", action: { [weak self] in
            guard let self, self.flowRevision == revision else { return }; self.gather(); self.showsArrivalOptions.toggle(); self.rebuildEditor()
        })
        var arrival: [NSView] = [folderRow(draft.inputFolder, label: "Watch this inbox", choose: { [weak self] in self?.draft.inputFolder = $0 }), horizontal([options, NSView()])]
        if showsArrivalOptions { arrival += [recursive, settle, uiLabel("Only new or changed arrivals run. Existing files, temporary files and links are skipped.", size: 11, color: .secondaryLabelColor)] }
        puzzle("WHEN a new file arrives", symbol: "tray.and.arrow.down.fill", tone: .arrival, views: arrival)
        matching.removeAllItems(); matching.addItems(withTitles: ["ALL of these are true", "ANY of these is true"]); matching.selectItem(at: draft.matchAll ? 0 : 1)
        matching.setAccessibilityLabel("Match all or any conditions"); matching.toolTip = "ALL requires every condition to match. ANY requires at least one condition to match."
        var conditionViews: [NSView] = [matching]
        for (index, condition) in draft.conditions.enumerated() {
            let field = RulePopup(); for choice in MatchField.allCases { field.addItem(withTitle: choice.title); field.lastItem?.representedObject = choice.rawValue }; field.selectItem(at: MatchField.allCases.firstIndex(of: condition.field)!)
            field.setAccessibilityLabel("Condition \(index + 1) type")
            field.changed { [weak self, weak field] in
                guard let self, self.flowRevision == revision, let value = field?.selectedItem?.representedObject as? String, let kind = MatchField(rawValue: value) else { return }
                self.changeCondition(index, to: kind)
            }
            let value: NSControl
            if condition.field == .format { value = formatPopup(condition.value.lowercased()) }
            else if condition.field == .category { value = popup(FormatCatalog.groups.map { ($0.title, $0.id) }, selected: condition.value.lowercased()) }
            else { let text = NSTextField(string: condition.value); text.placeholderString = condition.field == .nameSuffix ? "Example: .mp3" : "Type part of a filename"; text.delegate = self; text.toolTip = "Matches the filename including its extension, without case sensitivity."; value = text }
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            value.setAccessibilityLabel(condition.field.title + " value"); conditions.append((condition.field, value))
            let remove = RuleButton("", symbol: "xmark", action: { [weak self] in guard let self, self.flowRevision == revision else { return }; self.removeCondition(index) })
            remove.setAccessibilityLabel("Remove condition \(index + 1)"); remove.toolTip = "Remove this condition"; remove.isEnabled = draft.conditions.count > 1
            conditionViews.append(horizontal([field, value, remove]))
        }
        let addCondition = RuleButton("Add Condition", symbol: "plus.circle", action: { [weak self] in guard let self, self.flowRevision == revision else { return }; self.addCondition() }); addCondition.isEnabled = draft.conditions.count < 12
        conditionViews += [horizontal([addCondition, NSView()]), uiLabel("Recognises file content where possible. Filename tests include the extension.", size: 11, color: .secondaryLabelColor)]
        puzzle("IF the file matches…", symbol: "arrow.triangle.branch", tone: .decision, views: conditionViews)
        let branch = horizontal([uiLabel("↓ MATCH · run the blocks below", size: 12, weight: .semibold, color: .systemGreen), NSView(), uiLabel("↳ NO MATCH · try next eligible rule", size: 11, weight: .medium, color: .secondaryLabelColor)])
        branch.toolTip = "A nonmatching file stays unchanged by this rule. The next enabled rule whose inbox contains it is tried; with no match it stays in the inbox."
        branchStatus.font = .systemFont(ofSize: 11, weight: .medium); branchStatus.setAccessibilityLabel("Decision preview path")
        let branchContainer = vertical([branch, uiLabel("If no rule matches, the original stays in its inbox.", size: 11, color: .secondaryLabelColor), branchStatus])
        branchContainer.spacing = 3; full(RuleBlock(content: branchContainer, allowGlass: false), in: body)
        for (index, step) in draft.steps.enumerated() {
            let value: NSControl = step.kind == .convert ? formatPopup(step.value) : NSTextField(string: step.value)
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true; value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if let text = value as? NSTextField { text.placeholderString = "{name}-{format}"; text.delegate = self }
            value.setAccessibilityLabel(step.kind == .convert ? "Action \(index + 1) output format" : "Action \(index + 1) rename template"); steps.append((step.kind, value))
            let up = RuleButton("", symbol: "chevron.up", action: { [weak self] in guard let self, self.flowRevision == revision else { return }; self.moveStep(index, -1) }); up.isEnabled = index > 0; up.setAccessibilityLabel("Move action \(index + 1) up"); up.toolTip = "Move Up"
            let down = RuleButton("", symbol: "chevron.down", action: { [weak self] in guard let self, self.flowRevision == revision else { return }; self.moveStep(index, 1) }); down.isEnabled = index + 1 < draft.steps.count; down.setAccessibilityLabel("Move action \(index + 1) down"); down.toolTip = "Move Down"
            let remove = RuleButton("", symbol: "xmark", action: { [weak self] in guard let self, self.flowRevision == revision else { return }; self.removeStep(index) }); remove.isEnabled = draft.steps.count > 1; remove.setAccessibilityLabel("Remove action \(index + 1)"); remove.toolTip = "Remove Action"
            let example = uiLabel("", size: 11, color: .secondaryLabelColor); example.setAccessibilityLabel("Action \(index + 1) filename example"); exampleLabels.append(example)
            let hint = step.kind == .rename ? "Output name only. Use {name}, {format}, {date}; extension is added automatically." : "Preview a real file to check compatibility. Actions run from top to bottom."
            let piece = puzzle("DO \(index + 1) · " + (step.kind == .convert ? "Convert to" : "Rename the output"), symbol: step.kind == .convert ? "arrow.triangle.2.circlepath" : "pencil", tone: step.kind == .convert ? .convert : .rename, views: [horizontal([RuleDragHandle(token: dragToken(index)), value, up, down, remove]), example, uiLabel(hint, size: 11, color: .secondaryLabelColor)])
            piece.acceptsDrop = { [weak self] token in guard let self, self.flowRevision == revision else { return false }; return self.acceptActionDrag(token) }
            piece.drop = { [weak self] token, below in guard let self, self.flowRevision == revision else { return false }; return self.dropAction(token, at: index, below: below) }
        }
        puzzle("SAVE the result in…", symbol: "folder.fill", tone: .destination, views: [folderRow(draft.destination, label: "Save converted results here", choose: { [weak self] in self?.draft.destination = $0 }), uiLabel("Use a folder outside watched inboxes. Existing names get a numbered suffix.", size: 11, color: .secondaryLabelColor)])
        policy.removeAllItems(); for (title, value) in [("Keep original in inbox", "keep"), ("Move original to archive", "archive"), ("Send original to Trash", "trash")] { policy.addItem(withTitle: title); policy.lastItem?.representedObject = value }; policy.selectItem(at: OriginalPolicy.allCases.firstIndex(of: draft.originalPolicy)!)
        policy.setAccessibilityLabel("Original file after successful output")
        policy.changed { [weak self] in guard let self, self.flowRevision == revision else { return }; self.gather(); self.rebuildEditor() }
        acknowledge.state = draft.acknowledgedRemoval ? .on : .off
        var originalViews: [NSView] = [policy]
        if draft.originalPolicy == .archive { originalViews.append(folderRow(draft.archiveFolder, label: "Archive originals here", choose: { [weak self] in self?.draft.archiveFolder = $0 })) }
        if draft.originalPolicy != .keep { originalViews.append(acknowledge) }
        originalViews.append(uiLabel("Only after the output is saved. Failures keep the original. Documents and geospatial files must use Keep.", size: 11, color: .secondaryLabelColor))
        puzzle("AFTER SUCCESS · the original", symbol: "shield.checkered", tone: .original, views: originalViews)
        for button in navigationButtons { button.isEnabled = flowNodes[button.identifier?.rawValue ?? ""] != nil }
        refreshEditingStatus(); refreshFlowSummary()
        window?.contentView?.layoutSubtreeIfNeeded()
        let maxY = max(0, (editorScroll.documentView?.bounds.height ?? 0) - editorScroll.contentView.bounds.height)
        editorScroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset.y, maxY))); editorScroll.reflectScrolledClipView(editorScroll.contentView)
    }
    func addCondition() { gather(); guard draft.conditions.count < 12, selectedID != nil else { return }; draft.conditions.append(.init()); rebuildEditor() }
    func removeCondition(_ index: Int) { gather(); guard draft.conditions.count > 1, draft.conditions.indices.contains(index) else { return }; draft.conditions.remove(at: index); rebuildEditor() }
    func changeCondition(_ index: Int, to field: MatchField) {
        gather(); guard draft.conditions.indices.contains(index) else { return }
        let old = draft.conditions[index]
        let textFields: [MatchField] = [.nameContains, .namePrefix, .nameSuffix]
        let value = textFields.contains(old.field) && textFields.contains(field) ? old.value : field == .format ? "mp3" : field == .category ? "audio" : ""
        draft.conditions[index] = .init(field: field, value: value)
        rebuildEditor(); window?.makeFirstResponder(conditions[index].1)
    }
    func addStep(_ kind: StepKind) {
        gather(); guard draft.steps.count < 8, selectedID != nil else { return }
        let format = draft.steps.last(where: { $0.kind == .convert })?.value ?? (draft.matchAll ? draft.conditions.first(where: { $0.field == .format })?.value : nil)
        let category = format.flatMap { format in FormatCatalog.groups.first { $0.formats.contains(format) }?.id } ?? draft.conditions.first(where: { $0.field == .category })?.value ?? "audio"
        let defaults = ["audio": "mp3", "video": "mp4", "image": "webp", "document": "md", "geo": "geojson", "config": "yaml"]
        draft.steps.append(.init(kind: kind, value: kind == .convert ? defaults[category] ?? "mp3" : "{name}-{format}")); rebuildEditor()
    }
    func removeStep(_ index: Int) { gather(); guard draft.steps.count > 1, draft.steps.indices.contains(index) else { return }; draft.steps.remove(at: index); rebuildEditor() }
    func moveAction(from index: Int, to destination: Int) {
        gather(); guard draft.steps.indices.contains(index), draft.steps.indices.contains(destination), index != destination else { return }
        let moved = draft.steps.remove(at: index); draft.steps.insert(moved, at: destination); rebuildEditor()
    }
    func dragToken(_ index: Int) -> String { "\(flowSession)|\(draft.id)|\(flowRevision)|\(index)" }
    func acceptActionDrag(_ token: String) -> Bool {
        let fields = token.split(separator: "|")
        return fields.count == 4 && fields[0] == flowSession && fields[1] == draft.id.uuidString && Int(fields[2]) == flowRevision && Int(fields[3]).map { draft.steps.indices.contains($0) } == true
    }
    @discardableResult func dropAction(_ token: String, at index: Int, below: Bool) -> Bool {
        guard acceptActionDrag(token), draft.steps.indices.contains(index), let source = Int(token.split(separator: "|").last!) else { return false }
        let insertion = index + (below ? 1 : 0)
        let target = insertion - (source < insertion ? 1 : 0)
        moveAction(from: source, to: target); return true
    }
    func refreshFlowSummary() {
        guard selectedID != nil else { return }
        let inbox = draft.inputFolder.isEmpty ? "Choose inbox" : URL(fileURLWithPath: draft.inputFolder).lastPathComponent
        let output = draft.destination.isEmpty ? "Choose output folder" : URL(fileURLWithPath: draft.destination).lastPathComponent
        flowSummary.stringValue = "\(inbox) → match \(draft.matchAll ? "all" : "any") \(draft.conditions.count) condition(s) → \(draft.steps.count) action(s) → \(output) · original \(draft.originalPolicy == .keep ? "kept" : draft.originalPolicy == .archive ? "archived" : "sent to Trash")"
        let names = RuleFlowExample.names(draft)
        for (index, label) in exampleLabels.enumerated() where names.indices.contains(index) { label.stringValue = "Illustration using " + RuleFlowExample.inputFormat(draft).uppercased() + " input → " + names[index]; label.toolTip = "Illustration only. Preview a real file for its recognised format and actual plan." }
    }
    func jumpToBlock(_ key: String) {
        guard let node = flowNodes[key], let canvas = editorScroll.documentView else { return }
        if let viewTabs, viewTabs.selectedSegment != 0 { viewTabs.selectedSegment = 0; changeTab(viewTabs) }
        let frame = node.convert(node.bounds, to: canvas)
        let maxY = max(0, canvas.bounds.height - editorScroll.contentView.bounds.height)
        editorScroll.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, max(0, frame.minY - 2)))); editorScroll.reflectScrolledClipView(editorScroll.contentView)
    }
    func gather() {
        guard selectedID != nil else { return }
        draft.name = textValue(name); draft.enabled = enabled.state == .on; draft.recursive = recursive.state == .on; draft.settleSeconds = settle.selectedItem?.representedObject as? Double ?? 3; draft.matchAll = matching.indexOfSelectedItem == 0
        draft.conditions = conditions.map { field, control in .init(field: field, value: controlValue(control)) }
        draft.steps = steps.map { kind, control in .init(kind: kind, value: controlValue(control)) }
        draft.originalPolicy = OriginalPolicy(rawValue: policy.selectedItem?.representedObject as? String ?? "keep") ?? .keep
        draft.acknowledgedRemoval = acknowledge.state == .on
        if let detailsRule, detailsRule != draft { invalidatePreviewDetails(); message.textColor = .secondaryLabelColor; message.stringValue = "The rule changed. Preview again to see a current plan. No files changed." }
        refreshEditingStatus(); refreshFlowSummary()
    }
    func refreshEditingStatus() {
        guard let saved = runtime.rules.first(where: { $0.id == selectedID }) else { editingStatus.stringValue = ""; return }
        editingStatus.stringValue = saved != draft ? "Unsaved changes. Preview uses your edits; watching uses saved rules until you save." : (saved.enabled ? "Saved rule is enabled. Only new or changed arrivals run automatically." : "Saved draft is off. Enable and Save Rule to start watching.")
    }
    @objc func editorControlChanged(_ sender: NSControl) { gather(); cancelPreview() }
    func controlTextDidChange(_ notification: Notification) { gather(); cancelPreview() }
    func invalidatePreviewDetails() { previewDetails = nil; detailsRule = nil; viewPreviewDetails.isEnabled = false; previewDetailsWindow?.close(); previewDetailsWindow = nil; branchStatus.stringValue = "Preview a file to see which path it takes."; branchStatus.textColor = .secondaryLabelColor }
    func showPreviewDetails() {
        gather()
        guard let previewDetails, detailsRule == draft, selectedID == draft.id else { invalidatePreviewDetails(); return }
        if previewDetailsWindow == nil { previewDetailsWindow = RulePreviewDetails(text: previewDetails) }
        previewDetailsWindow?.showWindow(nil); previewDetailsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    private func textValue(_ field: NSTextField) -> String { field.currentEditor()?.string ?? field.stringValue }
    private func controlValue(_ control: NSControl) -> String { (control as? NSPopUpButton)?.selectedItem?.representedObject as? String ?? (control as? NSTextField).map(textValue) ?? "" }
    @discardableResult func saveRule() -> Bool {
        gather(); guard let index = runtime.rules.firstIndex(where: { $0.id == selectedID }) else { return false }
        var next = runtime.rules; next[index] = draft
        do { try runtime.save(next); cancelPreview(); message.textColor = .secondaryLabelColor; message.stringValue = draft.enabled ? "Saved and watching. Only new or changed files arriving from now on will run." : "Draft saved. Turn on Enable this rule, then save to start watching."; reloadList(); return true }
        catch { message.textColor = .systemRed; message.stringValue = error.localizedDescription; return false }
    }
    func newRule(template: Int) {
        guard (1...4).contains(template), mayDiscard() else { return }
        var rule = WatchRule()
        if template > 1 {
            let choice = [("Audio → MP3", "audio", "mp3"), ("Images → WebP", "image", "webp"), ("Data → YAML", "config", "yaml")][template - 2]
            rule.name = choice.0; rule.conditions = [.init(field: .category, value: choice.1)]; rule.steps = [.init(kind: .convert, value: choice.2)]
        }
        do { try runtime.save(runtime.rules + [rule]); selectedID = rule.id; draft = rule; rebuildEditor(resetScroll: true); reloadList(); message.stringValue = "Choose an inbox and a separate output folder. Preview a file before enabling." }
        catch { message.stringValue = error.localizedDescription }
    }
    func mayDiscard() -> Bool {
        gather()
        guard let saved = runtime.rules.first(where: { $0.id == selectedID }), saved != draft else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to this rule?"; alert.informativeText = "Saved changes take effect before you continue."; alert.addButton(withTitle: "Save Changes"); alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard Changes")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.buttons[1].keyEquivalentModifierMask = []
        return resolveUnsavedChanges(alert.runModal())
    }
    func resolveUnsavedChanges(_ choice: NSApplication.ModalResponse) -> Bool {
        if choice == .alertFirstButtonReturn { return saveRule() }
        guard choice == .alertThirdButtonReturn, let saved = runtime.rules.first(where: { $0.id == selectedID }) else { return false }
        draft = saved; rebuildEditor(); message.textColor = .secondaryLabelColor; message.stringValue = "Changes discarded. The saved rule was restored."; return true
    }
    func duplicate() {
        guard selectedID != nil, mayDiscard() else { return }
        var rule = draft; rule.id = UUID(); rule.name = String((rule.name + " copy").prefix(100)); rule.enabled = false
        do { try runtime.save(runtime.rules + [rule]); selectedID = rule.id; draft = rule; rebuildEditor(resetScroll: true); reloadList() } catch { message.stringValue = error.localizedDescription }
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
    func moveStep(_ index: Int, _ delta: Int) { moveAction(from: index, to: index + delta) }
    func testFile() {
        gather(); cancelPreview(); let rule = draft
        do { try rule.validate(roots: runtime.enabledRules.map(\.inputFolder) + [rule.inputFolder]) } catch { message.stringValue = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.allowedContentTypes = []; panel.allowsOtherFileTypes = true; panel.message = "Preview this rule on an inbox file. No files will change or convert."; panel.directoryURL = URL(fileURLWithPath: rule.inputFolder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startPreview(url, rule: rule)
    }
    func cancelPreview() {
        let wasRunning = previewRunning, hadDetails = previewDetails != nil
        previewCancellation?.cancel(); previewCancellation = nil; previewID = nil
        invalidatePreviewDetails()
        test.isEnabled = selectedID != nil && previewWorkCount == 0; cancelTest.isHidden = true
        if wasRunning || hadDetails { message.textColor = .secondaryLabelColor; message.stringValue = "The rule changed or its preview was closed. Preview again to see a current plan." }
    }
    func startPreview(_ url: URL, rule: WatchRule) {
        guard previewWorkCount == 0 else { message.stringValue = "The previous preview is finishing. Try again when Preview a File becomes available."; return }
        cancelPreview()
        let id = UUID(), cancellation = AutomationCancellation(); previewID = id; previewCancellation = cancellation
        previewWorkCount += 1
        test.isEnabled = false; cancelTest.isHidden = false; message.textColor = .secondaryLabelColor; message.stringValue = "Checking \(url.lastPathComponent) and building a read-only plan…"
        let factory = runtime.engine, scratch = runtime.store.url("Staging")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text: String, failed: Bool
            do { text = try AutomationPipeline(engine: factory(), scratch: scratch).preview(url, rule: rule, cancellation: cancellation); failed = false } catch { text = error.localizedDescription; failed = true }
            DispatchQueue.main.async {
                guard let self else { return }
                self.previewWorkCount -= 1; self.test.isEnabled = self.selectedID != nil && self.previewWorkCount == 0
                defer { self.onPreviewFinished?() }
                guard self.previewID == id else { return }
                self.gather(); self.previewID = nil; self.previewCancellation = nil; self.cancelTest.isHidden = true
                guard self.selectedID == rule.id, self.draft == rule else { self.invalidatePreviewDetails(); self.message.textColor = .secondaryLabelColor; self.message.stringValue = "The rule changed during its preview. Preview again to see a current plan. No files changed."; return }
                self.previewDetails = text; self.detailsRule = rule; self.viewPreviewDetails.isEnabled = true
                self.branchStatus.stringValue = failed ? "Preview needs attention · read the result below." : text.hasPrefix("No match") ? "↳ NO MATCH · this rule leaves the file unchanged." : "↓ MATCH · follow the action blocks, then save the output."
                self.branchStatus.textColor = failed ? .systemOrange : text.hasPrefix("No match") ? .secondaryLabelColor : .systemGreen
                self.message.textColor = failed ? .systemRed : .secondaryLabelColor
                if failed { self.message.stringValue = String(text.prefix(240)) + (text.count > 240 ? "…" : "") }
                else if text.hasPrefix("No match") { self.message.stringValue = "No match for this rule. Other eligible enabled rules may match.\nNo files changed. Open Preview Details for the recognised format and full paths." }
                else {
                    let lines = text.components(separatedBy: "\n")
                    self.message.stringValue = lines.filter { $0.hasPrefix("Detected:") || $0.hasPrefix("Planned output:") }.joined(separator: "\n") + "\nNo files changed. Open Preview Details for the full plan and original-file action."
                }
                self.message.toolTip = text
            }
        }
    }
    func runExisting() {
        guard !runtime.enabledRules.isEmpty, !runtime.paused else { message.stringValue = "Enable and save a rule first, then resume watching."; return }
        let alert = NSAlert(); alert.messageText = "Run enabled rules on existing files?"; alert.informativeText = "This queues up to 1,000 files already in your inboxes. Saved original-file actions also apply. Normal watching only handles new or changed arrivals."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Run Existing Files")
        if alert.runModal() == .alertSecondButtonReturn {
            if let count = runtime.runExisting() { message.stringValue = "Queued \(count) existing file(s) using saved rules." }
            else { message.stringValue = "The watcher is busy scanning or paused. Wait for it to be ready, then try again." }
        }
    }
    @objc func changeTab(_ sender: NSSegmentedControl) { editorScroll.isHidden = sender.selectedSegment == 1; activityScroll.isHidden = sender.selectedSegment == 0; if sender.selectedSegment == 1 { refreshActivity() } }
    func refreshStatus() {
        stateLabel.stringValue = runtime.status; pause.title = runtime.paused ? "Resume All" : "Pause All"; pause.isEnabled = !runtime.enabledRules.isEmpty
        existing.isEnabled = runtime.canRunExisting
        existing.toolTip = runtime.enabledRules.isEmpty ? "Enable and save a rule first. This action uses saved enabled rules." : (runtime.paused ? "Resume watching before running existing files." : (!runtime.canRunExisting ? "The watcher is still scanning. Wait until it is ready." : "Queues up to 1,000 inbox files using saved enabled rules, including their original-file actions."))
        if !activityScroll.isHidden { refreshActivity() }
    }
    func refreshActivity() {
        guard activityCount != runtime.activities.count || activityDate != runtime.activities.last?.date else { return }
        activityCount = runtime.activities.count; activityDate = runtime.activities.last?.date
        activityTable.reloadData()
    }
    func reloadList() {
        reloadingList = true
        defer { reloadingList = false }
        let selectedIndex = runtime.rules.firstIndex(where: { $0.id == selectedID })
        for button in ruleTools { button.isEnabled = selectedIndex != nil }
        if ruleTools.count == 4 { ruleTools[2].isEnabled = (selectedIndex ?? 0) > 0; ruleTools[3].isEnabled = selectedIndex.map { $0 + 1 < runtime.rules.count } ?? false }
        table.reloadData(); if let index = runtime.rules.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }; refreshStatus(); refreshEditingStatus() }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView == activityTable ? max(1, runtime.activities.count) : runtime.rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == activityTable {
            let identifier = NSUserInterfaceItemIdentifier("automationActivityCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ActivityCell ?? ActivityCell()
            cell.identifier = identifier
            if runtime.activities.isEmpty { cell.configure(nil) }
            else if runtime.activities.indices.contains(row) { cell.configure(runtime.activities[runtime.activities.count - 1 - row]) }
            else { cell.configure(nil) }
            return cell
        }
        guard runtime.rules.indices.contains(row) else { return nil }
        let rule = runtime.rules[row]; let text = NSTextField(wrappingLabelWithString: rule.name + "\n" + (rule.enabled ? "Enabled" : "Draft · off")); text.font = .systemFont(ofSize: 12); text.maximumNumberOfLines = 2; text.setAccessibilityLabel(rule.name + ", " + (rule.enabled ? "enabled" : "disabled")); return text
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { tableView == activityTable || (runtime.rules.indices.contains(row) && (reloadingList || runtime.rules[row].id == selectedID || mayDiscard())) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { mayDiscard() }
    func windowWillClose(_ notification: Notification) { cancelPreview(); onClose?() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloadingList, notification.object as? NSTableView === table, runtime.rules.indices.contains(table.selectedRow), runtime.rules[table.selectedRow].id != selectedID else { return }
        selectedID = runtime.rules[table.selectedRow].id; draft = runtime.rules[table.selectedRow]; rebuildEditor(resetScroll: true); reloadList(); message.stringValue = "Edit blocks, preview a file, then save. Changes take effect after saving."
    }
}

/// Keep full preview plans readable and selectable without expanding the editor
/// or hiding original-file consequences behind a truncated label or tooltip.
final class RulePreviewDetails: NSWindowController {
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    let scroll = NSScrollView()
    let done: RuleButton
    init(text plan: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Rule Preview Details — UltraConvert"; window.minSize = NSSize(width: 540, height: 320); window.isReleasedWhenClosed = false
        done = RuleButton("Done", action: { [weak window] in window?.performClose(nil) }); done.keyEquivalent = "\u{1b}"; done.keyEquivalentModifierMask = []
        super.init(window: window)
        let title = uiLabel("Read-only preview · no files changed", size: 15, weight: .semibold)
        let content = window.contentView!
        for view in [title, scroll, done] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        text.string = plan; text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 13); text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.minSize = .zero; text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true; text.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel("Complete rule preview, destination and original-file actions")
        scroll.documentView = text
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14), scroll.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -14),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Reuse only visible history rows; hundreds of per-row glass effects and
/// full-stack rebuilding would waste memory and frame time during bulk work.
final class ActivityCell: NSTableCellView {
    private static let timestamp: DateFormatter = { let value = DateFormatter(); value.locale = .autoupdatingCurrent; value.timeZone = .autoupdatingCurrent; value.dateStyle = .short; value.timeStyle = .short; return value }()
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
        guard let event else { title.stringValue = "No files processed yet"; details.stringValue = "Test your rule, then add a new file to its inbox. Activity stays local; the last 200 outcomes are retained."; details.toolTip = details.stringValue; reveal.isHidden = true; reveal.invoke = {}; setAccessibilityLabel(title.stringValue); return }
        title.stringValue = event.file
        let date = Self.timestamp.string(from: event.date)
        details.stringValue = event.rule + " · " + date + "\n" + event.message; details.toolTip = event.message
        reveal.isHidden = event.output == nil; reveal.setAccessibilityLabel("Reveal output for " + event.file)
        reveal.invoke = { if let output = event.output { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output)]) } }
        setAccessibilityLabel(event.file + ", " + event.message)
    }
}

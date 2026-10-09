import AppKit

enum GuideDestination: Equatable { case addFiles, rules, settings, setup, fullGuide }

/// An optional, nonmodal task map. Reading help never alters a batch or a rule.
final class GettingStarted: NSWindowController {
    let topics = NSSegmentedControl(labels: ["Convert Files", "Finder", "Folder Rules", "Options & Startup"], trackingMode: .selectOne, target: nil, action: nil)
    let body = NSStackView()
    let actions = NSStackView()
    let route: (GuideDestination) -> Void

    init(route: @escaping (GuideDestination) -> Void) {
        self.route = route
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Getting Started — UltraConvert"; panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 680, height: 520); panel.isReleasedWhenClosed = false
        super.init(window: panel)
        let main = NSStackView(); main.orientation = .vertical; main.alignment = .leading; main.spacing = 16
        pin(main, in: panel.contentView!, inset: 24)
        func full(_ view: NSView) { main.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        full(uiLabel("Start with a task", size: 25, weight: .semibold))
        full(uiLabel("Convert a batch now, use Finder shortcuts, or let folder rules handle new files. Everything runs on your Mac.", size: 13, color: .secondaryLabelColor))
        topics.selectedSegment = 0; topics.target = self; topics.action = #selector(changeTopic)
        topics.setAccessibilityLabel("Getting Started topics"); full(topics)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let canvas = FlippedView(); canvas.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = canvas
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 12; body.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(body)
        NSLayoutConstraint.activate([canvas.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), body.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), body.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8), body.topAnchor.constraint(equalTo: canvas.topAnchor), body.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -8)])
        full(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let note = uiLabel("Reopen this guide with Getting Started in the converter or the Help menu. Settings is also available with ⌘,.", size: 11, color: .secondaryLabelColor)
        full(note)
        actions.spacing = 8; full(actions)
        render(); panel.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func changeTopic() { render() }
    func openTopic(_ index: Int) { topics.selectedSegment = max(0, min(3, index)); render() }
    private func card(_ title: String, _ text: String) {
        let card = RoundedCard()
        for field in [uiLabel(title, size: 14, weight: .semibold), uiLabel(text, size: 12)] {
            field.isSelectable = true; card.contents.addArrangedSubview(field); field.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        }
        body.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }
    private func action(_ title: String, _ destination: GuideDestination) {
        actions.addArrangedSubview(RuleButton(title, action: { [weak self] in
            guard let self else { return }; self.close(); self.route(destination)
        }))
    }
    func render() {
        for stack in [body, actions] { for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() } }
        switch topics.selectedSegment {
        case 1:
            card("Quick Actions · convert any supported batch", "In Finder, select one or more files, right-click → Quick Actions → Convert Here with UltraConvert. The app opens for review. ‘Here’ saves single-file results beside each original. Convert to Destination with UltraConvert uses your saved output folder.")
            card("Services · choose a format first", "Right-click files → Services → Convert Here with UltraConvert — Choose Format… Select a category and format, then Review Conversion. Convert Here with UltraConvert — MP3 is a preset shortcut. Click Convert in the app to start; choosing a shortcut starts no conversion.")
            card("If an action is missing", "Open Settings and use Install or Repair Quick Actions. Enable them in System Settings → General → Login Items & Extensions → Finder (ⓘ). For format shortcuts, use System Settings → Keyboard → Keyboard Shortcuts → Services. macOS chooses which Services suit your selected file types; use the general Quick Action for a misnamed file.")
            action("Open Finder Setup…", .settings)
        case 2:
            card("1. Choose a template and two folders", "Open Folder Rules → New Rule → Audio → MP3, Images → WebP or Data → YAML. WHEN is the inbox to watch; SAVE is a separate output folder outside every watched inbox. Templates start off. Files already present are ignored when watching starts.")
            card("2. Match files and order the actions", "IF checks the detected file format, category or filename. ALL means every condition must match; ANY means at least one. THEN actions run from top to bottom. Rename changes the output name: {name}-{format} makes Recording-mp3.mp3. The wait time lets a file finish copying before inspection.")
            card("3. Preview, then enable and save", "Preview a File shows a plan without changing files. Check the output and AFTER SUCCESS policy. Keep the original is the default; Archive or Trash only applies after successful output and your acknowledgement. Enable this rule, then Save Rule. Unsaved edits do not change a running rule.")
            card("Pause, existing files and activity", "Pause All stops new work. Run Existing Files explicitly queues files already in the inbox using saved enabled rules. Activity shows results and errors. Closing the converter keeps enabled rules running; Quit UltraConvert stops watching. Launch at login is optional in Settings.")
            action("Open Folder Rules…", .rules)
        case 3:
            card("Where results go", "Beside source files saves single-file outputs next to their originals. Saved destination uses the folder remembered with Set as Default. Choose destination selects a folder for this batch. Destination batches use a Converted folder; files that need companions stay together. Existing names receive a numbered suffix.")
            card("Batch options", "Skip files already in target format leaves matching files unchanged and records them as skipped. Open results when finished reveals successful outputs. Files at a time controls simultaneous conversion: 2 suits most batches; 1 reduces peak resource use for large media or geospatial files. These settings do not affect folder-rule jobs.")
            card("Startup and recovery", "Launch at login opens UltraConvert after signing in to macOS. Start in the menu bar applies when enabled folder rules exist. Both are optional. If something fails, Report contains details, Retry Failed prepares those files for review, and Help → Check Setup checks the local engines.")
            action("Open Settings…", .settings); action("Check Setup…", .setup)
        default:
            card("1. Add files", "Drop one or more files into the converter or use Add Files (⌘O). UltraConvert recognises the contents, even when an extension is misleading. Add Files keeps the current queue. Remove Selected and Clear only remove queue entries.")
            card("2. Choose formats and a save location", "Pick an output format for each detected category. The advice under each choice explains common uses and tradeoffs. Mixed batches can have different targets, such as images → PNG and audio → MP3. Review each file’s source → target preview and the Save to explanation.")
            card("3. Convert and find the results", "Click Convert. Show Results reveals the new files; Report explains failures or skipped files. You can cancel; completed outputs remain. Manual conversions always keep originals and never replace existing files. Folder rules have their own explicit original-file policy.")
            action("Add Files…", .addFiles)
        }
        actions.insertArrangedSubview(RuleButton("Done", action: { [weak self] in self?.close() }), at: 0)
        if let done = actions.arrangedSubviews.first as? NSButton { done.keyEquivalent = "\u{1b}"; done.keyEquivalentModifierMask = [] }
        actions.insertArrangedSubview(NSView(), at: 1)
        action("Full Guide", .fullGuide)
    }
}

extension ConverterApp {
    var shouldOfferGettingStarted: Bool { !busy && files.isEmpty && phase == .empty && !preferences.bool(forKey: "hasSeenGettingStarted") && window.isVisible }
    @objc func showQuickStart() {
        preferences.set(true, forKey: "hasSeenGettingStarted")
        if guideController == nil { guideController = GettingStarted(route: { [weak self] destination in
            guard let self else { return }
            switch destination {
            case .addFiles: self.showConverter(); self.pickFiles()
            case .rules: self.showFolderRules()
            case .settings: self.showSettings()
            case .setup: self.showConverter(); self.checkSetup()
            case .fullGuide: self.openGuide()
            }
        }) }
        guideController?.showWindow(nil); guideController?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

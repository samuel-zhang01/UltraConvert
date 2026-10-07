import AppKit

extension ConverterApp {
    func startFolderAutomation() {
        do {
            let contents = Bundle.main.bundleURL.appendingPathComponent("Contents"), support = self.support
            let runtime = try FolderAutomation(support: support, engine: { NativeAutomationEngine(backend: try BackendPaths(contents: contents, support: support)) })
            runtime.manualBusy = { [weak self] in self?.busy ?? false }
            runtime.onChange = { [weak self] in self?.updateAutomationPresentation() }
            automation = runtime; runtime.configure()
        } catch { automationError = error.localizedDescription }
    }
    @objc func showFolderRules() {
        guard let automation else {
            let alert = NSAlert(); alert.messageText = "Folder rules need attention"; alert.informativeText = automationError ?? "Could not load folder automation."; alert.runModal(); return
        }
        if rulesController == nil {
            rulesController = FolderRulesWindow(runtime: automation)
            rulesController?.onClose = { [weak self] in if self?.window.isVisible == false && self?.automation?.keepsRunning == true { NSApp.setActivationPolicy(.accessory) } }
            rulesController?.onPreviewFinished = { [weak self] in self?.updateAutomationPresentation() }
        }
        NSApp.setActivationPolicy(.regular)
        rulesController?.showWindow(nil); rulesController?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleFolderWatching() { guard let automation else { return }; automation.setPaused(!automation.paused) }
    @objc func showConverter() {
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func updateAutomationPresentation() {
        if waitingForAutomationQuit && automation?.running != true && (rulesController?.previewWorkCount ?? 0) == 0 { waitingForAutomationQuit = false; NSApp.reply(toApplicationShouldTerminate: true); return }
        rulesController?.refreshStatus()
        guard let automation else { return }
        if !automation.enabledRules.isEmpty && automation.keepsRunning {
            if watcherStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "UltraConvert folder rules")
                item.button?.setAccessibilityLabel("UltraConvert folder rules")
                watcherStatusItem = item
            }
            watcherStatusItem?.button?.toolTip = "UltraConvert · " + automation.status
            let menu = NSMenu()
            let state = NSMenuItem(title: automation.status, action: nil, keyEquivalent: ""); state.isEnabled = false; menu.addItem(state); menu.addItem(.separator())
            addMenuItem(menu, "Open Converter", #selector(showConverter), symbol: "arrow.triangle.2.circlepath")
            addMenuItem(menu, "Folder Rules…", #selector(showFolderRules), symbol: "square.stack.3d.up")
            addMenuItem(menu, automation.paused ? "Resume Folder Rules" : "Pause Folder Rules", #selector(toggleFolderWatching), symbol: automation.paused ? "play" : "pause")
            addMenuItem(menu, "Startup & Finder Settings…", #selector(showSettings), symbol: "gearshape")
            menu.addItem(.separator()); menu.addItem(withTitle: "Quit UltraConvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            watcherStatusItem?.menu = menu
        } else if let item = watcherStatusItem { NSStatusBar.system.removeStatusItem(item); watcherStatusItem = nil }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showConverter(); return true }
}

final class FormatPicker: NSWindowController {
    let category = RulePopup()
    let format = NSPopUpButton()
    let cancel: RuleButton
    let review: RuleButton
    let choose: (String) -> Void
    init(count: Int, choose: @escaping (String) -> Void) {
        self.choose = choose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 265), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Convert Here with UltraConvert"; window.isReleasedWhenClosed = false
        cancel = RuleButton("Cancel", action: { [weak window] in window?.performClose(nil) }); cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        review = RuleButton("Review Conversion", action: {}); review.keyEquivalent = "\r"
        review.keyEquivalentModifierMask = []
        super.init(window: window)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        stack.addArrangedSubview(uiLabel("Choose an output format", size: 23, weight: .semibold))
        stack.addArrangedSubview(uiLabel("\(count) selected file(s) · save beside originals", size: 12, color: .secondaryLabelColor))
        category.addItems(withTitles: FormatCatalog.groups.map(\.title)); category.setAccessibilityLabel("Output format category"); format.setAccessibilityLabel("Output file format")
        category.changed { [weak self] in self?.refreshFormats() }; refreshFormats()
        let row = NSStackView(views: [category, format]); row.spacing = 12; stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        format.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.45).isActive = true
        stack.addArrangedSubview(uiLabel("All formats are listed. UltraConvert detects your files and checks compatibility before you click Convert.", size: 12, color: .secondaryLabelColor))
        review.invoke = { [weak self] in guard let self, let value = self.format.selectedItem?.representedObject as? String else { return }; self.choose(value); self.close() }
        let footer = NSStackView(views: [NSView(), cancel, review]); footer.spacing = 8; stack.addArrangedSubview(footer); footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refreshFormats() { format.removeAllItems(); for value in FormatCatalog.groups[max(0, category.indexOfSelectedItem)].formats { format.addItem(withTitle: value.uppercased()); format.lastItem?.representedObject = value } }
}

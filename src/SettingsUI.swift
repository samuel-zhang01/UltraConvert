import AppKit
import ServiceManagement

enum SettingsPane: String, CaseIterable {
    case general, updates, finder
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .general: return "gearshape"; case .updates: return "arrow.down.circle"; case .finder: return "cursorarrow.click" }
    }
    var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
}

/// System preference-style navigation, with ordinary opaque content surfaces.
/// Only the native window toolbar uses the system's navigation material.
final class IntegrationSettings: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let actionWidth: CGFloat = 192
    let preferences: UserDefaults
    let login: any LoginService
    let registerFinder: () throws -> Void
    let updates: (any UpdateManaging)?
    let updateChecks = NSButton(checkboxWithTitle: "Automatically check for updates daily", target: nil, action: nil)
    let updateDownloads = NSButton(checkboxWithTitle: "Download updates and install when I quit", target: nil, action: nil)
    let previewUpdates = NSButton(checkboxWithTitle: "Include preview releases", target: nil, action: nil)
    let updateStatus = NSTextField(wrappingLabelWithString: "")
    let updateNow = NSButton(title: "Check for Updates…", target: nil, action: nil)
    let loginToggle = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    let minimizedToggle = NSButton(checkboxWithTitle: "Start minimized at login", target: nil, action: nil)
    let minimizedHelp = NSTextField(wrappingLabelWithString: "")
    let menuBarToggle = NSButton(checkboxWithTitle: "Open quietly with active folder rules", target: nil, action: nil)
    let finderToggle = NSButton(checkboxWithTitle: "Repair Quick Actions automatically", target: nil, action: nil)
    let loginStatus = NSTextField(wrappingLabelWithString: "")
    let integrationStatus = NSTextField(wrappingLabelWithString: "")
    let servicesStatus = NSTextField(wrappingLabelWithString: "")
    let downloadsHelp = NSTextField(wrappingLabelWithString: "")
    let legacyDisclosure = NSButton()
    let legacyBody = NSStackView()
    let host = NSView()
    var paneScrolls: [SettingsPane: NSScrollView] = [:]
    var paneDocuments: [SettingsPane: NSView] = [:]
    private(set) var actionButtons: [NSButton] = []
    private(set) var selectedPane = SettingsPane.general

    init(preferences: UserDefaults, login: any LoginService, registerFinder: @escaping () throws -> Void, updates: (any UpdateManaging)? = nil) {
        self.preferences = preferences; self.login = login; self.registerFinder = registerFinder; self.updates = updates
        let height = min(CGFloat(640), (NSScreen.main?.visibleFrame.height ?? 900) - 150)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: max(500, height)), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.contentMinSize = NSSize(width: 600, height: 500)
        super.init(window: panel)
        panel.delegate = self; panel.backgroundColor = .windowBackgroundColor
        panel.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "UltraConvert.Settings")
        toolbar.delegate = self; toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false; toolbar.autosavesConfiguration = false
        panel.toolbar = toolbar
        pin(host, in: panel.contentView!, inset: 0)
        host.widthAnchor.constraint(greaterThanOrEqualToConstant: 600).isActive = true
        buildGeneral(); buildUpdates(); buildFinder()
        updates?.onChange = { [weak self] in self?.refreshUpdates() }
        refresh()
        selectPane(SettingsPane(rawValue: preferences.string(forKey: "settingsPane") ?? "") ?? .general, animated: false)
        panel.setContentSize(NSSize(width: 680, height: max(500, height)))
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsPane.allCases.map(\.identifier) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title; item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self; item.action = #selector(changePane(_:)); item.toolTip = "\(pane.title) settings"
        return item
    }
    @objc func changePane(_ sender: NSToolbarItem) {
        if let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) { selectPane(pane) }
    }
    func selectPane(_ pane: SettingsPane, animated: Bool = true) {
        selectedPane = pane; preferences.set(pane.rawValue, forKey: "settingsPane")
        for (key, view) in paneScrolls { view.isHidden = key != pane }
        window?.title = "\(pane.title) — UltraConvert"
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        host.layoutSubtreeIfNeeded()
        window?.makeFirstResponder(nil)
        if animated, let view = paneScrolls[pane] { InterfaceMotion.reveal(view) }
    }
    func pane(_ pane: SettingsPane, title: String, subtitle: String) -> NSStackView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        pin(scroll, in: host, inset: 0)
        let canvas = FlippedView(); canvas.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = canvas
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(stack)
        NSLayoutConstraint.activate([
            canvas.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -24)
        ])
        add(uiLabel(title, size: 22, weight: .semibold), to: stack)
        add(note(subtitle, color: .secondaryLabelColor), to: stack)
        paneScrolls[pane] = scroll; paneDocuments[pane] = canvas
        return stack
    }
    func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    func note(_ text: String, color: NSColor = .labelColor) -> NSTextField { uiLabel(text, size: 13, color: color) }
    func status(_ label: NSTextField, text: String) {
        label.font = .systemFont(ofSize: 13); label.textColor = .labelColor; label.stringValue = text
        label.setAccessibilityRole(.staticText)
    }
    func card(_ title: String, symbol: String, in parent: NSStackView) -> NSStackView {
        let card = RoundedCard(frame: .zero); add(card, to: parent)
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true; image.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let heading = NSStackView(views: [image, uiLabel(title, size: 15, weight: .semibold), NSView()]); heading.spacing = 8
        add(heading, to: card.contents)
        return card.contents
    }
    func toggle(_ button: NSButton, action: Selector, in stack: NSStackView, indent: CGFloat = 0) {
        button.target = self; button.action = action; button.font = .systemFont(ofSize: 13)
        button.setAccessibilityLabel(button.title)
        button.cell?.wraps = true
        if indent > 0 {
            let wrapper = NSView(); add(wrapper, to: stack)
            button.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(button)
            NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: indent), button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), button.topAnchor.constraint(equalTo: wrapper.topAnchor), button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)])
        } else { add(button, to: stack) }
    }
    func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); configureAction(button, symbol: symbol); return button
    }
    func configureAction(_ button: NSButton, symbol: String?) {
        button.target = self; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 13)
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading }
        button.setAccessibilityLabel(button.title)
        button.widthAnchor.constraint(equalToConstant: Self.actionWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        actionButtons.append(button)
    }
    func actionRow(_ text: String, _ button: NSButton, in stack: NSStackView) {
        let description = note(text); description.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        description.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [description, button]); row.alignment = .centerY; row.spacing = 20; row.distribution = .fill
        button.setContentHuggingPriority(.required, for: .horizontal); button.setContentCompressionResistancePriority(.required, for: .horizontal)
        add(row, to: stack)
        button.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
    }
    func buildGeneral() {
        let body = pane(.general, title: "Startup & background", subtitle: "Choose how UltraConvert opens when you sign in.")
        let startup = card("Login", symbol: "person.crop.circle", in: body)
        toggle(loginToggle, action: #selector(changeLogin), in: startup)
        status(loginStatus, text: ""); add(loginStatus, to: startup)
        toggle(minimizedToggle, action: #selector(changeMinimizedPreference), in: startup, indent: 18)
        status(minimizedHelp, text: ""); add(minimizedHelp, to: startup)
        actionRow("Manage macOS approval and login items.", button("Login Items…", #selector(openLoginSettings)), in: startup)
        let background = card("Folder rules", symbol: "square.stack.3d.up", in: body)
        add(note("Enabled rules keep working when the converter window closes. Quit UltraConvert to stop watching."), to: background)
        legacyDisclosure.setButtonType(.pushOnPushOff); legacyDisclosure.isBordered = false
        legacyDisclosure.alignment = .left; legacyDisclosure.font = .systemFont(ofSize: 13)
        legacyDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil); legacyDisclosure.imagePosition = .imageLeading
        legacyDisclosure.title = "Folder-rule startup"; legacyDisclosure.target = self; legacyDisclosure.action = #selector(toggleLegacyStartup)
        legacyDisclosure.setAccessibilityLabel("Folder-rule startup options")
        add(legacyDisclosure, to: background)
        legacyBody.orientation = .vertical; legacyBody.alignment = .leading; legacyBody.spacing = 10; legacyBody.isHidden = true
        add(legacyBody, to: background)
        toggle(menuBarToggle, action: #selector(changeMenuBarPreference), in: legacyBody)
        add(note("On other launches, keep the converter closed while enabled rules run. Opening files still shows the converter."), to: legacyBody)
    }
    func buildUpdates() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let body = pane(.updates, title: "App updates", subtitle: "Installed version \(version) · signed updates from GitHub")
        let automatic = card("Automatic updates", symbol: "arrow.triangle.2.circlepath", in: body)
        toggle(updateChecks, action: #selector(changeUpdateChecks), in: automatic)
        add(note("Checks run while UltraConvert is open. No extra background monitor."), to: automatic)
        toggle(updateDownloads, action: #selector(changeUpdateDownloads), in: automatic, indent: 18)
        status(downloadsHelp, text: ""); add(downloadsHelp, to: automatic)
        toggle(previewUpdates, action: #selector(changePreviewUpdates), in: automatic)
        add(note("Preview releases may be less stable. Leave off for regular releases."), to: automatic)
        let manual = card("Check & install", symbol: "checkmark.shield", in: body)
        updateNow.action = #selector(checkUpdates); configureAction(updateNow, symbol: nil)
        actionRow("Download, verify and install the latest app.", updateNow, in: manual)
        status(updateStatus, text: ""); add(updateStatus, to: manual)
        actionRow("Get the full installer or a repair download.", button("Open Download Page…", #selector(openReleaseDownloads)), in: manual)
        add(note("Install and Relaunch restores your queued files. Active work finishes first; save rule edits before updating. Settings and saved rules stay on this Mac."), to: manual)
        add(note("App updates leave conversion engines in place. For a Homebrew runtime update, see the installation guide; Help → Check Setup checks engine availability."), to: body)
    }
    func buildFinder() {
        let body = pane(.finder, title: "Convert from Finder", subtitle: "Select files in Finder, choose an action, then review the batch.")
        let quick = card("Quick Actions", symbol: "cursorarrow.click", in: body)
        add(note("Right-click files → Quick Actions → Convert Here with UltraConvert, or Convert to Destination with UltraConvert."), to: quick)
        toggle(finderToggle, action: #selector(changeFinderPreference), in: quick)
        add(note("Checks the actions when UltraConvert opens from Applications. Turning this off leaves existing actions installed."), to: quick)
        actionRow("Install missing actions or repair their app link.", button("Install or Repair", #selector(repairFinder)), in: quick)
        status(integrationStatus, text: "Installing an action does not enable its macOS switch."); add(integrationStatus, to: quick)
        actionRow("In Finder extensions, enable both UltraConvert actions.", button("Finder Settings…", #selector(openFinderSettings)), in: quick)
        let services = card("Format shortcuts", symbol: "list.bullet.rectangle", in: body)
        add(note("Right-click files → Services → Convert Here with UltraConvert — Choose Format… for the grouped format picker. Presets such as Convert to MP3 also open a batch for review."), to: services)
        actionRow("Refresh the app’s registered format shortcuts.", button("Refresh Shortcuts", #selector(refreshServices)), in: services)
        status(servicesStatus, text: "macOS filters shortcuts by selected file type. Use a general Quick Action if a misnamed file hides a preset."); add(servicesStatus, to: services)
        actionRow("Open Keyboard → Keyboard Shortcuts → Services.", button("Services Settings…", #selector(openServicesSettings)), in: services)
    }
    func refresh() {
        let state = login.state
        loginToggle.state = state.requested ? .on : .off; loginStatus.stringValue = state.message
        minimizedToggle.state = preferences.bool(forKey: StartupPolicy.minimizeAtLoginKey) ? .on : .off
        minimizedToggle.isEnabled = state.requested
        minimizedHelp.stringValue = state.requested ? "Keep the converter closed at login. Open it from UltraConvert’s menu bar icon. Opening files and app-update recovery still show the converter." : "Turn on Launch at login to use this option. Your choice is remembered."
        menuBarToggle.state = preferences.bool(forKey: "startInMenuBar") ? .on : .off
        finderToggle.state = preferences.object(forKey: "autoRegisterFinderActions") as? Bool != false ? .on : .off
        refreshUpdates()
    }
    func refreshUpdates() {
        guard let updates else {
            for button in [updateChecks, updateDownloads, previewUpdates, updateNow] { button.isEnabled = false }
            updateStatus.stringValue = "In-app updates are available in an installed release build."; return
        }
        updateChecks.state = updates.automaticallyChecks ? .on : .off
        updateDownloads.state = updates.automaticallyDownloads ? .on : .off; updateDownloads.isEnabled = updates.automaticallyChecks
        downloadsHelp.stringValue = updates.automaticallyChecks ? "Downloads verified updates in the background and installs on a normal quit." : "Turn on daily update checks to download automatically. Your choice is remembered."
        previewUpdates.state = updates.includesPreviews ? .on : .off
        updateNow.isEnabled = updates.canCheck; updateStatus.stringValue = updates.status
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func windowWillClose(_ notification: Notification) {
        if let app = NSApp.delegate as? ConverterApp, app.minimizedStartup, !app.window.isVisible, app.rulesController?.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }
    @objc func toggleLegacyStartup() {
        InterfaceMotion.layout(host) { legacyBody.isHidden = legacyDisclosure.state != .on }
        legacyDisclosure.image = NSImage(systemSymbolName: legacyBody.isHidden ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        if !legacyBody.isHidden { InterfaceMotion.reveal(legacyBody) }
    }
    @objc func changeMinimizedPreference() { preferences.set(minimizedToggle.state == .on, forKey: StartupPolicy.minimizeAtLoginKey) }
    @objc func changeMenuBarPreference() { preferences.set(menuBarToggle.state == .on, forKey: "startInMenuBar") }
    @objc func changeUpdateChecks() { updates?.automaticallyChecks = updateChecks.state == .on; refreshUpdates() }
    @objc func changeUpdateDownloads() { updates?.automaticallyDownloads = updateDownloads.state == .on; refreshUpdates() }
    @objc func changePreviewUpdates() { updates?.includesPreviews = previewUpdates.state == .on; refreshUpdates() }
    @objc func checkUpdates() { updates?.checkNow(); refreshUpdates() }
    @objc func openReleaseDownloads() { NSWorkspace.shared.open(URL(string: "https://github.com/samuel-zhang01/UltraConvert/releases/latest")!) }
    @objc func changeLogin() {
        do { if loginToggle.state == .on { try login.enable() } else { try login.disable() }; refresh() }
        catch { refresh(); loginStatus.stringValue = "Could not change launch at login: " + error.localizedDescription }
    }
    @objc func changeFinderPreference() {
        preferences.set(finderToggle.state == .on, forKey: "autoRegisterFinderActions")
        integrationStatus.stringValue = finderToggle.state == .on ? "Actions will be checked next time UltraConvert opens from Applications." : "Automatic repair is off. Existing actions stay installed; you can repair them here."
    }
    @objc func repairFinder() {
        do { try registerFinder(); integrationStatus.stringValue = "Quick Actions installed. Open Finder Settings and enable both UltraConvert actions." }
        catch { integrationStatus.stringValue = "Could not install Quick Actions: " + error.localizedDescription }
    }
    @objc func refreshServices() {
        do { try FormatServices.register(app: Bundle.main.bundleURL); servicesStatus.stringValue = "Format shortcuts refreshed. Open Services Settings to enable them." }
        catch { servicesStatus.stringValue = "Could not refresh format shortcuts: " + error.localizedDescription }
    }
    @objc func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc func openFinderSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!) }
    @objc func openServicesSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
}

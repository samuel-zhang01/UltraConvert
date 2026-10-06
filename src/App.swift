import AppKit

final class ConverterApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    let stack = NSStackView()
    let status = NSTextField(wrappingLabelWithString: "Choose files to convert locally.")
    let summary = NSTextField(wrappingLabelWithString: "")
    let progress = NSProgressIndicator()
    let choose = NSButton(title: "Choose Files…", target: nil, action: nil)
    let destination = NSButton(title: "Destination…", target: nil, action: nil)
    let start = NSButton(title: "Convert", target: nil, action: nil)
    let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    let reveal = NSButton(title: "Show Results", target: nil, action: nil)
    let reportButton = NSButton(title: "Show Report", target: nil, action: nil)
    let helpButton = NSButton(title: "Help", target: nil, action: nil)
    let destinationPath = NSTextField(wrappingLabelWithString: "")
    let formats = NSStackView()
    let location = NSPopUpButton()
    let saveDefault = NSButton(title: "Set as Default", target: nil, action: nil)
    let skipSame = NSButton(checkboxWithTitle: "Skip files already in target format", target: nil, action: nil)
    let openAfter = NSButton(checkboxWithTitle: "Open results when finished", target: nil, action: nil)
    let jobs = NSPopUpButton()
    let crs = NSTextField(string: "")
    var selectors: [String: NSPopUpButton] = [:]
    var files: [String] = []
    var infos: [[String: Any]] = []
    var outputURL: URL?
    var resultURL: URL?
    var resultURLs: [URL] = []
    var process: Process?
    var busy = false
    var eventBuffer = Data()
    var pendingFiles: [String] = []
    var here = true
    var lastSummary = ""
    let preferences = UserDefaults.standard
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UltraConvert")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About UltraConvert", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit UltraConvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Choose Files…", action: #selector(pickFiles), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        let hereItem = NSMenuItem(title: "Convert Here", action: #selector(convertHere), keyEquivalent: "\r")
        hereItem.keyEquivalentModifierMask = [.command]
        hereItem.target = self; fileMenu.addItem(hereItem)
        let destinationItem = NSMenuItem(title: "Convert to Folder…", action: #selector(convertToFolder), keyEquivalent: "\r")
        destinationItem.keyEquivalentModifierMask = [.command, .shift]
        destinationItem.target = self; fileMenu.addItem(destinationItem)
        fileMenu.addItem(.separator())
        addMenuItem(fileMenu, "Open Default Destination", #selector(openDefaultFolder), symbol: "folder")
        addMenuItem(fileMenu, "Show Results", #selector(showResults), symbol: "folder.badge.checkmark")
        addMenuItem(fileMenu, "Show Conversion Report", #selector(showReport), symbol: "doc.text")
        addMenuItem(fileMenu, "Copy Result Summary", #selector(copySummary), symbol: "doc.on.doc")
        fileMenuItem.submenu = fileMenu
        menu.addItem(fileMenuItem)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editMenuItem.submenu = editMenu
        menu.addItem(editMenuItem)
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        addMenuItem(helpMenu, "Quick Start", #selector(showQuickStart), symbol: "questionmark.circle")
        addMenuItem(helpMenu, "Installation and User Guide", #selector(openGuide), symbol: "book")
        addMenuItem(helpMenu, "Check Setup…", #selector(checkSetup), symbol: "checkmark.shield")
        addMenuItem(helpMenu, "Finder Action Settings…", #selector(openFinderSettings), symbol: "gearshape")
        helpMenuItem.submenu = helpMenu; menu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 510),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "UltraConvert"
        window.delegate = self
        window.center()
        window.minSize = NSSize(width: 600, height: 480)
        let content = window.contentView!
        let body = NSScrollView()
        body.hasVerticalScroller = true
        body.autohidesScrollers = true
        body.drawsBackground = false
        body.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(body)
        let canvas = FlippedView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        body.documentView = canvas
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(stack)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            body.topAnchor.constraint(equalTo: content.topAnchor),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: body.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -24)
        ])
        let title = NSTextField(labelWithString: "UltraConvert")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let spacer = NSView()
        let heading = NSStackView(views: [icon, title, spacer, helpButton]); heading.spacing = 12
        helpButton.bezelStyle = .helpButton
        helpButton.target = self; helpButton.action = #selector(showQuickStart)
        helpButton.toolTip = "Quick start, installation help and Finder settings"
        stack.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let intro = NSTextField(wrappingLabelWithString: "Select one or many files. Formats are detected from their contents where possible. Originals stay in place.")
        stack.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 610, height: 90))
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: 12)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        formats.orientation = .vertical
        formats.alignment = .leading
        formats.spacing = 8
        stack.addArrangedSubview(formats)
        location.addItems(withTitles: ["Convert beside each source", "Use default destination", "Choose destination…"])
        location.target = self; location.action = #selector(locationChanged)
        saveDefault.target = self; saveDefault.action = #selector(saveDefaultFolder)
        let outputRow = NSStackView(views: [location, destination, saveDefault]); outputRow.spacing = 10
        stack.addArrangedSubview(outputRow)
        destinationPath.font = .systemFont(ofSize: 11)
        destinationPath.textColor = .secondaryLabelColor
        destinationPath.isSelectable = true
        stack.addArrangedSubview(destinationPath)
        destinationPath.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        jobs.toolTip = "Run up to four files at once. Two jobs suit most batches; use one for large media or GIS files."
        skipSame.toolTip = "Already-matching files are recorded as skipped and stay in their original folder."
        skipSame.state = preferences.bool(forKey: "skipSame") ? .on : .off
        openAfter.state = preferences.bool(forKey: "openAfter") ? .on : .off
        jobs.addItems(withTitles: ["1 job", "2 jobs", "3 jobs", "4 jobs"])
        jobs.selectItem(at: max(0, min(3, preferences.integer(forKey: "jobs") == 0 ? 1 : preferences.integer(forKey: "jobs") - 1)))
        let options = NSStackView(views: [skipSame, jobs]); options.spacing = 12
        stack.addArrangedSubview(options)
        stack.addArrangedSubview(openAfter)
        crs.placeholderString = "Known input CRS, e.g. EPSG:4326 (required for WKT without .prj or SRID)"
        crs.isHidden = true
        stack.addArrangedSubview(crs)
        crs.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progress.minValue = 0
        progress.maxValue = 1
        progress.isIndeterminate = false
        progress.style = .bar
        stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(summary)
        summary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let buttons = NSStackView(views: [choose, start, cancel, reveal, reportButton])
        buttons.spacing = 10
        buttons.orientation = .horizontal
        stack.addArrangedSubview(buttons)
        choose.target = self; choose.action = #selector(pickFiles)
        destination.target = self; destination.action = #selector(pickDestination)
        start.target = self; start.action = #selector(convertFiles)
        cancel.target = self; cancel.action = #selector(cancelConversion)
        reveal.target = self; reveal.action = #selector(showResults)
        reportButton.target = self; reportButton.action = #selector(showReport)
        for (button, symbol) in [(choose, "doc.badge.plus"), (destination, "folder"), (start, "arrow.triangle.2.circlepath"), (cancel, "xmark"), (reveal, "folder.badge.checkmark"), (reportButton, "doc.text")] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
        }
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        cancel.isEnabled = false
        start.isEnabled = false
        reveal.isHidden = true
        reportButton.isHidden = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        var args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
        here = preferences.string(forKey: "outputMode") != "destination"
        if args.count >= 2 && args[0] == "--mode" {
            here = args[1] == "here"
            args.removeFirst(2)
        }
        if args.first == "--" { args.removeFirst() }
        outputURL = defaultFolder()
        refreshDestination()
        if !args.isEmpty { loadFiles(args) }
        else if !files.isEmpty { loadFiles(files) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if busy { pendingFiles = filenames }
        else {
            files = filenames
            if window != nil { loadFiles(filenames) }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func pickFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose files for local batch conversion"
        if let path = preferences.string(forKey: "lastSourceFolder") { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK { loadFiles(panel.urls.map(\.path)) }
    }

    @objc func pickDestination() {
        _ = chooseFolder()
    }

    func chooseFolder() -> Bool {
        guard !busy else { return false }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "A new Converted folder will be created here for this batch."
        panel.directoryURL = outputURL ?? defaultFolder()
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
            here = false
            location.selectItem(at: 2)
            refreshDestination()
            return true
        }
        return false
    }

    func defaultFolder() -> URL {
        if let path = preferences.string(forKey: "defaultFolder") { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/UltraConvert")
    }

    func refreshDestination() {
        if here { location.selectItem(at: 0) }
        else if outputURL == defaultFolder() { location.selectItem(at: 1) }
        destination.title = "Choose Folder…"
        destinationPath.stringValue = here ? "A new Converted folder beside each source folder." : "Destination: \((outputURL ?? defaultFolder()).path)"
        destination.toolTip = here ? "A separate output folder is created beside files in each source folder." : outputURL?.path
        saveDefault.isEnabled = !busy && !here
    }

    @objc func locationChanged() {
        guard !busy else { return }
        switch location.indexOfSelectedItem {
        case 0: here = true
        case 1: here = false; outputURL = defaultFolder()
        default: pickDestination()
        }
        refreshDestination()
    }

    @objc func saveDefaultFolder() {
        syncLocationSelection()
        if let url = outputURL, !here {
            preferences.set(url.path, forKey: "defaultFolder")
            refreshDestination()
            status.stringValue = "Default destination saved: \(url.lastPathComponent)."
        }
    }

    func syncLocationSelection() {
        if location.indexOfSelectedItem == 0 { here = true }
        else if location.indexOfSelectedItem == 1 { here = false; outputURL = defaultFolder() }
        refreshDestination()
    }

    @objc func convertHere() { guard !busy else { return }; here = true; refreshDestination(); convertFiles() }
    @objc func convertToFolder() { guard !busy else { return }; if chooseFolder() { convertFiles() } }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(pickFiles) || menuItem.action == #selector(checkSetup) { return !busy }
        if menuItem.action == #selector(convertHere) || menuItem.action == #selector(convertToFolder) { return !busy && !selectors.isEmpty }
        if menuItem.action == #selector(showResults) || menuItem.action == #selector(showReport) { return resultURL != nil }
        if menuItem.action == #selector(copySummary) { return !lastSummary.isEmpty }
        return true
    }

    func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector, symbol: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
    }

    @objc func openGuide() { NSWorkspace.shared.open(URL(string: "https://github.com/samuel-zhang01/UltraConvert#readme")!) }

    @objc func openFinderSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    @objc func showQuickStart() {
        let alert = NSAlert()
        alert.messageText = "Convert your first batch"
        alert.informativeText = "1. Click Choose Files, or select files in Finder → right-click → Quick Actions → UltraConvert.\n2. Choose an output format for each detected category.\n3. Select beside sources, your default destination, or a chosen folder.\n4. Click Convert, then Show Results or Show Report.\n\nBoth Finder actions accept multiple files. Originals stay in place.\n\nEnable the two actions in System Settings → General → Login Items & Extensions → Finder (ⓘ)."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Full Guide")
        alert.addButton(withTitle: "Finder Settings")
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { self.openGuide() }
            if response == .alertThirdButtonReturn { self.openFinderSettings() }
        }
    }

    @objc func openDefaultFolder() {
        let url = defaultFolder()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch { status.stringValue = "Could not open default destination: \(error.localizedDescription)" }
    }

    @objc func showReport() {
        let reports = (resultURLs.isEmpty ? [resultURL].compactMap { $0 } : resultURLs)
            .map { $0.appendingPathComponent("conversion-report.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if reports.isEmpty { status.stringValue = "The report was moved or removed. Use Show Results to find the output folder." }
        else { NSWorkspace.shared.activateFileViewerSelecting(Array(reports.prefix(8))) }
    }

    @objc func copySummary() {
        guard !lastSummary.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastSummary, forType: .string)
        status.stringValue = "Result summary copied."
    }

    @objc func checkSetup() {
        guard !busy else { return }
        setBusy(true)
        status.stringValue = "Checking local engines and Finder action files…"
        launch([], script: "diagnostics.py") { _, output, error in
            self.setBusy(false)
            defer { self.loadPendingFiles() }
            guard let data = output.data(using: .utf8),
                  let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let checks = report["checks"] as? [[String: Any]] else {
                self.status.stringValue = "Setup check could not run: \(error.suffix(600))"
                return
            }
            let ready = report["ok"] as? Bool == true
            self.status.stringValue = ready ? "Setup checks passed. Finder switches are managed in System Settings." : "Setup needs attention. See the checks below."
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let text = "UltraConvert \(version)\n\(report["environment"] ?? "")\n\n" + checks.map {
                "\($0["ok"] as? Bool == true ? "✓" : "⚠") \($0["name"] ?? "Check"): \($0["detail"] ?? "")"
            }.joined(separator: "\n\n") + "\n\n\(report["note"] ?? "")"
            let alert = NSAlert()
            alert.messageText = ready ? "Your local setup is ready" : "Repair your setup"
            alert.informativeText = "These checks run locally. Copying does not send anything."
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 490, height: 270))
            scroll.hasVerticalScroller = true
            let view = NSTextView(frame: scroll.bounds)
            view.string = text; view.isEditable = false; view.isSelectable = true
            view.font = .systemFont(ofSize: 12)
            view.autoresizingMask = [.width]; view.isVerticallyResizable = true
            view.textContainer?.widthTracksTextView = true
            scroll.documentView = view; alert.accessoryView = scroll
            alert.addButton(withTitle: "Done")
            alert.addButton(withTitle: "Copy Setup Report")
            alert.addButton(withTitle: "Finder Settings")
            alert.beginSheetModal(for: self.window) { response in
                if response == .alertSecondButtonReturn {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    self.status.stringValue = "Setup report copied. Nothing was uploaded."
                }
                if response == .alertThirdButtonReturn { self.openFinderSettings() }
            }
        }
    }

    func loadPendingFiles() {
        if !pendingFiles.isEmpty && !busy { let next = pendingFiles; pendingFiles = []; loadFiles(next) }
    }

    func setBusy(_ value: Bool) {
        busy = value
        choose.isEnabled = !value
        destination.isEnabled = !value
        start.isEnabled = !value && !selectors.isEmpty
        cancel.isEnabled = value
        for control in selectors.values { control.isEnabled = !value }
        crs.isEnabled = !value
        location.isEnabled = !value
        jobs.isEnabled = !value
        skipSame.isEnabled = !value
        openAfter.isEnabled = !value
        saveDefault.isEnabled = !value && !here
    }

    func launch(_ args: [String], script: String = "convert.py", completion: @escaping (Int32, String, String) -> Void) {
        let task = Process()
        task.executableURL = support.appendingPathComponent(".venv/bin/python")
        task.arguments = [support.appendingPathComponent("src/\(script)").path] + args
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        task.environment = env
        guard FileManager.default.isExecutableFile(atPath: task.executableURL!.path) else {
            completion(1, "", "The conversion runtime is missing. Run python3 install.py from the UltraConvert repository.")
            return
        }
        let stdout = Pipe(), stderr = Pipe()
        task.standardOutput = stdout; task.standardError = stderr
        process = task
        eventBuffer = Data()
        do { try task.run() }
        catch { process = nil; completion(1, "", error.localizedDescription); return }
        let stderrGroup = DispatchGroup()
        let stderrCapture = LockedCapture()
        stderrGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = stderr.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                stderrCapture.append(chunk)
            }
            stderrGroup.leave()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var data = Data()
            while true {
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
                if data.count > 8 * 1024 * 1024 { data.removeFirst(data.count - 8 * 1024 * 1024) }
                DispatchQueue.main.async { self.handleEvents(chunk) }
            }
            task.waitUntilExit()
            stderrGroup.wait()
            DispatchQueue.main.async {
                self.process = nil
                completion(task.terminationStatus, String(data: data, encoding: .utf8) ?? "", stderrCapture.text())
            }
        }
    }

    func loadFiles(_ selected: [String]) {
        guard !busy else { pendingFiles = selected; return }
        files = selected
        infos = []; selectors.removeAll()
        formats.arrangedSubviews.forEach { formats.removeArrangedSubview($0); $0.removeFromSuperview() }
        resultURL = nil; resultURLs = []; lastSummary = ""
        reportButton.isHidden = true
        crs.stringValue = ""; crs.isHidden = true
        if let first = selected.first { preferences.set(URL(fileURLWithPath: first).deletingLastPathComponent().path, forKey: "lastSourceFolder") }
        setBusy(true)
        status.stringValue = "Recognising \(selected.count) file(s)…"
        summary.stringValue = ""
        progress.isIndeterminate = true; progress.startAnimation(nil)
        reveal.isHidden = true
        launch(["--inspect", "--jobs", String(jobs.indexOfSelectedItem + 1), "--"] + files) { code, output, error in
            defer { self.loadPendingFiles() }
            self.progress.stopAnimation(nil); self.progress.isIndeterminate = false
            self.setBusy(false)
            guard code == 0, let data = output.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let infos = parsed["files"] as? [[String: Any]] else {
                self.status.stringValue = "Could not inspect files: \(error.suffix(1200))"
                self.start.isEnabled = false
                return
            }
            self.infos = infos
            self.buildSelectors()
        }
    }

    func buildSelectors() {
        formats.arrangedSubviews.forEach { formats.removeArrangedSubview($0); $0.removeFromSuperview() }
        selectors.removeAll()
        var groups: [String: [[String: Any]]] = [:]
        for info in infos where info["error"] is NSNull {
            groups[info["category"] as? String ?? "", default: []].append(info)
        }
        let defaults = ["image": "png", "geo": "gpkg", "document": "docx", "audio": "flac", "video": "mp4", "config": "json"]
        for key in ["image", "document", "video", "audio", "geo", "config"] {
            guard let items = groups[key], let initial = items.first?["targets"] as? [String] else { continue }
            let common = initial.filter { target in items.allSatisfy { ($0["targets"] as? [String] ?? []).contains(target) } }
            let names = ["image": "Images", "document": "Documents & ebooks", "video": "Video", "audio": "Audio", "geo": "Geospatial", "config": "Configuration"]
            let symbols = ["image": "photo", "document": "doc.text", "video": "film", "audio": "waveform", "geo": "map", "config": "curlybraces"]
            let image = NSImageView(image: NSImage(systemSymbolName: symbols[key]!, accessibilityDescription: nil)!)
            image.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let label = NSTextField(labelWithString: "\(names[key]!) (\(items.count)) →")
            label.widthAnchor.constraint(equalToConstant: 180).isActive = true
            let popup = NSPopUpButton()
            popup.addItems(withTitles: common.map { $0 == "alac" ? "ALAC (lossless .m4a)" : $0.uppercased() })
            for (index, format) in common.enumerated() { popup.item(at: index)?.representedObject = format }
            let remembered = preferences.dictionary(forKey: "formats") as? [String: String] ?? [:]
            if let preferred = remembered[key] ?? defaults[key], let index = common.firstIndex(of: preferred) { popup.selectItem(at: index) }
            popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let row = NSStackView(views: [image, label, popup]); row.spacing = 10
            formats.addArrangedSubview(row)
            selectors[key] = popup
        }
        if let scroll = stack.arrangedSubviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
           let text = scroll.documentView as? NSTextView {
            text.string = infos.map { info in
                if let error = info["error"] as? String { return "⚠ \(info["name"] ?? "file"): \(error)" }
                return "\(info["name"] ?? "file")  ·  \((info["format"] as? String ?? "").uppercased())  ·  \(info["category"] ?? "")"
            }.joined(separator: "\n")
        }
        crs.isHidden = groups["geo"] == nil
        let failed = infos.filter { $0["error"] is String }.count
        status.stringValue = "\(infos.count - failed) recognised, \(failed) unsupported. Choose formats, then Convert."
        summary.stringValue = "New output folder; no overwrites. Documents may reflow. Media uses first tracks; lossy formats re-encode. GIS limitations appear in the report."
        start.isEnabled = !selectors.isEmpty
        refreshDestination()
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        window.setContentSize(NSSize(width: 720, height: min(available - 70, CGFloat(max(650, 580 + 40 * selectors.count)))))
    }

    @objc func convertFiles() {
        guard !busy && !selectors.isEmpty else { return }
        resultURL = nil; resultURLs = []; lastSummary = ""
        reveal.isHidden = true; reportButton.isHidden = true
        syncLocationSelection()
        var plan: [String: String] = [:]
        for (key, popup) in selectors { plan[key] = popup.selectedItem?.representedObject as? String }
        var remembered = preferences.dictionary(forKey: "formats") as? [String: String] ?? [:]
        remembered.merge(plan) { _, new in new }
        preferences.set(remembered, forKey: "formats")
        preferences.set(here ? "here" : "destination", forKey: "outputMode")
        preferences.set(skipSame.state == .on, forKey: "skipSame")
        preferences.set(openAfter.state == .on, forKey: "openAfter")
        preferences.set(jobs.indexOfSelectedItem + 1, forKey: "jobs")
        let planURL = FileManager.default.temporaryDirectory.appendingPathComponent("ultraconvert-plan-\(UUID().uuidString).json")
        do { try JSONSerialization.data(withJSONObject: plan).write(to: planURL) }
        catch { status.stringValue = error.localizedDescription; return }
        setBusy(true)
        progress.doubleValue = 0
        status.stringValue = "Converting…"
        summary.stringValue = "You can cancel. Completed outputs will be kept."
        var args = ["--plan", planURL.path, "--jobs", String(jobs.indexOfSelectedItem + 1)]
        args += here ? ["--here"] : ["--output", (outputURL ?? defaultFolder()).path]
        if skipSame.state == .on { args += ["--skip-same"] }
        if !crs.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { args += ["--source-crs", crs.stringValue.trimmingCharacters(in: .whitespaces)] }
        launch(args + ["--"] + files) { code, output, error in
            defer { self.loadPendingFiles() }
            try? FileManager.default.removeItem(at: planURL)
            self.setBusy(false)
            let lines = output.split(separator: "\n")
            let final = lines.compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }.last(where: { $0["event"] as? String == "complete" })
            if let report = final {
                self.resultURL = URL(fileURLWithPath: report["output"] as? String ?? "")
                self.resultURLs = (report["outputs"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
                self.status.stringValue = "\(report["success"] ?? 0) converted, \(report["skipped"] ?? 0) skipped, \(report["failed"] ?? 0) failed. \(code == 130 ? "Cancelled." : "")"
                let results = report["results"] as? [[String: Any]] ?? []
                let errors = results.compactMap { item -> String? in
                    guard let error = item["error"] as? String else { return nil }
                    return "\(item["name"] ?? "file"): \(error)"
                }
                self.summary.stringValue = errors.isEmpty ? "Saved in \(self.resultURLs.count) output folder(s). Originals retained. Each folder has conversion-report.json with format notes." : String(errors.joined(separator: "\n").prefix(850))
                self.reveal.isHidden = false
                self.reportButton.isHidden = false
                self.lastSummary = "UltraConvert: \(report["success"] ?? 0) converted, \(report["skipped"] ?? 0) skipped, \(report["failed"] ?? 0) failed.\(code == 130 ? " Cancelled." : "")"
                self.progress.doubleValue = 1
                if self.openAfter.state == .on { self.showResults() }
            } else {
                self.status.stringValue = "Conversion stopped (exit \(code))."
                self.summary.stringValue = String(error.suffix(1200))
            }
        }
    }

    func handleEvents(_ chunk: Data) {
        eventBuffer.append(chunk)
        if eventBuffer.count > 8 * 1024 * 1024 { eventBuffer.removeAll(); return }
        while let newline = eventBuffer.firstIndex(of: 10) {
            let data = eventBuffer[..<newline]
            eventBuffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if event["event"] as? String == "file", let completed = event["completed"] as? Double, let total = event["total"] as? Double {
                progress.doubleValue = completed / max(total, 1)
                let result = event["result"] as? [String: Any] ?? [:]
                status.stringValue = "\(Int(completed))/\(Int(total)): \(result["name"] ?? "file")"
            }
        }
    }

    @objc func cancelConversion() { process?.terminate(); status.stringValue = "Cancelling…"; cancel.isEnabled = false }
    @objc func showResults() {
        if resultURLs.count > 1 { NSWorkspace.shared.activateFileViewerSelecting(Array(resultURLs.prefix(8))) }
        else if let url = resultURL { NSWorkspace.shared.open(url) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if busy { cancelConversion(); return false }; NSApp.terminate(nil); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { if busy { cancelConversion(); return .terminateCancel }; return .terminateNow }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class LockedCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 64 * 1024 { data.removeFirst(data.count - 64 * 1024) }
    }
    func text() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

let app = NSApplication.shared
// Install file icons before the staged workflows are swapped into place. Finder
// Settings uses their document icons, independently of the Quick Action image.
if CommandLine.arguments.dropFirst().first == "--brand-workflows" {
    guard let iconURL = Bundle.main.url(forResource: "UltraConvert", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL), CommandLine.arguments.count > 2 else { exit(1) }
    for path in CommandLine.arguments.dropFirst(2) {
        let url = URL(fileURLWithPath: path)
        let marker = url.appendingPathComponent("Contents/ultraconvert-managed.json")
        guard url.pathExtension == "workflow",
              let data = try? Data(contentsOf: marker),
              let owner = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              owner["owner"] == "UltraConvert",
              NSWorkspace.shared.setIcon(icon, forFile: path, options: []) else { exit(1) }
    }
    exit(0)
}
let delegate = ConverterApp()
app.delegate = delegate
app.run()

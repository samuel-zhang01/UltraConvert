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
        fileMenuItem.submenu = fileMenu
        menu.addItem(fileMenuItem)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editMenuItem.submenu = editMenu
        menu.addItem(editMenuItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 510),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "UltraConvert"
        window.delegate = self
        window.center()
        window.minSize = NSSize(width: 600, height: 480)
        let content = window.contentView!
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        let title = NSTextField(labelWithString: "UltraConvert")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let heading = NSStackView(views: [icon, title]); heading.spacing = 12
        stack.addArrangedSubview(heading)
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
        let outputRow = NSStackView(views: [location, saveDefault]); outputRow.spacing = 10
        stack.addArrangedSubview(outputRow)
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
        let buttons = NSStackView(views: [choose, destination, start, cancel, reveal])
        buttons.spacing = 10
        buttons.orientation = .horizontal
        stack.addArrangedSubview(buttons)
        choose.target = self; choose.action = #selector(pickFiles)
        destination.target = self; destination.action = #selector(pickDestination)
        start.target = self; start.action = #selector(convertFiles)
        cancel.target = self; cancel.action = #selector(cancelConversion)
        reveal.target = self; reveal.action = #selector(showResults)
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        cancel.isEnabled = false
        start.isEnabled = false
        reveal.isHidden = true
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
        destination.title = here ? "Destination: beside sources" : "Destination: \(outputURL?.lastPathComponent ?? "Choose…")"
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
        if menuItem.action == #selector(pickFiles) { return !busy }
        if menuItem.action == #selector(convertHere) || menuItem.action == #selector(convertToFolder) { return !busy && !selectors.isEmpty }
        return true
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

    func launch(_ args: [String], completion: @escaping (Int32, String, String) -> Void) {
        let task = Process()
        task.executableURL = support.appendingPathComponent(".venv/bin/python")
        task.arguments = [support.appendingPathComponent("src/convert.py").path] + args
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
        catch { completion(1, "", error.localizedDescription); return }
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
            let label = NSTextField(labelWithString: "\(key.capitalized) (\(items.count)) →")
            label.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let popup = NSPopUpButton()
            popup.addItems(withTitles: common.map { $0 == "alac" ? "ALAC (lossless .m4a)" : $0.uppercased() })
            for (index, format) in common.enumerated() { popup.item(at: index)?.representedObject = format }
            let remembered = preferences.dictionary(forKey: "formats") as? [String: String] ?? [:]
            if let preferred = remembered[key] ?? defaults[key], let index = common.firstIndex(of: preferred) { popup.selectItem(at: index) }
            popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let row = NSStackView(views: [label, popup]); row.spacing = 10
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
        window.setContentSize(NSSize(width: 680, height: max(610, 530 + 40 * selectors.count)))
    }

    @objc func convertFiles() {
        guard !busy && !selectors.isEmpty else { return }
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
let delegate = ConverterApp()
app.delegate = delegate
app.run()

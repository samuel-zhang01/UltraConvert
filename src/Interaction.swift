import AppKit

// Finder Services select a format and open a reviewable batch. The normal engine
// inspection, preservation rules and explicit Convert button remain in the path.
extension ConverterApp: NSMenuDelegate {
    @objc func prepareConversion(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let allowed = FormatCatalog.all.union(["choose"])
        guard let format = userData, allowed.contains(format) else {
            error.pointee = "This format shortcut is unavailable."; return
        }
        guard !busy else {
            error.pointee = "UltraConvert is processing a batch. Wait for it to finish or cancel, then try again."; return
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let paths = uniquePaths(urls.map(\.path))
        guard !paths.isEmpty && paths.count <= 1000 else {
            error.pointee = "Select between 1 and 1,000 files in Finder."; return
        }
        if format == "choose" {
            formatPicker = FormatPicker(count: paths.count, choose: { [weak self] target in
                guard let self else { return }; guard !self.busy else { self.status.stringValue = "A batch is running. Wait or cancel, then choose a format again."; return }; self.presetFormat = target; self.here = true; self.refreshDestination(); self.loadFiles(paths); self.showConverter()
            })
            formatPicker?.showWindow(nil); formatPicker?.window?.makeKeyAndOrderFront(nil); NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
            return
        }
        presetFormat = format
        here = true
        refreshDestination()
        loadFiles(paths)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.filter { seen.insert($0).inserted }
    }

    func queuePendingFiles(_ paths: [String]) {
        let combined = uniquePaths(pendingFiles + paths)
        guard combined.count <= 1000 else {
            status.stringValue = "Incoming selection exceeds 1,000 files; the current batch continues."; return
        }
        pendingFiles = combined
    }

    func resetOutcomes() {
        outcomeRefresh?.cancel(); outcomeRefresh = nil
        changedRows = []
        outcomes = [:]; outputBySource = [:]; failedPaths = []
    }

    func scheduleOutcomeRefresh() {
        guard outcomeRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flushOutcomeChanges() }
        outcomeRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func flushOutcomeChanges() {
        outcomeRefresh?.cancel(); outcomeRefresh = nil
        let valid = changedRows.filter { $0 < queueRows.count }
        changedRows = []
        guard !valid.isEmpty else { return }
        fileTable.reloadData(forRowIndexes: IndexSet(valid), columnIndexes: IndexSet(integer: 0))
        queueReloadCount += 1
        refreshPresentation()
    }

    @objc func retryFailed() {
        guard !busy && !failedPaths.isEmpty else { return }
        // Recognition runs again before the user starts a retry; changed files
        // never bypass source fingerprints or the normal destination review.
        loadFiles(failedPaths)
    }

    var selectedQueuePaths: [String] {
        fileTable.selectedRowIndexes.compactMap { queueRows.indices.contains($0) ? queueRows[$0]["path"] as? String : nil }
    }

    func buildQueueMenu() {
        let menu = NSMenu(title: "File actions")
        menu.delegate = self
        let conversion = NSMenuItem(title: "Review Selected Files Here as", action: nil, keyEquivalent: "")
        conversion.submenu = FormatCatalog.menu(target: self, action: #selector(contextConvert(_:)))
        menu.addItem(conversion); menu.addItem(.separator())
        addMenuItem(menu, "Reveal Original in Finder", #selector(revealSources), symbol: "folder")
        addMenuItem(menu, "Show Converted File", #selector(revealSelectedOutputs), symbol: "folder.badge.checkmark")
        menu.addItem(.separator())
        addMenuItem(menu, "Copy File Names", #selector(copyFileNames), symbol: "doc.on.doc")
        addMenuItem(menu, "Copy Error Details", #selector(copyErrors), symbol: "exclamationmark.bubble")
        menu.addItem(.separator())
        addMenuItem(menu, "Remove from Queue", #selector(removeSelectedFiles), symbol: "minus.circle")
        fileTable.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = fileTable.clickedRow
        if queueRows.indices.contains(row) && !fileTable.selectedRowIndexes.contains(row) {
            fileTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    @objc func contextConvert(_ sender: NSMenuItem) {
        guard !busy, let format = sender.representedObject as? String, !selectedQueuePaths.isEmpty else { return }
        let selected = selectedQueuePaths
        guard FormatCatalog.all.contains(format), selected.allSatisfy({ path in
            guard let row = rowByPath[path], queueRows.indices.contains(row), queueRows[row]["error"] is NSNull else { return false }
            return (queueRows[row]["targets"] as? [String])?.contains(format) == true
        }) else {
            status.stringValue = "That format is not compatible with every selected file. Select compatible files, or choose an output format for each category."
            return
        }
        presetFormat = format; here = true; refreshDestination(); loadFiles(selected)
    }

    func contextActionEnabled(_ action: Selector?) -> Bool? {
        let paths = selectedQueuePaths
        switch action {
        case #selector(revealSources), #selector(copyFileNames): return !paths.isEmpty
        case #selector(revealSelectedOutputs): return paths.contains { outputBySource[$0] != nil }
        case #selector(copyErrors): return paths.contains { path in
            outcomes[path]?.failed == true || rowByPath[path].map { queueRows[$0]["error"] is String } == true
        }
        case #selector(removeSelectedFiles): return !busy && !paths.isEmpty
        default: return nil
        }
    }

    @objc func revealSources() {
        let urls = selectedQueuePaths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        if urls.isEmpty { status.stringValue = "The selected originals were moved or removed." }
        else { NSWorkspace.shared.activateFileViewerSelecting(Array(urls.prefix(8))) }
    }

    @objc func revealSelectedOutputs() {
        let urls = selectedQueuePaths.compactMap { outputBySource[$0] }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { status.stringValue = "The selected output was moved or removed." }
        else { NSWorkspace.shared.activateFileViewerSelecting(Array(urls.prefix(8))) }
    }

    func copyQueueText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status.stringValue = "Copied. Nothing was uploaded."
    }

    @objc func copyFileNames() {
        copyQueueText(selectedQueuePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n"))
    }

    @objc func copyErrors() {
        let text = selectedQueuePaths.compactMap { path -> String? in
            let error = outcomes[path].flatMap { $0.failed ? $0.text : nil } ?? rowByPath[path].flatMap { queueRows[$0]["error"] as? String }
            return error.map { URL(fileURLWithPath: path).lastPathComponent + ": " + $0 }
        }.joined(separator: "\n")
        copyQueueText(text)
    }
}

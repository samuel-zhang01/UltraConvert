import AppKit

// Exercise the real AppKit hierarchy with content inspection from the public fixtures.
// In particular, activating constraints before attaching category views used to abort.
@main
struct InterfaceSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let inspected = report["files"] as! [[String: Any]]
        precondition(inspected.count == 6 && inspected.allSatisfy { $0["error"] is NSNull })
        let app = ConverterApp()
        app.buildInterface()
        precondition(app.fileTable.numberOfRows == 0)
        for selection in [Array(inspected.prefix(1)), inspected, Array(inspected.suffix(2)), inspected] {
            app.infos = selection
            app.files = selection.compactMap { $0["path"] as? String }
            app.buildSelectors()
            app.window.contentView!.layoutSubtreeIfNeeded()
            let categories = Set(selection.compactMap { $0["category"] as? String })
            precondition(Set(app.selectors.keys) == categories)
            precondition(app.fileTable.numberOfRows == selection.count)
            precondition(app.start.isEnabled && app.queueEmpty.isHidden)
            precondition(app.selectors.values.allSatisfy { $0.numberOfItems > 0 })
        }
        app.optionsDisclosure.state = .on
        app.toggleOptions()
        app.window.setContentSize(NSSize(width: 760, height: 570))
        app.window.contentView!.layoutSubtreeIfNeeded()
        precondition(!app.optionsBody.isHidden && app.queueSurface.frame.width > 0)
        precondition(app.start.frame.width >= 155)
        app.failedPaths = ["/tmp/failed.png"]
        app.reportButton.isHidden = false; app.reveal.isHidden = false
        app.phase = .attention
        app.window.contentView!.layoutSubtreeIfNeeded()
        for button in [app.start, app.reportButton, app.reveal, app.retryButton] {
            let bounds = button.convert(button.bounds, to: app.window.contentView)
            precondition(bounds.minX >= 0 && bounds.maxX <= app.window.contentView!.bounds.width)
            precondition(bounds.minY >= 0 && bounds.maxY <= app.window.contentView!.bounds.height)
        }
        // Presets choose compatible targets without starting a conversion and
        // surface an unavailable target rather than silently selecting it.
        let image = inspected.first { $0["category"] as? String == "image" }!
        app.infos = [image]; app.files = [image["path"] as! String]
        app.presetFormat = "webp"
        app.buildSelectors()
        precondition(app.selectors["image"]?.selectedItem?.representedObject as? String == "webp")
        precondition(app.presetFormat == nil && !app.busy)
        app.presetFormat = "mp3"
        app.buildSelectors()
        precondition(app.status.stringValue.contains("does not suit"))

        // Context presets apply to every selected file. Real video and audio
        // inspection fixtures share MP3; reviewing them still starts no conversion.
        let audio = inspected.first { $0["category"] as? String == "audio" }!
        let video = inspected.first { $0["category"] as? String == "video" }!
        let mp3Item = app.fileTable.menu!.items[0].submenu!.items[0].submenu!.items.first {
            $0.representedObject as? String == "mp3"
        }!
        precondition(app.fileTable.menu!.items[0].title == "Review Selected Files Here as")
        app.infos = [video, audio]; app.files = app.infos.compactMap { $0["path"] as? String }
        app.presetFormat = "mp3"
        app.buildSelectors()
        app.fileTable.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        precondition(app.validateMenuItem(mp3Item))
        precondition(Set(app.selectors.keys) == ["video", "audio"])
        precondition(app.selectors.values.allSatisfy { $0.selectedItem?.representedObject as? String == "mp3" })
        precondition(app.start.isEnabled && !app.busy && app.process == nil && app.presetFormat == nil)

        // Mixed categories and unsupported items cannot silently fall back to a
        // second target, even when the handler is invoked without menu validation.
        let unsupported: [String: Any] = ["path": "/tmp/unsupported.wav", "name": "unsupported.wav",
            "category": "audio", "targets": ["mp3"], "error": "Unsupported audio"]
        for selection in [[image, audio], [audio, unsupported]] {
            app.infos = selection; app.files = selection.compactMap { $0["path"] as? String }
            app.buildSelectors()
            app.fileTable.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
            app.here = false
            app.outputURL = URL(fileURLWithPath: "/tmp/UltraConvert-context-review")
            app.location.selectItem(at: 2); app.refreshDestination()
            let filesBefore = app.files, selectedBefore = app.selectedQueuePaths
            let queueBefore = try JSONSerialization.data(withJSONObject: app.queueRows, options: .sortedKeys)
            let targetsBefore = app.selectors.mapValues { $0.selectedItem?.representedObject as? String }
            let destinationBefore = app.outputURL, destinationText = app.destinationPath.stringValue
            precondition(!app.validateMenuItem(mp3Item))
            app.contextConvert(mp3Item)
            precondition(app.files == filesBefore && app.selectedQueuePaths == selectedBefore)
            let queueAfter = try JSONSerialization.data(withJSONObject: app.queueRows, options: .sortedKeys)
            precondition(queueAfter == queueBefore)
            precondition(app.selectors.mapValues { $0.selectedItem?.representedObject as? String } == targetsBefore)
            precondition(!app.here && app.outputURL == destinationBefore && app.destinationPath.stringValue == destinationText)
            precondition(app.presetFormat == nil && !app.busy && app.process == nil)
            precondition(app.status.stringValue.contains("every selected file"))
        }
        app.fileTable.deselectAll(nil)
        precondition(!app.validateMenuItem(mp3Item))
        // A Finder preset for a mixed selection must not silently choose other
        // category defaults. Every conversion entry point stays blocked until
        // the user explicitly chooses compatible per-category formats.
        let audioForPreset = inspected.first { $0["category"] as? String == "audio" }!
        app.infos = [image, audioForPreset]; app.files = app.infos.compactMap { $0["path"] as? String }
        app.presetFormat = "mp3"; app.buildSelectors()
        precondition(app.rejectedPreset == "mp3" && app.phase == .attention && !app.start.isEnabled && app.status.stringValue.contains("every selected file"))
        app.convertFiles(); precondition(!app.busy && app.process == nil)
        let blockedHere = NSMenuItem(title: "Convert Here", action: #selector(app.convertHere), keyEquivalent: "")
        precondition(!app.validateMenuItem(blockedHere))
        app.setBusy(true); app.setBusy(false); precondition(!app.start.isEnabled)
        let audioSelector = app.selectors["audio"]!; audioSelector.select(audioSelector.itemArray.first { $0.representedObject as? String == "mp3" }!); app.formatChanged(audioSelector)
        precondition(app.rejectedPreset == nil && app.phase == .ready && app.start.isEnabled && app.formatExplanations["audio"]?.stringValue.contains("MP3") == true)

        // Unsupported items must remain inspectable without enabling conversion.
        app.infos = [["path": "/tmp/unknown.bin", "name": "unknown.bin", "error": "Unsupported"]]
        app.files = ["/tmp/unknown.bin"]
        app.buildSelectors()
        precondition(app.selectors.isEmpty && !app.start.isEnabled && app.phase == .attention)
        app.fileTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        precondition(app.contextActionEnabled(#selector(app.copyErrors)) == true)
        precondition(app.contextActionEnabled(#selector(app.revealSelectedOutputs)) == false)

        // Same-frame incoming selections merge instead of silently losing files.
        app.pendingFiles = []
        app.queuePendingFiles(["/tmp/a.png", "/tmp/a.png"])
        app.queuePendingFiles(["/tmp/b.png"])
        precondition(app.pendingFiles == ["/tmp/a.png", "/tmp/b.png"])
        app.pendingFiles = []
        precondition(app.uniquePaths(["/tmp/a.png", "/tmp/./a.png"]) == ["/tmp/a.png"])

        // Services reject concurrent requests and unknown user data before
        // inspecting a file or altering the batch/destination.
        let board = NSPasteboard(name: .init("UltraConvert-interface-test-\(UUID())"))
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.png") as NSURL])
        var serviceError: NSString?
        app.busy = true
        app.prepareConversion(board, userData: "png", error: &serviceError)
        precondition(serviceError != nil && app.files == ["/tmp/unknown.bin"])
        app.busy = false
        serviceError = nil
        app.prepareConversion(board, userData: "../../invalid", error: &serviceError)
        precondition(serviceError != nil)
        board.releaseGlobally()

        // A thousand completion events update the model immediately, then
        // reload changed rows once. Fragmentation must preserve UTF-8 and JSON.
        app.infos = (0..<1000).map { index in
            var item = inspected[0]
            item["path"] = "/tmp/queue-\(index).png"; item["name"] = "Photo \(index).png"
            return item
        }
        app.files = app.infos.compactMap { $0["path"] as? String }
        app.buildSelectors()
        app.phase = .converting
        let reloads = app.queueReloadCount
        var events = Data()
        for index in 0..<1000 {
            let event: [String: Any] = ["event": "file", "completed": index + 1, "total": 1000,
                "result": ["path": "/tmp/queue-\(index).png", "name": "Photo 😀 \(index).png", "success": true, "target": "webp", "output": "/tmp/queue-\(index).webp"]]
            events.append(try JSONSerialization.data(withJSONObject: event)); events.append(10)
        }
        for offset in stride(from: 0, to: events.count, by: 997) {
            app.handleEvents(events.subdata(in: offset..<min(offset + 997, events.count)))
        }
        precondition(app.outcomes.count == 1000 && app.outputBySource.count == 1000)
        precondition(app.queueReloadCount == reloads)
        app.flushOutcomeChanges()
        precondition(app.queueReloadCount == reloads + 1 && app.changedRows.isEmpty)
        precondition(app.progress.doubleValue == 1)
        app.resultURL = URL(fileURLWithPath: "/tmp")
        app.publishedURLs = []
        let resultsItem = NSMenuItem(title: "Show Results", action: #selector(app.showResults), keyEquivalent: "")
        precondition(!app.validateMenuItem(resultsItem))
        app.showResults()
        precondition(app.status.stringValue.contains("No new outputs"))
        app.clearFiles()
        precondition(app.fileTable.numberOfRows == 0 && !app.queueEmpty.isHidden)
        precondition(app.selectors.isEmpty && !app.start.isEnabled)
        precondition(app.outputBySource.isEmpty && app.changedRows.isEmpty)
        print("Native interface smoke passed: mixed/unsupported batches, compact layout, context actions, service guards, incoming selections, fragmented 1,000-file events, result guards and clear.")
    }
}

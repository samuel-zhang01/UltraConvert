import AppKit

@main struct CompressionTests {
    static func main() throws {
        _ = NSApplication.shared
        let domain = "UltraConvert.CompressionQA.\(UUID())"
        let isolated = UserDefaults(suiteName: domain)!
        defer { isolated.removePersistentDomain(forName: domain) }
        var count = 0
        func expect(_ value: @autoclosure () -> Bool) { precondition(value()); count += 1 }
        expect(CompressionQuality.bitrate("mp3", quality: 1) == 64)
        expect(CompressionQuality.bitrate("mp3", quality: 100) == 320)
        expect(CompressionQuality.bitrate("opus", quality: 50) == 96)
        expect(CompressionQuality.bitrate("flac", quality: 50) == nil)
        expect(CompressionQuality.bitrate("mp3", quality: 0) == nil)
        expect(CompressionQuality.estimatedAudioBytes(duration: 60, format: "mp3", quality: 100) == 2_400_000)
        for duration in [Double.nan, Double.infinity, -1, 0] { expect(CompressionQuality.estimatedAudioBytes(duration: duration, format: "mp3", quality: 75) == nil) }
        for target in ["gif", "mxf", "png", "flac", "wav", "alac"] { expect(!CompressionQuality.supports(target)) }
        let control = CompressionControl(category: "audio", target: "mp3", infos: [["duration": 60.0]], preferences: isolated)
        expect(control.quality == nil && control.adjustment.isHidden)
        control.custom.state = .on; control.changed(control.custom)
        control.slider.doubleValue = 100; control.changed(control.slider)
        expect(control.quality == 100 && control.estimate.stringValue.contains("estimated audio size"))
        expect(control.estimate.stringValue.contains("actual size varies"))
        control.infos = [[:]]; control.refresh()
        expect(control.estimate.stringValue.contains("known duration") && control.estimate.stringValue.contains("48 kHz"))
        let app = ConverterApp(preferences: isolated)
        app.buildInterface()
        app.crs.stringValue = "EPSG:4326"; app.crs.isHidden = true
        expect(app.sourceCRSArguments.isEmpty)
        app.crs.isHidden = false; expect(app.sourceCRSArguments == ["--source-crs", "EPSG:4326"])
        app.crs.stringValue = " "; expect(app.sourceCRSArguments.isEmpty)
        app.qualityControls["audio"] = control
        expect(app.qualityArguments == ["--quality-audio", "100"])
        control.target = "flac"; control.refresh()
        expect(control.quality == nil && control.custom.isHidden && app.qualityArguments.isEmpty)
        control.target = "mp3"; control.refresh(); control.slider.doubleValue = 36; control.changed(control.slider)
        let chosenQuality = control.quality
        expect(control.slider.numberOfTickMarks == 7 && control.slider.allowsTickMarkValuesOnly)
        app.infos = [["path": "/nonexistent/test.wav", "format": "wav", "category": "audio", "error": NSNull(), "targets": ["mp3"], "duration": 60.0]]
        // Rebuilding immediately must flush a debounced edit before dropping its control.
        app.buildSelectors()
        expect(app.qualityControls["audio"]?.quality == chosenQuality)
        app.fileTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let menu = app.fileTable.menu!
        app.refreshContextMenu(menu)
        let categories = menu.items.first!.submenu!.items.filter { !$0.isHidden }
        expect(categories.count == 1 && categories.first?.title == "Audio")
        expect(categories.first!.submenu!.items.filter { !$0.isHidden }.map(\.representedObject).compactMap { $0 as? String } == ["mp3"])
        expect(menu.items.first { $0.action == #selector(ConverterApp.copyErrors) }!.isHidden)
        for (category, target) in [("image", "jpeg"), ("video", "webm")] {
            let item = CompressionControl(category: category, target: target, infos: [], preferences: isolated)
            item.custom.state = .on; item.changed(item.custom)
            expect(item.estimate.stringValue.contains("no reliable estimate"))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 280), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(); window.contentView = content; pin(control, in: content, inset: 16)
        window.contentView!.layoutSubtreeIfNeeded()
        expect(control.slider.frame.width > 100)
        expect(control.slider.accessibilityLabel()?.contains("quality") == true)
        control.setEnabled(false); expect(!control.slider.isEnabled && !control.custom.isEnabled)
        print("Passed \(count) native compression, truthful estimate, persistence and accessibility checks")
    }
}

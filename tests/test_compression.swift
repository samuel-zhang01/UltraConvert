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

        // A real event loop is essential here: static layout tests skip the
        // production animation path and cannot catch a late animated scroll
        // restoring an obsolete destination after rapid quality toggles.
        let motionDomain = domain + ".Motion"
        let motionPreferences = UserDefaults(suiteName: motionDomain)!
        defer { motionPreferences.removePersistentDomain(forName: motionDomain) }
        let motionApp = ConverterApp(preferences: motionPreferences)
        motionApp.buildInterface()
        motionApp.window.setContentSize(NSSize(width: 760, height: 570))
        motionApp.infos = [
            ["path": "/nonexistent/motion.png", "format": "png", "category": "image", "error": NSNull(), "targets": ["jpeg"]],
            ["path": "/nonexistent/motion.mp4", "format": "mp4", "category": "video", "error": NSNull(), "targets": ["mp4"]],
            ["path": "/nonexistent/motion.wav", "format": "wav", "category": "audio", "error": NSNull(), "targets": ["mp3", "flac"], "duration": 60.0]
        ]
        motionApp.draftTargets["audio"] = "mp3"
        motionApp.buildSelectors()
        motionApp.window.contentView!.layoutSubtreeIfNeeded()
        // Keep this disposable test window away from the owner's desktop.
        motionApp.window.setFrameOrigin(NSPoint(x: -12_000, y: -12_000))
        motionApp.window.orderFront(nil)
        defer { motionApp.window.orderOut(nil) }
        let scroll = motionApp.formatsScroll, document = scroll.documentView!
        let changes: [(String, NSControl.StateValue)] = [
            ("audio", .on), ("audio", .off), ("audio", .on),
            ("video", .on), ("video", .off), ("image", .on),
            ("image", .off), ("audio", .off), ("audio", .on)
        ]
        func validScrollBounds() -> Bool {
            let bounds = scroll.contentView.bounds
            let maximum = max(0, document.bounds.height - bounds.height)
            return bounds.minY.isFinite && bounds.height > 0 && bounds.minY >= -0.5 && bounds.minY <= maximum + 0.5
        }
        func geometry() -> [NSRect] {
            [document.bounds, scroll.contentView.bounds, motionApp.bodyScroll!.contentView.bounds] +
            ["image", "video", "audio"].flatMap { key -> [NSRect] in
                let item = motionApp.qualityControls[key]!
                return [item.convert(item.bounds, to: document), item.adjustment.frame, item.estimate.frame]
            }
        }
        func sameGeometry(_ left: [NSRect], _ right: [NSRect]) -> Bool {
            left.count == right.count && zip(left, right).allSatisfy { a, b in
                abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 &&
                abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
            }
        }
        func noGeometryAnimations() -> Bool {
            var views: [NSView] = [scroll.contentView, document]
            for item in motionApp.qualityControls.values {
                views += [item, item.adjustment, item.estimate]
                var parent = item.superview
                while let view = parent, view !== scroll { views.append(view); parent = view.superview }
            }
            return views.allSatisfy { view in
                !(view.layer?.animationKeys() ?? []).contains { key in
                    let key = key.lowercased()
                    return key.contains("bounds") || key.contains("position") || key.contains("frame")
                }
            }
        }
        func stopEventLoop() {
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        }
        func toggle(_ index: Int) {
            let (key, state) = changes[index], item = motionApp.qualityControls[key]!
            item.custom.state = state; item.changed(item.custom)
            expect(item.adjustment.isHidden == (state == .off) && item.estimate.isHidden == (state == .off))
            expect(validScrollBounds())
            let settled = geometry()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                // Only a subtle content opacity transition is permitted. The
                // panel must already have its final geometry and scroll offset.
                expect(sameGeometry(settled, geometry()))
                expect(validScrollBounds() && noGeometryAnimations())
                if index + 1 < changes.count { toggle(index + 1); return }
                let audio = motionApp.qualityControls["audio"]!
                let visible = scroll.documentVisibleRect
                let checkbox = audio.custom.convert(audio.custom.bounds, to: document)
                let estimate = audio.estimate.convert(audio.estimate.bounds, to: document)
                expect(checkbox.minY >= visible.minY - 1 && estimate.maxY <= visible.maxY + 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    expect(sameGeometry(settled, geometry()) && validScrollBounds())
                    expect(noGeometryAnimations() && audio.adjustment.alphaValue == 1 && audio.estimate.alphaValue == 1)
                    // Exercise explicit Reduce Motion endpoints without changing
                    // the owner's system accessibility preference.
                    InterfaceMotion.reveal(audio.adjustment, reduceMotion: false)
                    InterfaceMotion.reveal(audio.estimate, reduceMotion: false)
                    InterfaceMotion.reveal(audio.adjustment, reduceMotion: true)
                    InterfaceMotion.reveal(audio.estimate, reduceMotion: true)
                    InterfaceMotion.scroll(scroll, to: .zero, reduceMotion: false)
                    InterfaceMotion.scroll(scroll, to: settled[1].origin, reduceMotion: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                        expect((audio.adjustment.layer?.presentation()?.opacity ?? 1) >= 0.999)
                        expect((audio.estimate.layer?.presentation()?.opacity ?? 1) >= 0.999)
                        expect(sameGeometry(settled, geometry()) && noGeometryAnimations())
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        expect(sameGeometry(settled, geometry()) && validScrollBounds() && noGeometryAnimations())
                        // A format that has no lossy-quality control can be
                        // selected while the preceding reveal is still active.
                        InterfaceMotion.reveal(audio.adjustment, reduceMotion: false)
                        InterfaceMotion.reveal(audio.estimate, reduceMotion: false)
                        let format = motionApp.selectors["audio"]!
                        format.selectItem(withTitle: "FLAC"); motionApp.formatChanged(format)
                        motionApp.window.contentView!.layoutSubtreeIfNeeded()
                        expect(audio.quality == nil && audio.custom.isHidden && audio.adjustment.isHidden && audio.estimate.isHidden)
                        expect(validScrollBounds() && motionApp.qualityArguments.isEmpty)
                        let unsupported = geometry()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                            expect(sameGeometry(unsupported, geometry()) && noGeometryAnimations())
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            expect(sameGeometry(unsupported, geometry()) && validScrollBounds() && noGeometryAnimations())
                            expect(audio.custom.isHidden && audio.adjustment.isHidden && audio.estimate.isHidden)
                            stopEventLoop()
                        }
                    }
                }
            }
        }
        DispatchQueue.main.async {
            expect(NSApp.isRunning && motionApp.window.isVisible)
            expect(motionApp.qualityControls.count == 3 && document.bounds.height > scroll.contentView.bounds.height)
            let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
            InterfaceMotion.snapScroll(scroll, to: NSPoint(x: 0, y: bottom))
            InterfaceMotion.scroll(scroll, to: .zero, reduceMotion: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { toggle(0) }
        }
        NSApp.run()
        print("Passed \(count) native compression, live animation, truthful estimate, persistence and accessibility checks")
    }
}

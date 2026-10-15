import AppKit
import Darwin

@main struct ReportTests {
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default, folder = fm.temporaryDirectory.appendingPathComponent("UltraConvert report QA \(UUID())")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checks += 1 }
        func write(_ filename: String, _ object: [String: Any]) throws -> URL {
            let url = folder.appendingPathComponent(filename)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
            return url
        }
        let longError = String(repeating: "The source could not be decoded. ", count: 300) + "Full recovery detail remains available."
        let fullNote = "Custom audio uses 48 kHz. <b>This is literal text.</b>"
        let mixed = try write("mixed.json", ["date": "2026-10-15T12:00:00+01:00", "success": 999, "failed": 999, "cancelled": true, "results": [
            ["path": "/Example/Voice.wav", "name": "Voice.wav", "format": "wav", "target": "mp3", "success": true, "output": "/Example/Voice.mp3", "notes": [fullNote]],
            ["path": "/Example/Photo.png", "format": "png", "target": "png", "success": true, "skipped": true, "notes": ["Already in the selected format; original retained."]],
            ["path": "/Example/Broken.mov", "format": "mov", "target": "mp4", "success": false, "error": longError, "notes": ["The original was retained."]]
        ]])
        let document = ConversionReportDocument.load([mixed, mixed])
        expect(document.converted == 1 && document.skipped == 1 && document.failed == 1 && document.reportsRead == 1 && document.problems == 0, "Counts come from unique report file results, never repeated global totals")
        for phrase in [longError, fullNote, "Photo.png — Skipped", "Voice.wav — Converted", "Broken.mov — Failed", "WAV → MP3", "/Example/Voice.mp3", "batch was cancelled"] {
            expect(document.text.contains(phrase), "Readable report retains complete status, errors, notes and locations: " + phrase.suffix(40))
        }
        let another = try write("another.json", ["results": [["path": "/Other/Recording.wav", "success": true, "target": "mp3"]]])
        let combined = ConversionReportDocument.load([mixed, another])
        expect(combined.converted == 2 && combined.skipped == 1 && combined.failed == 1 && combined.reportsRead == 2, "Split source-folder reports combine without inflating counts")
        let missing = ConversionReportDocument.load([folder.appendingPathComponent("missing.json")])
        expect(missing.reportsRead == 0 && missing.problems == 1 && missing.availableReports.isEmpty && missing.text.contains("moved, removed") && missing.text.contains("have not been changed"), "Missing reports explain recovery without claiming conversions failed")
        let broken = folder.appendingPathComponent("broken.json"); try Data("{ incomplete".utf8).write(to: broken)
        let malformed = ConversionReportDocument.load([broken])
        expect(malformed.problems == 1 && malformed.reportsRead == 0 && malformed.availableReports == [broken] && malformed.text.contains("incomplete or damaged"), "Malformed reports remain revealable and get a friendly explanation")
        for object in [["unexpected": "shape"], ["results": [["path": "/Example/Numeric.wav", "success": 1]]], ["results": [["success": true]]]] as [[String: Any]] {
            let bad = try write("invalid-shape.json", object)
            expect(ConversionReportDocument.load([bad]).reportsRead == 0, "Wrong schemas and numeric success flags cannot invent successful conversions")
        }
        let empty = ConversionReportDocument.load([])
        expect(empty.text.contains("Convert a batch first") && empty.summary == "Report unavailable", "First-use Report is understandable")
        let emptyReport = try write("empty.json", ["results": []])
        expect(ConversionReportDocument.load([emptyReport]).text.contains("No file results were recorded"), "An empty result list is handled explicitly")
        let oversize = folder.appendingPathComponent("oversize.json"); fm.createFile(atPath: oversize.path, contents: nil)
        let file = try FileHandle(forWritingTo: oversize); try file.truncate(atOffset: UInt64(ConversionReportDocument.maximumBytes + 1)); try file.close()
        let huge = ConversionReportDocument.load([oversize])
        expect(huge.problems == 1 && huge.text.contains("16 MiB") && huge.availableReports == [oversize], "Oversize input is rejected before allocation but can still be revealed")
        let budget = try Data(contentsOf: mixed).count + Data(contentsOf: another).count - 1
        let limited = ConversionReportDocument.load([mixed, another], maximumBytes: budget)
        expect(limited.reportsRead == 1 && limited.problems == 1 && limited.converted == 1, "Combined read budget applies across report files")
        let manyResults = (0..<1_000).map { ["path": "/Example/\($0).wav", "success": true] as [String: Any] }
        let fullBatch = try write("full-batch.json", ["results": manyResults])
        let tooMany = ConversionReportDocument.load([fullBatch, another])
        expect(tooMany.converted == 1_000 && tooMany.reportsRead == 1 && tooMany.problems == 1 && tooMany.text.contains("1,000-file batch limit"), "Combined result count is bounded across split reports, independently of JSON byte size")
        let linked = folder.appendingPathComponent("linked.json"); try fm.createSymbolicLink(at: linked, withDestinationURL: mixed)
        for url in [linked, folder, URL(string: "https://example.invalid/report.json")!] {
            let rejected = ConversionReportDocument.load([url])
            expect(rejected.reportsRead == 0 && rejected.availableReports.isEmpty, "Links, directories and network URLs are not report input")
        }
        let pipe = folder.appendingPathComponent("pipe.json")
        expect(mkfifo(pipe.path, 0o600) == 0, "FIFO fixture created")
        let started = Date(); let pipeDocument = ConversionReportDocument.load([pipe])
        expect(pipeDocument.problems == 1 && Date().timeIntervalSince(started) < 1, "A special file is rejected without blocking the UI or waiting for a writer")
        let window = ConversionReportWindow(reports: [], document: document)
        defer { window.close() }
        expect(window.window!.contentView!.bounds.width >= 600, "Report window cannot shrink to an unreadable intrinsic size")
        expect(window.text.string == document.text && !window.text.isEditable && !window.text.isRichText && window.text.isSelectable, "Native report shows all text read-only without interpreting markup")
        expect(window.reveal.isEnabled && window.copy.isEnabled && window.summary.stringValue.contains("1 failed"), "Readable summary and explicit local actions are available")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.window!.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 600, height: 400), NSSize(width: 740, height: 560)] {
                window.window!.setContentSize(size); window.window!.contentView!.layoutSubtreeIfNeeded()
                for button in [window.reveal, window.copy, window.done] {
                    let frame = button.convert(button.bounds, to: window.window!.contentView!)
                    expect(frame.minX >= 0 && frame.maxX <= size.width && frame.minY >= 0 && frame.maxY <= size.height && button.bounds.width >= button.intrinsicContentSize.width, "Report actions remain visible and untruncated at compact light/dark sizes")
                }
            }
        }
        window.window!.makeKeyAndOrderFront(nil)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.window!.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        expect(window.window!.performKeyEquivalent(with: escape) && !window.window!.isVisible, "Escape closes the report without changing file state")
        let unavailableWindow = ConversionReportWindow(reports: [], document: missing)
        expect(!unavailableWindow.reveal.isEnabled && unavailableWindow.copy.isEnabled, "Missing-report state keeps useful readable feedback without offering a broken Finder action")
        unavailableWindow.close()
        let asynchronous = ConversionReportWindow(reports: [mixed])
        expect(asynchronous.reportDocument == nil && asynchronous.summary.stringValue.contains("Reading"), "File reading starts asynchronously without blocking window creation")
        let deadline = Date().addingTimeInterval(3)
        while asynchronous.reportDocument == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(asynchronous.reportDocument?.failed == 1 && asynchronous.text.string.contains(longError), "Background read delivers the complete report to native controls")
        asynchronous.close()
        let closed = ConversionReportWindow(reports: [mixed]); closed.close()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        expect(closed.reportDocument == nil, "A closed report window ignores a late asynchronous read completion")
        print("Passed \(checks) readable report, bounded input, local-only, recovery, compact layout and keyboard checks")
    }
}

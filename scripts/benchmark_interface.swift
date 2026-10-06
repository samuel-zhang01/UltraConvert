import AppKit

// Synthetic main-thread event ingestion, excluding engines and drawing. Compile
// with the real application sources; use BENCHMARK_BASELINE for pre-1.3 sources.
@main
struct InterfaceBenchmark {
    static func main() throws {
        _ = NSApplication.shared
        let app = ConverterApp()
        app.buildInterface()
        app.infos = (0..<1000).map { index in
            ["path": "/tmp/benchmark-\(index).png", "name": "Photo \(index).png", "format": "png",
             "category": "image", "targets": ["png", "webp"], "error": NSNull()] as [String: Any]
        }
        app.files = app.infos.compactMap { $0["path"] as? String }
        app.buildSelectors()
        app.window.contentView!.layoutSubtreeIfNeeded()
        app.phase = .converting
        var events = Data()
        for index in 0..<1000 {
            events.append(try JSONSerialization.data(withJSONObject: ["event": "file", "completed": index + 1, "total": 1000,
                "result": ["path": "/tmp/benchmark-\(index).png", "name": "Photo \(index).png", "success": true, "target": "webp"]])); events.append(10)
        }
        let start = ProcessInfo.processInfo.systemUptime
        app.handleEvents(events)
        #if !BENCHMARK_BASELINE
        app.flushOutcomeChanges()
        #endif
        let seconds = ProcessInfo.processInfo.systemUptime - start
        precondition(app.outcomes.count == 1000 && app.progress.doubleValue == 1)
        app.infos = []
        app.refreshQueue()
        let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!
        for path in app.files { app.fileIcons[path] = icon }
        let rowsStart = ProcessInfo.processInfo.systemUptime
        for row in 0..<1000 { _ = app.tableView(app.fileTable, viewFor: app.fileTable.tableColumns[0], row: row) }
        let rowsSeconds = ProcessInfo.processInfo.systemUptime - rowsStart
        let result: [String: Any] = ["files": 1000, "seconds": seconds, "row_preparation_seconds": rowsSeconds, "outcomes": app.outcomes.count,
            "limitations": "Synthetic native event ingestion and preparation of 1,000 queue rows during recognition; excludes engines, drawing and real-user latency. Icons are pre-cached in both versions."]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}

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
        app.clearFiles()
        precondition(app.fileTable.numberOfRows == 0 && !app.queueEmpty.isHidden)
        precondition(app.selectors.isEmpty && !app.start.isEnabled)
        print("Native interface smoke passed: category changes, mixed batch, compact window, options and clear.")
    }
}

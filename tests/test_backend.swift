import AppKit

@main
struct BackendSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UltraConvert backend \(UUID())")
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let app = root.appendingPathComponent("Applications/UltraConvert's test.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        let support = home.appendingPathComponent("Library/Application Support/UltraConvert")
        try fm.createDirectory(at: resources.appendingPathComponent("Source"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Helpers"), withIntermediateDirectories: true)
        try Data().write(to: contents.appendingPathComponent("Helpers/python"))
        let legacy = try BackendPaths(contents: contents, support: support)
        precondition(!legacy.bundled && legacy.python == support.appendingPathComponent(".venv/bin/python"))
        let manifest = resources.appendingPathComponent("runtime-manifest.json")
        var metadata: [String: Any] = ["schema": 1, "python": "Helpers/python", "source": "Resources/Source", "environment_paths": [:]]
        try JSONSerialization.data(withJSONObject: metadata).write(to: manifest)
        let backend = try BackendPaths(contents: contents, support: support)
        precondition(backend.bundled && backend.python.path.hasSuffix("Helpers/python"))
        precondition(!backend.environment["PATH"]!.contains("homebrew"))
        for path in ["/usr/bin/true", "../../../usr/bin/true", "Helpers/missing"] {
            metadata["python"] = path
            try JSONSerialization.data(withJSONObject: metadata).write(to: manifest)
            do { _ = try BackendPaths(contents: contents, support: support); preconditionFailure("Unsafe path was accepted") }
            catch { }
        }
        metadata["python"] = "Helpers/python"
        metadata["environment_paths"] = ["DYLD_INSERT_LIBRARIES": "Helpers/python"]
        try JSONSerialization.data(withJSONObject: metadata).write(to: manifest)
        do { _ = try BackendPaths(contents: contents, support: support); preconditionFailure("Loader environment was accepted") }
        catch { }
        // Native workflow installation handles arbitrary app paths, preserves
        // owned previous actions and refuses a foreign destination before swaps.
        let templates = URL(fileURLWithPath: CommandLine.arguments[1])
        try fm.copyItem(at: templates, to: resources.appendingPathComponent("FinderActions"))
        try FinderActions.install(app: app, home: home)
        let services = home.appendingPathComponent("Library/Services")
        let action = services.appendingPathComponent(FinderActions.names[0] + ".workflow")
        let document = action.appendingPathComponent("Contents/document.wflow")
        let saved = try Data(contentsOf: document)
        let plist = try PropertyListSerialization.propertyList(from: saved, format: nil) as! [String: Any]
        let actions = plist["actions"] as! [[String: Any]]
        let command = ((actions[0]["action"] as! [String: Any])["ActionParameters"] as! [String: Any])["COMMAND_STRING"] as! String
        precondition(command.contains("'\\''") && command.contains("--mode here -- \"$@\""))
        try FinderActions.install(app: app, home: home)
        let repeated = try Data(contentsOf: document)
        precondition(repeated == saved)
        try Data("broken owned workflow".utf8).write(to: document)
        try FinderActions.install(app: app, home: home, force: true)
        let repaired = try Data(contentsOf: document)
        precondition(repaired == saved)
        let marker = action.appendingPathComponent("Contents/ultraconvert-managed.json")
        try Data("{\"owner\":\"Other\"}".utf8).write(to: marker)
        do { try FinderActions.install(app: app, home: home); preconditionFailure("Foreign workflow was replaced") }
        catch { }
        let retained = try Data(contentsOf: document)
        precondition(retained == saved)
        print("Native backend checks passed: legacy/bundled selection, missing/escaping paths, loader environment, safe Finder dispatch, idempotence and foreign-action preservation.")
    }
}

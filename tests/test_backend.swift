import AppKit

final class TestLoginService: LoginService {
    var state = LoginState.disabled
    var fail = false
    var enableCount = 0
    var disableCount = 0
    func enable() throws {
        enableCount += 1
        if fail { throw CocoaError(.fileWriteNoPermission) }
        state = .needsApproval
    }
    func disable() throws { disableCount += 1; state = .disabled }
}

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
        // Settings must reflect macOS's real state, including approval and
        // failures, without registering a login item as a side effect of opening.
        let suite = "UltraConvert-settings-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let login = TestLoginService()
        var repairs = 0
        let settings = IntegrationSettings(preferences: preferences, login: login, registerFinder: { repairs += 1 })
        precondition(settings.loginToggle.state == .off && login.enableCount == 0)
        precondition(settings.finderToggle.state == .on)
        settings.finderToggle.state = .off; settings.changeFinderPreference(); settings.refresh()
        precondition(!preferences.bool(forKey: "autoRegisterFinderActions") && settings.finderToggle.state == .off)
        settings.repairFinder()
        precondition(repairs == 1 && settings.integrationStatus.stringValue.contains("installed"))
        settings.loginToggle.state = .on; settings.changeLogin()
        precondition(login.enableCount == 1 && settings.loginToggle.state == .on && settings.loginStatus.stringValue.contains("Allow"))
        settings.loginToggle.state = .off; settings.changeLogin()
        precondition(login.disableCount == 1 && settings.loginToggle.state == .off)
        login.fail = true; settings.loginToggle.state = .on; settings.changeLogin()
        precondition(settings.loginToggle.state == .off && settings.loginStatus.stringValue.contains("Could not"))
        login.state = .unavailable; settings.refresh()
        precondition(settings.loginToggle.state == .off && settings.loginStatus.stringValue.contains("off") && !settings.loginStatus.stringValue.contains("could not"))
        login.state = .enabled; settings.refresh()
        precondition(settings.loginToggle.state == .on)
        settings.window!.contentView!.layoutSubtreeIfNeeded()
        let scroll = settings.window!.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
        let settingsDocument = scroll.documentView!
        let statusBounds = settings.integrationStatus.convert(settings.integrationStatus.bounds, to: settingsDocument)
        precondition(scroll.hasVerticalScroller && statusBounds.minY >= 0 && statusBounds.maxY <= settingsDocument.bounds.height && statusBounds.maxX <= settingsDocument.bounds.width)
        settings.integrationStatus.scrollToVisible(settings.integrationStatus.bounds)
        precondition(scroll.documentVisibleRect.intersects(statusBounds))
        print("Native backend checks passed: legacy/bundled selection, missing/escaping paths, loader environment, safe Finder dispatch, idempotence and foreign-action preservation.")
    }
}

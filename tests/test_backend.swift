import AppKit
import Darwin

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
    static func extendedAttribute(_ name: String, at url: URL) -> Data {
        let count = getxattr(url.path, name, nil, 0, 0, 0)
        precondition(count > 0, "Expected workflow icon metadata")
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, count, 0, 0) }
        precondition(read == count)
        return data
    }
    static func iconBlock(_ kind: String, in icon: Data) -> Data {
        var offset = 8
        while offset + 8 <= icon.count {
            let size = icon[(offset + 4)..<(offset + 8)].reduce(0) { ($0 << 8) | Int($1) }
            precondition(size >= 8 && offset + size <= icon.count)
            if String(data: icon[offset..<(offset + 4)], encoding: .ascii) == kind { return Data(icon[offset..<(offset + size)]) }
            offset += size
        }
        preconditionFailure("Missing canonical icon resolution")
    }
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UltraConvert backend \(UUID())")
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        // Automatic setup must never repoint the user's actions at an Xcode
        // archive, download or unrelated folder merely named Applications.
        for path in ["/Applications/UltraConvert.app", "/Applications/Utilities/UltraConvert.app", home.appendingPathComponent("Applications/UltraConvert.app").path] {
            precondition(FinderActions.isInstalledLocation(app: URL(fileURLWithPath: path), home: home))
        }
        for path in [root.appendingPathComponent("Products/Applications/UltraConvert.app").path, home.appendingPathComponent("Downloads/Applications/UltraConvert.app").path, "/Applications-other/UltraConvert.app", "/Applications/../tmp/UltraConvert.app", "/Applications/not-an-app"] {
            precondition(!FinderActions.isInstalledLocation(app: URL(fileURLWithPath: path), home: home))
        }
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
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let canonicalIcon = try Data(contentsOf: repository.appendingPathComponent("assets/UltraConvert.icns"))
        try canonicalIcon.write(to: resources.appendingPathComponent("UltraConvert.icns"))
        try FinderActions.install(app: app, home: home)
        let services = home.appendingPathComponent("Library/Services")
        let action = services.appendingPathComponent(FinderActions.names[0] + ".workflow")
        let document = action.appendingPathComponent("Contents/document.wflow")
        let saved = try Data(contentsOf: document)
        let plist = try PropertyListSerialization.propertyList(from: saved, format: nil) as! [String: Any]
        let actions = plist["actions"] as! [[String: Any]]
        let command = ((actions[0]["action"] as! [String: Any])["ActionParameters"] as! [String: Any])["COMMAND_STRING"] as! String
        precondition(command.contains("'\\''") && command.contains("--mode here -- \"$@\""))
        // Finder gets the existing multi-resolution ICNS, including its exact
        // small and Retina payloads. The Settings image remains the original PNG.
        let finderMetadata = extendedAttribute("com.apple.FinderInfo", at: action)
        precondition(finderMetadata.count >= 10 && finderMetadata[8] & 0x04 != 0)
        let fork = extendedAttribute("com.apple.ResourceFork", at: action.appendingPathComponent("Icon\r"))
        for kind in ["ic04", "ic07", "ic10", "ic11"] { precondition(fork.range(of: iconBlock(kind, in: canonicalIcon)) != nil) }
        let quickActionImage = try Data(contentsOf: templates.appendingPathComponent(FinderActions.names[0] + ".workflow/Contents/Resources/workflowCustomImage.png"))
        let installedQuickActionImage = try Data(contentsOf: action.appendingPathComponent("Contents/Resources/workflowCustomImage.png"))
        precondition(installedQuickActionImage == quickActionImage)
        precondition((plist["workflowMetaData"] as! [String: Any])["customImageFileData"] as? Data == quickActionImage)
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
        // A damaged/partial app without the canonical ICNS still installs its
        // workflows without asking IconServices to encode the small Settings PNG.
        let noIconApp = root.appendingPathComponent("No Icon.app")
        let noIconTemplates = noIconApp.appendingPathComponent("Contents/Resources/FinderActions")
        try fm.createDirectory(at: noIconTemplates.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: templates, to: noIconTemplates)
        for name in FinderActions.names {
            let template = noIconTemplates.appendingPathComponent(name + ".workflow")
            let icon = template.appendingPathComponent("Icon\r")
            if fm.fileExists(atPath: icon.path) { try fm.removeItem(at: icon) }
            _ = removexattr(template.path, "com.apple.FinderInfo", 0)
        }
        let noIconHome = root.appendingPathComponent("no-icon-home")
        try FinderActions.install(app: noIconApp, home: noIconHome)
        let noIconAction = noIconHome.appendingPathComponent("Library/Services/" + FinderActions.names[0] + ".workflow")
        precondition(fm.fileExists(atPath: noIconAction.appendingPathComponent("Contents/document.wflow").path))
        precondition(!fm.fileExists(atPath: noIconAction.appendingPathComponent("Icon\r").path))
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

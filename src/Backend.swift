import AppKit
import CoreServices
import ServiceManagement

enum HomebrewRuntime {
    static var prefixes: [URL] {
        #if arch(arm64)
        return [URL(fileURLWithPath: "/opt/homebrew")]
        #else
        return [URL(fileURLWithPath: "/usr/local")]
        #endif
    }
    static func python(support: URL, prefixes: [URL]) -> URL {
        let existing = support.appendingPathComponent(".venv/bin/python")
        if FileManager.default.fileExists(atPath: existing.path) { return existing }
        for prefix in prefixes {
            let candidate = prefix.appendingPathComponent("opt/ultraconvert-runtime/libexec/bin/python")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return existing
    }
}

struct BackendPaths {
    let python: URL
    let source: URL
    let environment: [String: String]
    let bundled: Bool

    init(contents: URL?, support: URL, brewPrefixes: [URL] = HomebrewRuntime.prefixes) throws {
        let manifest = contents?.appendingPathComponent("Resources/runtime-manifest.json")
        guard let contents, let manifest,
              FileManager.default.fileExists(atPath: manifest.path) else {
            python = HomebrewRuntime.python(support: support, prefixes: brewPrefixes)
            let sealedSource = contents?.appendingPathComponent("Resources/Source")
            if let sealedSource, FileManager.default.fileExists(atPath: sealedSource.path) {
                let root = contents!.resolvingSymlinksInPath().standardizedFileURL
                let resolved = sealedSource.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadInvalidFileName) }
                for name in ["convert.py", "compression_profiles.py", "diagnostics.py", "runtime_tools.py", "structured.py", "geospatial.py", "guards.py", "policy.xml"] {
                    let script = resolved.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
                    guard script.path.hasPrefix(resolved.path + "/"), FileManager.default.fileExists(atPath: script.path) else { throw CocoaError(.fileReadCorruptFile) }
                }
                source = resolved
            } else { source = support.appendingPathComponent("src") }
            environment = [:]
            bundled = false
            return
        }
        let root = contents.resolvingSymlinksInPath().standardizedFileURL
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        guard let data, data["schema"] as? Int == 1,
              let paths = data["environment_paths"] as? [String: String] else {
            throw NSError(domain: "UltraConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "The app's bundled runtime manifest is invalid. Download a complete replacement app."])
        }
        func inside(_ key: String) throws -> URL {
            guard !key.hasPrefix("/") else { throw CocoaError(.fileReadInvalidFileName) }
            let url = root.appendingPathComponent(key).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "UltraConvert", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app's bundled runtime is incomplete. Download a complete replacement app."])
            }
            return url
        }
        guard let pythonPath = data["python"] as? String, let sourcePath = data["source"] as? String else {
            throw CocoaError(.fileReadCorruptFile)
        }
        python = try inside(pythonPath)
        source = try inside(sourcePath)
        let allowed: Set<String> = ["GDAL_DATA", "PROJ_DATA", "MAGICK_CONFIGURE_PATH", "MAGICK_CODER_MODULE_PATH"]
        guard Set(paths.keys).isSubset(of: allowed) else { throw CocoaError(.fileReadCorruptFile) }
        var env: [String: String] = [:]
        for (name, path) in paths { env[name] = try inside(path).path }
        env["PATH"] = root.appendingPathComponent("Helpers").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["GDAL_DRIVER_PATH"] = "disable"
        environment = env
        bundled = true
    }
}

extension ConverterApp {
    @objc func showSettings() {
        if settingsController == nil {
            settingsController = IntegrationSettings(preferences: preferences, login: SystemLoginService(), registerFinder: { [weak self] in
                guard let self, !self.busy else {
                    throw NSError(domain: "UltraConvert", code: 6, userInfo: [NSLocalizedDescriptionKey: "Wait for the current batch to finish, then try again."])
                }
                try FinderActions.install(app: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser, force: true)
                try FormatServices.register(app: Bundle.main.bundleURL)
            }, updates: updater)
        }
        NSApp.setActivationPolicy(.regular)
        if let panel = settingsController?.window { InterfaceMotion.present(panel) }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.refresh()
    }
    func showSettingsPane(_ pane: SettingsPane) { showSettings(); settingsController?.selectPane(pane) }
    func backendPaths() throws -> BackendPaths {
        try BackendPaths(contents: Bundle.main.bundleURL.appendingPathComponent("Contents"), support: support)
    }

    @objc func showLicences() {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ThirdParty/README.txt"),
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/samuel-zhang01/UltraConvert#licence-and-upstream-source")!)
        }
    }

    @objc func installFinderActions() {
        guard !busy else { return }
        do {
            try FinderActions.install(app: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser, force: true)
            try FormatServices.register(app: Bundle.main.bundleURL)
            status.stringValue = "Finder actions installed. Enable them in Finder Settings."
            openFinderSettings()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Finder actions could not be installed"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }
}

enum FinderActions {
    static let names = ["Convert Here with UltraConvert", "Convert to Destination with UltraConvert"]

    static func isInstalledLocation(app: URL, home: URL) -> Bool {
        let app = app.standardizedFileURL.resolvingSymlinksInPath()
        guard app.pathExtension.lowercased() == "app" else { return false }
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains { root in
            let root = root.standardizedFileURL.resolvingSymlinksInPath()
            return app.path.hasPrefix(root.path + "/")
        }
    }

    static func install(app: URL, home: URL, force: Bool = false) throws {
        let fm = FileManager.default
        let resources = app.appendingPathComponent("Contents/Resources")
        let templates = resources.appendingPathComponent("FinderActions")
        guard fm.fileExists(atPath: templates.path) else {
            throw NSError(domain: "UltraConvert", code: 5, userInfo: [NSLocalizedDescriptionKey: "This app does not contain Finder setup templates. For a source installation, re-run install.py; for a standalone app, download a complete replacement."])
        }
        let services = home.appendingPathComponent("Library/Services")
        let support = home.appendingPathComponent("Library/Application Support/UltraConvert")
        let transaction = UUID().uuidString
        let backup = support.appendingPathComponent("backups/finder-" + transaction)
        try fm.createDirectory(at: services, withIntermediateDirectories: true)
        guard !isSymlink(services), !isSymlink(support), !isSymlink(support.appendingPathComponent("backups")) else { throw CocoaError(.fileWriteNoPermission) }
        let ownership = support.appendingPathComponent("installation.json")
        if fm.fileExists(atPath: support.path) {
            guard let data = try? Data(contentsOf: ownership),
                  let owner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  owner["owner"] as? String == "UltraConvert" else {
                throw NSError(domain: "UltraConvert", code: 4, userInfo: [NSLocalizedDescriptionKey: "The existing UltraConvert support folder is not marked as owned and was left in place."])
            }
        } else {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["owner": "UltraConvert", "app": app.path, "bundled": true]).write(to: ownership, options: .atomic)
        }
        var stages: [(fresh: URL, target: URL, old: URL)] = []
        var swapped: [(fresh: URL, target: URL, old: URL)] = []
        defer { for stage in stages { try? fm.removeItem(at: stage.fresh) } }
        do {
            for (index, name) in names.enumerated() {
                let target = services.appendingPathComponent(name + ".workflow")
                let marker = target.appendingPathComponent("Contents/ultraconvert-managed.json")
                if fm.fileExists(atPath: target.path) {
                    guard !isSymlink(target),
                          let data = try? Data(contentsOf: marker),
                          let owner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          owner["owner"] as? String == "UltraConvert" else {
                        throw NSError(domain: "UltraConvert", code: 3, userInfo: [NSLocalizedDescriptionKey: "An existing Finder action is not owned by UltraConvert and was left in place: \(target.path)"])
                    }
                    if !force, owner["app"] as? String == app.path,
                       ["Contents/Info.plist", "Contents/document.wflow", "Contents/Resources/workflowCustomImage.png"].allSatisfy({ fm.fileExists(atPath: target.appendingPathComponent($0).path) }) { continue }
                }
                let fresh = services.appendingPathComponent(".ultraconvert-new-\(transaction)-\(index)")
                let old = backup.appendingPathComponent(name + ".workflow")
                stages.append((fresh, target, old))
                try fm.copyItem(at: templates.appendingPathComponent(name + ".workflow"), to: fresh)
                let document = fresh.appendingPathComponent("Contents/document.wflow")
                guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: document), format: nil) as? [String: Any],
                      var actions = plist["actions"] as? [[String: Any]], actions.count == 1,
                      var action = actions[0]["action"] as? [String: Any],
                      var parameters = action["ActionParameters"] as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let quotedApp = "'" + app.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
                parameters["COMMAND_STRING"] = "/usr/bin/open -n -a \(quotedApp) --args --mode \(index == 0 ? "here" : "destination") -- \"$@\""
                action["ActionParameters"] = parameters
                actions[0]["action"] = action
                plist["actions"] = actions
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: document, options: .atomic)
                try JSONSerialization.data(withJSONObject: ["owner": "UltraConvert", "app": app.path]).write(to: fresh.appendingPathComponent("Contents/ultraconvert-managed.json"), options: .atomic)
                // The canonical multi-resolution ICNS is already encoded for
                // Finder. Converting the small Quick Action PNG in setIcon
                // triggers an IconServices guard fault on macOS 27.
                if let icon = NSImage(contentsOf: resources.appendingPathComponent("UltraConvert.icns")) {
                    NSWorkspace.shared.setIcon(icon, forFile: fresh.path, options: [])
                }
            }
            for stage in stages {
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                if fm.fileExists(atPath: stage.target.path) { try fm.moveItem(at: stage.target, to: stage.old) }
                swapped.append(stage)
                try fm.moveItem(at: stage.fresh, to: stage.target)
            }
        } catch {
            for stage in swapped.reversed() {
                try? fm.removeItem(at: stage.target)
                if fm.fileExists(atPath: stage.old.path) { try? fm.moveItem(at: stage.old, to: stage.target) }
            }
            throw error
        }
        NSUpdateDynamicServices()
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

enum LoginState {
    case disabled, enabled, needsApproval, unavailable

    var requested: Bool { self == .enabled || self == .needsApproval }
    var message: String {
        switch self {
        case .disabled: return "Launch at login is off. Finder conversion works without it."
        case .enabled: return "UltraConvert will open when you log in."
        case .needsApproval: return "Allow UltraConvert in macOS Login Items to finish enabling this option."
        case .unavailable: return "Launch at login is off. Enable it to ask macOS to register this app."
        }
    }
}

protocol LoginService {
    var state: LoginState { get }
    func enable() throws
    func disable() throws
}

struct SystemLoginService: LoginService {
    var state: LoginState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
}

enum FormatServices {
    static func register(app: URL) throws {
        let result = LSRegisterURL(app as CFURL, true)
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        NSUpdateDynamicServices()
    }
}

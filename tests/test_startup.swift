import AppKit

@main struct StartupTests {
    static func main() {
        _ = NSApplication.shared
        let domain = "UltraConvert.StartupTests.\(UUID())"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var cases = 0
        func expect(_ value: Bool) { precondition(value); cases += 1 }

        func event(_ eventID: AEEventID = AEEventID(kAEOpenApplication), eventClass: AEEventClass = AEEventClass(kCoreEventClass), launch: OSType? = nil) -> NSAppleEventDescriptor {
            let descriptor = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            if let launch { descriptor.setParam(NSAppleEventDescriptor(enumCode: launch), forKeyword: keyAEPropData) }
            return descriptor
        }
        expect(!StartupPolicy.launchedAtLogin(event: nil))
        expect(!StartupPolicy.launchedAtLogin(event: event()))
        expect(!StartupPolicy.launchedAtLogin(event: event(launch: 0)))
        expect(!StartupPolicy.launchedAtLogin(event: event(launch: OSType(keyAELaunchedAsServiceItem))))
        expect(StartupPolicy.launchedAtLogin(event: event(launch: OSType(keyAELaunchedAsLogInItem))))
        expect(!StartupPolicy.launchedAtLogin(event: event(AEEventID(kAEReopenApplication), launch: OSType(keyAELaunchedAsLogInItem))))
        expect(!StartupPolicy.launchedAtLogin(event: event(AEEventID(kAEOpenDocuments), launch: OSType(keyAELaunchedAsLogInItem))))
        expect(!StartupPolicy.launchedAtLogin(event: event(eventClass: AEEventClass(kAEInternetSuite), launch: OSType(keyAELaunchedAsLogInItem))))

        // Missing preferences preserve a normal first launch and never migrate
        // or enable the existing folder-rule setting as a side effect.
        expect(!StartupPolicy.startsInMenuBar(preferences: preferences, launchedAtLogin: true, hasFiles: false, restoringUpdate: false, rulesKeepRunning: false))
        expect(preferences.persistentDomain(forName: domain)?.isEmpty != false)
        expect(preferences.object(forKey: StartupPolicy.minimizeAtLoginKey) == nil)
        expect(preferences.object(forKey: "startInMenuBar") == nil)

        // Every combination of opt-ins, launch source, work and update recovery.
        // The expected behavior describes user intent rather than implementation.
        for bits in 0..<128 {
            let minimized = bits & 1 != 0, legacy = bits & 2 != 0
            let login = bits & 4 != 0, files = bits & 8 != 0
            let update = bits & 16 != 0, rules = bits & 32 != 0
            // Test an unrelated login preference too: runtime launch context,
            // rather than a possibly stale preference, identifies a real login.
            preferences.set(minimized, forKey: StartupPolicy.minimizeAtLoginKey)
            preferences.set(legacy, forKey: "startInMenuBar")
            preferences.set(bits & 64 != 0, forKey: "launchAtLogin")
            let expected: Bool
            if files || update { expected = false }
            else if login && minimized { expected = true }
            else { expected = legacy && rules }
            let before = preferences.persistentDomain(forName: domain)!
            expect(StartupPolicy.startsInMenuBar(preferences: preferences, launchedAtLogin: login, hasFiles: files, restoringUpdate: update, rulesKeepRunning: rules) == expected)
            expect(NSDictionary(dictionary: preferences.persistentDomain(forName: domain)!).isEqual(to: before))
        }

        // A minimized login remains recoverable even with no rules, a paused
        // watcher or a runtime setup error. Explicit Dock/reopen integration
        // clears minimizedStartup and opens the normal converter.
        expect(StartupPolicy.needsMenuBarItem(rulesKeepRunning: false, minimizedStartup: true))
        expect(StartupPolicy.needsMenuBarItem(rulesKeepRunning: true, minimizedStartup: true))
        expect(StartupPolicy.needsMenuBarItem(rulesKeepRunning: true, minimizedStartup: false))
        expect(!StartupPolicy.needsMenuBarItem(rulesKeepRunning: false, minimizedStartup: false))
        let app = ConverterApp(preferences: preferences)
        app.buildInterface()
        preferences.set(true, forKey: StartupPolicy.minimizeAtLoginKey)
        preferences.set(false, forKey: "startInMenuBar")
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: false, restoringUpdate: false)
        expect(app.minimizedStartup && !app.window.isVisible)
        expect(app.watcherStatusItem != nil)
        let titles = app.watcherStatusItem?.menu?.items.map(\.title) ?? []
        expect(titles.contains("Open Converter") && titles.contains("Settings…") && titles.contains("Quit UltraConvert"))
        app.showConverter()
        expect(!app.minimizedStartup && app.window.isVisible && app.watcherStatusItem == nil)
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: false, restoringUpdate: false)
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: true, restoringUpdate: false)
        expect(!app.minimizedStartup && app.window.isVisible && NSApp.activationPolicy() == .regular)
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: false, restoringUpdate: false)
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: false, restoringUpdate: true)
        expect(!app.minimizedStartup && app.window.isVisible && NSApp.activationPolicy() == .regular)
        // A real preset Service must leave minimized-login presentation, just
        // like Open Converter and the grouped format picker. The nonexistent
        // temporary input can only produce a read-only inspection error.
        app.applyStartupPresentation(launchedAtLogin: true, hasFiles: false, restoringUpdate: false)
        expect(app.minimizedStartup && app.watcherStatusItem != nil)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("UltraConvert missing startup fixture \(UUID()).wav")
        let board = NSPasteboard(name: .init("UltraConvert.StartupService.\(UUID())"))
        board.writeObjects([source as NSURL])
        defer { board.releaseGlobally(); if app.process?.isRunning == true { app.process?.terminate() } }
        var serviceError: NSString?
        app.prepareConversion(board, userData: "mp3", error: &serviceError)
        expect(serviceError == nil && app.files == [source.path])
        expect(!app.minimizedStartup && app.window.isVisible && app.watcherStatusItem == nil && NSApp.activationPolicy() == .regular)
        expect(preferences.bool(forKey: StartupPolicy.minimizeAtLoginKey))
        let deadline = Date().addingTimeInterval(5)
        while app.busy, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(!app.busy && !FileManager.default.fileExists(atPath: source.path))
        app.window.orderOut(nil)
        print("Passed \(cases) login-launch, startup recovery and preference-preservation checks")
    }
}

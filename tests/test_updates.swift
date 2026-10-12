import AppKit

final class FakeUpdates: UpdateManaging {
    var canCheck = true
    var automaticallyChecks = true
    var automaticallyDownloads = false
    var includesPreviews = false
    var status = "Your version is up to date."
    var onChange: (() -> Void)?
    var checks = 0
    func checkNow() { checks += 1 }
}

@main struct UpdateTests {
    static func main() throws {
        _ = NSApplication.shared
        let domain = "UltraConvert.UpdateTests.\(UUID())"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var cases = 0
        func expect(_ value: Bool) { precondition(value); cases += 1 }
        for bits in 0..<16 {
            let reason = UpdateSafety.reason(manualBusy: bits & 1 != 0, automationBusy: bits & 2 != 0, previewCount: bits & 4 != 0 ? 1 : 0, unsavedRule: bits & 8 != 0)
            expect((reason == nil) == (bits == 0))
        }
        let updater = AppUpdater(preferences: preferences)
        var blocker: String? = "Working"
        var installations = 0
        updater.blockedReason = { blocker }
        expect(updater.prepareRelaunch { installations += 1 })
        expect(!updater.isRelaunching)
        updater.workDidFinish(); expect(installations == 0)
        blocker = "Unsaved rule"; updater.workDidFinish(); expect(installations == 0)
        blocker = nil; updater.workDidFinish(); expect(installations == 1 && updater.isRelaunching)
        updater.workDidFinish(); expect(installations == 1)
        let idle = AppUpdater(preferences: preferences)
        expect(!idle.prepareRelaunch { installations += 1 })
        expect(idle.isRelaunching)
        idle.includesPreviews = true; expect(preferences.bool(forKey: "includePreviewUpdates"))
        idle.includesPreviews = false; expect(!preferences.bool(forKey: "includePreviewUpdates"))
        idle.downloadedForQuit(version: "1.8.1"); expect(idle.status.contains("will install when you quit"))
        idle.finishedCycle(error: nil); expect(idle.status.contains("1.8.1") && idle.status.contains("will install when you quit"))
        blocker = "Working"
        expect(updater.prepareRelaunch { installations += 1 })
        updater.finishedCycle(error: CocoaError(.fileReadCorruptFile))
        blocker = nil; updater.workDidFinish(); expect(installations == 1 && !updater.isRelaunching)
        let fake = FakeUpdates()
        let settings = IntegrationSettings(preferences: preferences, login: SystemLoginService(), registerFinder: {}, updates: fake)
        expect(settings.updateChecks.state == .on && settings.updateDownloads.state == .off)
        settings.updateChecks.state = .off; settings.changeUpdateChecks()
        expect(!fake.automaticallyChecks && !settings.updateDownloads.isEnabled)
        settings.updateChecks.state = .on; settings.changeUpdateChecks()
        settings.updateDownloads.state = .on; settings.changeUpdateDownloads()
        expect(fake.automaticallyDownloads)
        settings.previewUpdates.state = .on; settings.changePreviewUpdates(); expect(fake.includesPreviews)
        settings.checkUpdates(); expect(fake.checks == 1)
        fake.canCheck = false; fake.status = "Checking…"; fake.onChange?()
        expect(!settings.updateNow.isEnabled && settings.updateStatus.stringValue == "Checking…")
        settings.close()
        print("Passed \(cases) updater policy, deferred relaunch and settings checks")
    }
}

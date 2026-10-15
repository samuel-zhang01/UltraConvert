import AppKit
#if canImport(Sparkle)
import Sparkle
#elseif !ULTRACONVERT_INTERFACE_TESTS
#error("Production builds must link the pinned Sparkle framework")
#endif

protocol UpdateManaging: AnyObject {
    var canCheck: Bool { get }
    var automaticallyChecks: Bool { get set }
    var automaticallyDownloads: Bool { get set }
    var includesPreviews: Bool { get set }
    var status: String { get }
    var onChange: (() -> Void)? { get set }
    func checkNow()
}

struct UpdateSafety {
    static func reason(manualBusy: Bool, automationBusy: Bool, previewCount: Int, unsavedRule: Bool, pendingJobs: Int = 0) -> String? {
        if manualBusy { return "A conversion or file check is still running. The update will wait for it to finish." }
        if automationBusy || pendingJobs > 0 { return "Folder-rule work is running or queued. The update will wait for it to finish." }
        if previewCount > 0 { return "A rule preview is still running. The update will wait for it to finish." }
        if unsavedRule { return "Save your rule changes or discard them before installing an update." }
        return nil
    }
}

final class AppUpdater: NSObject, UpdateManaging {
    let preferences: UserDefaults
    var blockedReason: () -> String? = { nil }
    var beforeRelaunch: () -> Void = {}
    var onChange: (() -> Void)?
    private(set) var status = "Signed updates are downloaded from GitHub."
    private(set) var isRelaunching = false
    private var deferredInstall: (() -> Void)?
    private var readyOnQuit: String?
#if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
#endif
    init(preferences: UserDefaults) { self.preferences = preferences; super.init() }
    func start() {
#if canImport(Sparkle)
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.changed() } },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.changed() } },
            controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.changed() } }
        ]
        do { try controller.updater.start() }
        catch { status = "Updates could not start: " + error.localizedDescription; changed() }
#else
        status = "Updates are available in the installed release app."
#endif
    }
    var canCheck: Bool {
#if canImport(Sparkle)
        return deferredInstall != nil || controller?.updater.canCheckForUpdates == true
#else
        return false
#endif
    }
    var automaticallyChecks: Bool {
        get {
#if canImport(Sparkle)
            return controller?.updater.automaticallyChecksForUpdates ?? false
#else
            return false
#endif
        }
        set {
#if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
#endif
            changed()
        }
    }
    var automaticallyDownloads: Bool {
        get {
#if canImport(Sparkle)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
#else
            return false
#endif
        }
        set {
#if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = newValue
#endif
            changed()
        }
    }
    var includesPreviews: Bool {
        get { preferences.object(forKey: "includePreviewUpdates") as? Bool ?? (Bundle.main.object(forInfoDictionaryKey: "UCUpdateChannel") as? String == "preview") }
        set {
            preferences.set(newValue, forKey: "includePreviewUpdates")
#if canImport(Sparkle)
            controller?.updater.resetUpdateCycleAfterShortDelay()
#endif
            changed()
        }
    }
    func changed() { onChange?() }
    func checkNow() {
        if let reason = blockedReason() {
            status = reason; changed()
            let alert = NSAlert(); alert.messageText = "Finish your work before updating"; alert.informativeText = reason; alert.runModal(); return
        }
        if let install = deferredInstall { deferredInstall = nil; isRelaunching = true; install(); return }
#if canImport(Sparkle)
        guard canCheck else { return }
        controller.checkForUpdates(nil)
#endif
    }
    // Existing completion events call this; no idle polling timer is needed.
    func workDidFinish() {
        guard let install = deferredInstall, blockedReason() == nil else { return }
        deferredInstall = nil; isRelaunching = true; install()
    }
    func prepareRelaunch(installHandler: @escaping () -> Void) -> Bool {
        if let reason = blockedReason() { deferredInstall = installHandler; status = "Update ready. " + reason; changed(); return true }
        isRelaunching = true; return false
    }
    func downloadedForQuit(version: String) {
        readyOnQuit = version
        status = "UltraConvert \(version) is downloaded and will install when you quit."
        changed()
    }
    func finishedCycle(error: Error?) {
        if let error { isRelaunching = false; deferredInstall = nil; readyOnQuit = nil; status = error.localizedDescription }
        else if let version = readyOnQuit { status = "UltraConvert \(version) is downloaded and will install when you quit." }
        else if deferredInstall == nil { status = "Update check finished. You can check again at any time." }
        changed()
    }
}

#if canImport(Sparkle)
extension AppUpdater: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { includesPreviews ? ["preview"] : [] }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if let reason = blockedReason() { throw NSError(domain: "UltraConvert.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
        status = "Checking GitHub for signed updates…"; changed()
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "UltraConvert \(item.displayVersionString) is available."; changed()
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        prepareRelaunch(installHandler: installHandler)
    }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { beforeRelaunch() }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        downloadedForQuit(version: item.displayVersionString); return false
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        finishedCycle(error: error)
    }
}
#endif

extension ConverterApp {
    func startUpdater() {
        updater.blockedReason = { [weak self] in
            guard let self else { return "UltraConvert is closing." }
            return UpdateSafety.reason(manualBusy: self.busy, automationBusy: self.automation?.running == true, previewCount: self.rulesController?.previewWorkCount ?? 0, unsavedRule: self.rulesController?.hasUnsavedChanges ?? false, pendingJobs: self.automation?.pendingCount ?? 0)
        }
        updater.beforeRelaunch = { [weak self] in
            guard let self else { return }
            // This is local state only; file paths are never sent in update requests.
            self.preferences.set(Array((self.files + self.pendingFiles).prefix(10_000)), forKey: "updateRestoreFiles")
            self.preferences.set(self.outputURL?.path, forKey: "updateRestoreDestination")
            self.rememberConversionOptions()
            self.preferences.synchronize()
        }
        updater.start()
    }
    @objc func checkForUpdates() { updater.checkNow() }
    func rememberConversionOptions() {
        flushQualityPreferences()
        var remembered = preferences.dictionary(forKey: "formats") as? [String: String] ?? [:]
        for (key, popup) in selectors { if let value = popup.selectedItem?.representedObject as? String { remembered[key] = value } }
        preferences.set(remembered, forKey: "formats")
        preferences.set(here ? "here" : "destination", forKey: "outputMode")
        preferences.set(skipSame.state == .on, forKey: "skipSame")
        preferences.set(openAfter.state == .on, forKey: "openAfter")
        preferences.set(jobs.indexOfSelectedItem + 1, forKey: "jobs")
    }
}

import AppKit

/// Startup presentation must not change login registration or saved rules.
enum StartupPolicy {
    static let minimizeAtLoginKey = "startMinimizedAtLogin"

    /// Read during applicationDidFinishLaunching, before presenting other UI.
    /// macOS identifies login launches in the open-application Apple event.
    /// https://developer.apple.com/documentation/coreservices/keyaelaunchedasloginitem
    static func launchedAtLogin(event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static func startsInMenuBar(preferences: UserDefaults, launchedAtLogin: Bool, hasFiles: Bool, restoringUpdate: Bool, rulesKeepRunning: Bool) -> Bool {
        // Explicit work and update recovery always remain accessible in a window,
        // including an update that restores an empty queue.
        guard !hasFiles, !restoringUpdate else { return false }
        if launchedAtLogin && preferences.bool(forKey: minimizeAtLoginKey) { return true }
        // Preserve the existing opt-in behavior for folder-rule users.
        return rulesKeepRunning && preferences.bool(forKey: "startInMenuBar")
    }

    static func needsMenuBarItem(rulesKeepRunning: Bool, minimizedStartup: Bool) -> Bool {
        // A login launch without saved rules must still have Open and Quit.
        rulesKeepRunning || minimizedStartup
    }
}

import AppKit

final class SettingsTestLogin: LoginService {
    var state = LoginState.disabled
    var registrations = 0
    var fail = false
    func enable() throws { registrations += 1; if fail { throw CocoaError(.fileWriteNoPermission) }; state = .needsApproval }
    func disable() throws { state = .disabled }
}
final class SettingsTestUpdates: UpdateManaging {
    var canCheck = true
    var automaticallyChecks = true
    var automaticallyDownloads = true
    var includesPreviews = false
    var status = "Signed updates come from GitHub."
    var onChange: (() -> Void)?
    var checks = 0
    func checkNow() { checks += 1 }
}
@main struct SettingsTests {
    static func main() throws {
        _ = NSApplication.shared
        let domain = "UltraConvert.SettingsQA.\(UUID())"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let login = SettingsTestLogin(), updates = SettingsTestUpdates()
        var cases = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Settings behavior") { precondition(condition(), message); cases += 1 }
        let settings = IntegrationSettings(preferences: preferences, login: login, registerFinder: { throw CocoaError(.fileWriteNoPermission) }, updates: updates)
        let window = settings.window!
        window.contentView!.layoutSubtreeIfNeeded()
        expect(window.contentView!.bounds.width >= 600, "The initial window must not collapse to an intrinsic minimum")
        expect(login.registrations == 0, "Opening Settings must never register login")
        expect(settings.selectedPane == .general)
        expect(window.toolbar?.items.map(\.itemIdentifier) == SettingsPane.allCases.map(\.identifier))
        expect(window.toolbar?.allowsUserCustomization == false)
        expect(!window.styleMask.contains(.miniaturizable) && !window.styleMask.contains(.resizable))
        expect(!settings.minimizedToggle.isEnabled && settings.minimizedHelp.stringValue.contains("Turn on"))
        expect([settings.loginStatus, settings.minimizedHelp, settings.downloadsHelp, settings.updateStatus, settings.integrationStatus, settings.servicesStatus].allSatisfy { $0.textColor == .labelColor }, "Essential instructions and results use full semantic text contrast")
        settings.minimizedToggle.state = .on; settings.changeMinimizedPreference(); settings.refresh()
        expect(preferences.bool(forKey: StartupPolicy.minimizeAtLoginKey))
        expect(settings.minimizedToggle.state == .on && !settings.minimizedToggle.isEnabled)
        settings.loginToggle.state = .on; settings.changeLogin()
        expect(login.registrations == 1 && settings.minimizedToggle.isEnabled && settings.loginStatus.stringValue.contains("Allow"))
        settings.loginToggle.state = .off; settings.changeLogin()
        expect(!settings.minimizedToggle.isEnabled && preferences.bool(forKey: StartupPolicy.minimizeAtLoginKey))
        login.fail = true; settings.loginToggle.state = .on; settings.changeLogin()
        expect(settings.loginStatus.stringValue.contains("Could not") && !settings.minimizedToggle.isEnabled)
        settings.updateChecks.state = .off; settings.changeUpdateChecks()
        expect(!settings.updateDownloads.isEnabled && settings.downloadsHelp.stringValue.contains("Turn on"))
        expect(updates.automaticallyDownloads, "Dependent preference must be retained while disabled")
        settings.updateChecks.state = .on; settings.changeUpdateChecks()
        expect(settings.updateDownloads.isEnabled && settings.updateDownloads.state == .on)
        settings.checkUpdates(); expect(updates.checks == 1)
        settings.selectPane(.finder, animated: false); settings.repairFinder()
        expect(settings.integrationStatus.stringValue.contains("Could not install"))
        expect(!settings.servicesStatus.stringValue.contains("Could not install"), "Quick Action feedback must stay in its own section")
        settings.integrationStatus.stringValue = String(repeating: "A long repair error needs to remain readable. ", count: 30)
        settings.servicesStatus.stringValue = String(repeating: "A long format-shortcut result. ", count: 25)
        settings.updateStatus.stringValue = String(repeating: "A long update status. ", count: 25)
        func descendants<T: NSView>(_ view: NSView, as type: T.Type) -> [T] { (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { descendants($0, as: type) } }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 600, height: 500), NSSize(width: 680, height: 640)] {
                window.setContentSize(size)
                for pane in SettingsPane.allCases {
                    settings.selectPane(pane, animated: false); window.contentView!.layoutSubtreeIfNeeded()
                    let canvas = settings.paneDocuments[pane]!, scroll = settings.paneScrolls[pane]!
                    expect(window.title == "\(pane.title) — UltraConvert")
                    expect(window.toolbar?.selectedItemIdentifier == pane.identifier)
                    expect(settings.paneScrolls.filter { !$0.value.isHidden }.count == 1)
                    for button in settings.actionButtons where !button.isHiddenOrHasHiddenAncestor {
                        expect(abs(button.frame.width - IntegrationSettings.actionWidth) < 0.5, "Uniform action width")
                        expect(abs(button.frame.height - 28) < 0.5, "Uniform action height")
                        expect(button.intrinsicContentSize.width <= button.frame.width + 1, "Action text cannot be clipped: \(button.title)")
                        let rect = button.convert(button.bounds, to: canvas)
                        expect(rect.minX >= 0 && rect.maxX <= canvas.bounds.width + 0.5)
                        expect(abs(rect.maxX - (canvas.bounds.width - 40)) < 1, "Action buttons must share the trailing column")
                        expect(button.accessibilityLabel() == button.title)
                    }
                    for label in descendants(canvas, as: NSTextField.self) where !label.isHiddenOrHasHiddenAncestor {
                        expect((label.font?.pointSize ?? 0) >= 13, "Readable helper text")
                        let rect = label.superview!.convert(label.alignmentRect(forFrame: label.frame), to: canvas)
                        expect(rect.minX >= -0.5 && rect.maxX <= canvas.bounds.width + 0.5, "Label outside horizontal canvas: \(label.stringValue)")
                        expect(rect.minY >= -0.5 && rect.maxY <= canvas.bounds.height + 0.5, "Label outside vertical canvas")
                    }
                    let last = pane == .finder ? settings.servicesStatus : pane == .updates ? settings.updateStatus : settings.minimizedHelp
                    last.scrollToVisible(last.bounds)
                    expect(scroll.documentVisibleRect.intersects(last.convert(last.bounds, to: canvas)), "Feedback must be reachable")
                }
            }
        }
        settings.selectPane(.general, animated: false)
        settings.legacyDisclosure.state = .on; settings.toggleLegacyStartup(); expect(!settings.legacyBody.isHidden)
        settings.legacyDisclosure.state = .off; settings.toggleLegacyStartup(); expect(settings.legacyBody.isHidden)
        settings.selectPane(.finder, animated: false)
        let restored = IntegrationSettings(preferences: preferences, login: login, registerFinder: {}, updates: SettingsTestUpdates())
        expect(restored.selectedPane == .finder, "Last pane is restored")
        settings.close(); restored.close()
        print("Passed \(cases) settings navigation, dependency, layout, feedback and persistence checks")
    }
}

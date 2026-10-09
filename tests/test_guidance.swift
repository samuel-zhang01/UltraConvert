import AppKit

@main
struct GuidanceSmoke {
    static func main() {
        _ = NSApplication.shared
        let suite = "UltraConvert-guidance-test-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let app = ConverterApp(preferences: preferences); app.buildInterface(); app.window.orderFront(nil)
        precondition(app.shouldOfferGettingStarted)
        app.files = ["/tmp/keep-my-queue.wav"]
        precondition(!app.shouldOfferGettingStarted)
        app.showQuickStart()
        precondition(app.files == ["/tmp/keep-my-queue.wav"] && !app.busy && app.process == nil)
        precondition(preferences.bool(forKey: "hasSeenGettingStarted"))
        precondition(preferences.object(forKey: "outputMode") == nil && preferences.object(forKey: "startInMenuBar") == nil)
        let guide = app.guideController!
        guide.window!.setContentSize(NSSize(width: 680, height: 520))
        for topic in 0..<4 {
            guide.openTopic(topic); guide.window!.contentView!.layoutSubtreeIfNeeded()
            precondition(guide.body.arrangedSubviews.count >= 3)
            for view in guide.actions.arrangedSubviews where view is NSButton {
                let frame = view.convert(view.bounds, to: guide.window!.contentView!)
                precondition(frame.minX >= 0 && frame.maxX <= 680 && frame.minY >= 0 && frame.maxY <= 520)
            }
        }
        guide.close(); app.files = []
        precondition(!app.shouldOfferGettingStarted)
        app.showQuickStart(); precondition(app.guideController === guide && guide.window!.isVisible)
        guide.openTopic(0)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: guide.window!.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        precondition(guide.window!.performKeyEquivalent(with: escape) && !guide.window!.isVisible)
        preferences.set(false, forKey: "hasSeenGettingStarted")
        app.busy = true; precondition(!app.shouldOfferGettingStarted)
        app.busy = false; app.phase = .inspecting; precondition(!app.shouldOfferGettingStarted)
        app.phase = .empty; app.window.orderOut(nil); precondition(!app.shouldOfferGettingStarted)
        for group in FormatCatalog.groups {
            for format in group.formats { precondition(FormatCatalog.advice(format).contains(" · ")) }
        }
        // All task routes are explicit actions, never run while merely reading a topic.
        var destinations: [GuideDestination] = []
        let isolated = GettingStarted(route: { destinations.append($0) })
        for topic in 0..<4 { isolated.openTopic(topic) }
        precondition(destinations.isEmpty)
        isolated.openTopic(2)
        let rules = isolated.actions.arrangedSubviews.compactMap { $0 as? RuleButton }.first { $0.title == "Open Folder Rules…" }!
        rules.invoke(); precondition(destinations == [.rules])
        print("Guidance tests passed: first-use gating/persistence, queue/preferences preservation, topic bounds, Escape, explicit task routing and advice for all 62 formats.")
    }
}

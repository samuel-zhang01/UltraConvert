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
        precondition(guide.window!.contentMinSize == NSSize(width: 680, height: 520))
        guide.window!.setFrame(NSRect(origin: guide.window!.frame.origin, size: guide.window!.minSize), display: false)
        precondition(guide.window!.contentView!.bounds.width >= 680 && guide.window!.contentView!.bounds.height >= 520)
        for topic in 0..<4 {
            guide.openTopic(topic); guide.window!.contentView!.layoutSubtreeIfNeeded()
            precondition(guide.body.arrangedSubviews.count >= 3)
            for view in guide.actions.arrangedSubviews where view is NSButton {
                let frame = view.convert(view.bounds, to: guide.window!.contentView!)
                precondition(frame.minX >= 0 && frame.maxX <= 680 && frame.minY >= 0 && frame.maxY <= 520)
            }
        }
        for topic in [3, 1, 2, 0, 3, 0] { guide.topics.selectedSegment = topic; guide.changeTopic() }
        precondition(guide.topics.selectedSegment == 0 && guide.body.alphaValue == 1)
        precondition(guide.body.arrangedSubviews.compactMap { $0 as? RoundedCard }.first?.contents.arrangedSubviews.compactMap { $0 as? NSTextField }.first?.stringValue == "1. Add files")
        guide.openTopic(2); guide.scroll.contentView.scroll(to: NSPoint(x: 0, y: 100)); guide.openTopic(0)
        precondition(guide.scroll.contentView.bounds.origin == .zero)
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

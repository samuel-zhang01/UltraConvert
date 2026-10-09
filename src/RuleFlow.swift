import AppKit

enum FlowTone {
    case arrival, decision, convert, rename, destination, original
    var color: NSColor {
        switch self {
        case .arrival: return .systemOrange
        case .decision: return .systemBlue
        case .convert: return .systemPurple
        case .rename: return .systemPink
        case .destination: return .systemGreen
        case .original: return .systemTeal
        }
    }
}

/// A bounded, native puzzle block. Colour supplements the word and symbol;
/// controls stay native and every ordering operation also has keyboard buttons.
final class RulePuzzleBlock: NSView {
    static let dragType = NSPasteboard.PasteboardType("local.ultraconvert.rule-action")
    let tone: FlowTone
    var drop: ((String, Bool) -> Bool)?
    var acceptsDrop: ((String) -> Bool)?
    private var dropBelow: Bool?
    override var isFlipped: Bool { true }
    init(content: NSView, tone: FlowTone) {
        self.tone = tone
        super.init(frame: .zero)
        pin(content, in: self, inset: 20)
        heightAnchor.constraint(equalTo: content.heightAnchor, constant: 40).isActive = true
        registerForDraggedTypes([Self.dragType])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width - 1, bottom = bounds.height - 11
        guard w > 100, bottom > 35 else { return }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 13, y: 10))
        p.line(to: NSPoint(x: 44, y: 10))
        p.curve(to: NSPoint(x: 53, y: 19), controlPoint1: NSPoint(x: 48, y: 10), controlPoint2: NSPoint(x: 48, y: 19))
        p.line(to: NSPoint(x: 75, y: 19))
        p.curve(to: NSPoint(x: 84, y: 10), controlPoint1: NSPoint(x: 80, y: 19), controlPoint2: NSPoint(x: 80, y: 10))
        p.line(to: NSPoint(x: w - 13, y: 10))
        p.curve(to: NSPoint(x: w, y: 23), controlPoint1: NSPoint(x: w, y: 10), controlPoint2: NSPoint(x: w, y: 10))
        p.line(to: NSPoint(x: w, y: bottom - 13))
        p.curve(to: NSPoint(x: w - 13, y: bottom), controlPoint1: NSPoint(x: w, y: bottom), controlPoint2: NSPoint(x: w, y: bottom))
        p.line(to: NSPoint(x: 84, y: bottom))
        p.curve(to: NSPoint(x: 75, y: bottom + 9), controlPoint1: NSPoint(x: 80, y: bottom), controlPoint2: NSPoint(x: 80, y: bottom + 9))
        p.line(to: NSPoint(x: 53, y: bottom + 9))
        p.curve(to: NSPoint(x: 44, y: bottom), controlPoint1: NSPoint(x: 48, y: bottom + 9), controlPoint2: NSPoint(x: 48, y: bottom))
        p.line(to: NSPoint(x: 13, y: bottom))
        p.curve(to: NSPoint(x: 1, y: bottom - 13), controlPoint1: NSPoint(x: 1, y: bottom), controlPoint2: NSPoint(x: 1, y: bottom))
        p.line(to: NSPoint(x: 1, y: 23))
        p.curve(to: NSPoint(x: 13, y: 10), controlPoint1: NSPoint(x: 1, y: 10), controlPoint2: NSPoint(x: 1, y: 10))
        p.close()
        NSColor.controlBackgroundColor.setFill(); p.fill()
        tone.color.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.22 : 0.12).setFill(); p.fill()
        tone.color.withAlphaComponent(0.65).setStroke(); p.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1; p.stroke()
        if let below = dropBelow {
            let line = NSBezierPath(); let y: CGFloat = below ? bottom - 2 : 12
            line.move(to: NSPoint(x: 12, y: y)); line.line(to: NSPoint(x: w - 12, y: y))
            NSColor.controlAccentColor.setStroke(); line.lineWidth = 4; line.stroke()
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let token = sender.draggingPasteboard.string(forType: Self.dragType), acceptsDrop?(token) == true else { return [] }
        dropBelow = convert(sender.draggingLocation, from: nil).y > bounds.midY
        needsDisplay = true; return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropBelow = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropBelow = nil; needsDisplay = true }
        guard let token = sender.draggingPasteboard.string(forType: Self.dragType), acceptsDrop?(token) == true else { return false }
        return drop?(token, convert(sender.draggingLocation, from: nil).y > bounds.midY) ?? false
    }
}

final class RuleDragHandle: NSImageView, NSDraggingSource {
    let token: String
    init(token: String) {
        self.token = token
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder action")
        toolTip = "Drag this grip to another action. Move Up and Move Down also work with the keyboard."
        setAccessibilityLabel("Drag to reorder action; keyboard users can use Move Up or Move Down")
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        guard let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged else { return }
        let item = NSPasteboardItem(); item.setString(token, forType: RulePuzzleBlock.dragType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: next, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
}

enum RuleFlowExample {
    static func inputFormat(_ rule: WatchRule) -> String {
        if rule.matchAll, let format = rule.conditions.first(where: { $0.field == .format })?.value { return format }
        let category = rule.matchAll ? rule.conditions.first(where: { $0.field == .category })?.value : nil
        return ["audio": "wav", "video": "mov", "image": "png", "document": "md", "geo": "geojson", "config": "json"][category ?? "audio"] ?? "wav"
    }
    /// This is an illustration, not file recognition or a promise of capability.
    static func names(_ rule: WatchRule, date: Date = Date()) -> [String] {
        var name = "Example"
        var format = inputFormat(rule)
        return rule.steps.map { step in
            if step.kind == .convert { format = step.value }
            else { name = (try? RuleNaming.render(step.value, name: name, format: format, date: date)) ?? "Invalid name template" }
            return name + "." + FormatCatalog.outputExtension(format)
        }
    }
}

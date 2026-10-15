import AppKit
import CoreFoundation
import Darwin

/// Read reports as local data, never as markup or executable commands. A batch
/// can have one report per source folder; the combined read has one size limit.
struct ConversionReportDocument {
    static let maximumBytes = 16 * 1024 * 1024
    let text: String
    let converted: Int
    let skipped: Int
    let failed: Int
    let reportsRead: Int
    let problems: Int
    let availableReports: [URL]
    var summary: String {
        guard reportsRead > 0 else { return "Report unavailable" }
        return "\(converted) converted · \(skipped) skipped · \(failed) failed" + (problems > 0 ? " · \(problems) report(s) need attention" : "")
    }

    static func load(_ urls: [URL], maximumBytes: Int = maximumBytes) -> ConversionReportDocument {
        var seen = Set<URL>()
        let reports = urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        var sections: [String] = [], available: [URL] = []
        var converted = 0, skipped = 0, failed = 0, reportsRead = 0, problems = 0, consumed = 0, resultCount = 0
        if reports.isEmpty {
            sections.append("No conversion report is available yet. Convert a batch first, then open Report to review its results.")
        }
        for url in reports.prefix(1_000) {
            do {
                let data = try boundedRead(url, limit: max(0, maximumBytes - consumed))
                consumed += data.count; available.append(url)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = object["results"] as? [[String: Any]] else { throw ReportReadError.malformed }
                guard results.count <= 1_000 - resultCount else { throw ReportReadError.tooManyResults }
                var entries: [String] = [], localConverted = 0, localSkipped = 0, localFailed = 0
                for (index, result) in results.enumerated() {
                    guard let path = result["path"] as? String, !path.isEmpty,
                          let success = boolean(result["success"]) else { throw ReportReadError.malformed }
                    let isSkipped = boolean(result["skipped"]) ?? false
                    let name = result["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
                    let state: String
                    if !success { state = "Failed"; localFailed += 1 }
                    else if isSkipped { state = "Skipped"; localSkipped += 1 }
                    else { state = "Converted"; localConverted += 1 }
                    var lines = ["\(index + 1). \(name) — \(state)", "Original: " + path]
                    if let source = result["format"] as? String, let target = result["target"] as? String {
                        lines.append("Format: " + source.uppercased() + " → " + target.uppercased())
                    }
                    if let output = result["output"] as? String, !output.isEmpty { lines.append("Output: " + output) }
                    if let error = result["error"] as? String, !error.isEmpty { lines.append("Error: " + error) }
                    else if !success { lines.append("No further error details were recorded.") }
                    if let notes = result["notes"] as? [String], !notes.isEmpty { lines.append("Notes:\n" + notes.map { "• " + $0 }.joined(separator: "\n")) }
                    entries.append(lines.joined(separator: "\n"))
                }
                var heading = "\(localConverted) converted · \(localSkipped) skipped · \(localFailed) failed"
                if let date = object["date"] as? String { heading += "\nDate: " + date }
                if boolean(object["cancelled"]) == true { heading += "\nThis batch was cancelled. Completed results are listed below." }
                sections.append(heading + "\nReport: " + url.path + "\n\n" + (entries.isEmpty ? "No file results were recorded." : entries.joined(separator: "\n\n")))
                converted += localConverted; skipped += localSkipped; failed += localFailed; reportsRead += 1; resultCount += results.count
            } catch {
                problems += 1
                let detail: String
                if let known = error as? ReportReadError {
                    detail = known.message
                    if case .tooLarge = known { available.append(url) }
                }
                else { detail = "This file is not a readable UltraConvert report. It may be incomplete or damaged." }
                sections.append("Report needs attention\n" + url.path + "\n" + detail + "\nYour files and completed conversions have not been changed by opening this report.")
            }
        }
        if reports.count > 1_000 { problems += 1; sections.append("Only the first 1,000 report files were read. Reveal the reports in Finder to inspect the remaining files.") }
        return ConversionReportDocument(text: sections.joined(separator: "\n\n────────────────────\n\n"), converted: converted, skipped: skipped, failed: failed, reportsRead: reportsRead, problems: problems, availableReports: available)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    private enum ReportReadError: Error {
        case unavailable, tooLarge, tooManyResults, malformed
        var message: String {
            switch self {
            case .unavailable: return "The report was moved, removed or cannot be read. Use Show Results to find any completed outputs."
            case .tooLarge: return "The report exceeds the 16 MiB combined reading limit. Reveal it in Finder to inspect it with a text editor."
            case .tooManyResults: return "The reports exceed UltraConvert’s 1,000-file batch limit. Reveal the report files in Finder to inspect the remaining results."
            case .malformed: return "This file is not a readable UltraConvert report. It may be incomplete or damaged."
            }
        }
    }
    private static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw ReportReadError.unavailable }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw ReportReadError.unavailable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG else { throw ReportReadError.unavailable }
        guard limit > 0, information.st_size >= 0, information.st_size <= limit else { throw ReportReadError.tooLarge }
        var data = Data()
        while let chunk = try file.read(upToCount: min(65_536, limit - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw ReportReadError.tooLarge }
        }
        return data
    }
}

final class ConversionReportWindow: NSWindowController, NSWindowDelegate {
    let summary = uiLabel("Reading local reports…", size: 13, weight: .medium)
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 360))
    let reveal = RuleButton("Reveal Report…", action: {})
    let copy = RuleButton("Copy Report", action: {})
    let done = RuleButton("Done", action: {})
    private(set) var reportDocument: ConversionReportDocument?
    private var loadID = UUID()

    init(reports: [URL], document: ConversionReportDocument? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Conversion Report — UltraConvert"; window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 400)
        super.init(window: window); window.delegate = self
        let heading = uiLabel("Conversion report", size: 22, weight: .semibold)
        let note = uiLabel("Read-only results. Opening or copying this report changes no files and sends nothing.", size: 13, color: .secondaryLabelColor)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        text.string = "Reading your local conversion reports…"; text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .systemFont(ofSize: 13); text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.minSize = .zero; text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true; text.textContainer?.containerSize = NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel("Complete conversion results, errors, notes and file locations"); scroll.documentView = text
        reveal.setAccessibilityLabel("Reveal report files in Finder"); reveal.isEnabled = false
        reveal.invoke = { [weak self] in guard let urls = self?.reportDocument?.availableReports, !urls.isEmpty else { return }; NSWorkspace.shared.activateFileViewerSelecting(Array(urls.prefix(8))) }
        copy.isEnabled = false
        copy.setAccessibilityLabel("Copy readable conversion report")
        copy.invoke = { [weak self] in
            guard let self, let report = self.reportDocument else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report.text, forType: .string)
            self.summary.stringValue = report.summary + " · copied to clipboard"
        }
        done.invoke = { [weak window] in window?.performClose(nil) }; done.keyEquivalent = "\u{1b}"; done.keyEquivalentModifierMask = []
        let footer = NSStackView(views: [reveal, copy, NSView(), done]); footer.spacing = 8
        let content = window.contentView!
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 600).isActive = true
        content.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        for view in [heading, summary, note, scroll, footer] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            summary.leadingAnchor.constraint(equalTo: heading.leadingAnchor), summary.trailingAnchor.constraint(equalTo: heading.trailingAnchor), summary.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            note.leadingAnchor.constraint(equalTo: heading.leadingAnchor), note.trailingAnchor.constraint(equalTo: heading.trailingAnchor), note.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: heading.trailingAnchor), scroll.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 16), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor), footer.trailingAnchor.constraint(equalTo: heading.trailingAnchor), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        window.setContentSize(NSSize(width: 740, height: 560)); window.center()
        if let document { apply(document) }
        else {
            let id = loadID
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let document = ConversionReportDocument.load(reports)
                DispatchQueue.main.async { [weak self] in guard let self, self.loadID == id else { return }; self.apply(document) }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func apply(_ document: ConversionReportDocument) {
        reportDocument = document; summary.stringValue = document.summary; text.string = document.text
        text.scrollRangeToVisible(NSRange(location: 0, length: 0)); reveal.isEnabled = !document.availableReports.isEmpty; copy.isEnabled = true
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    func windowWillClose(_ notification: Notification) { loadID = UUID() }
}

extension ConverterApp {
    func presentConversionReport() {
        let urls = reportURLs.isEmpty ? (resultURLs.isEmpty ? [resultURL].compactMap { $0 } : resultURLs).map { $0.appendingPathComponent("conversion-report.json") } : reportURLs
        reportController?.close(); reportController = ConversionReportWindow(reports: urls)
        if let panel = reportController?.window { InterfaceMotion.present(panel) }
    }
}

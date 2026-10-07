import AppKit

enum BatchPhase: Hashable {
    case empty, inspecting, ready, converting, complete, attention, checking
}

extension ConverterApp: NSTableViewDataSource, NSTableViewDelegate {
    func buildInterface() {
        let available = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: min(750, available.height - 90)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "UltraConvert"
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 570)
        window.center()
        let content = window.contentView!
        let body = NSScrollView()
        body.hasVerticalScroller = true
        body.autohidesScrollers = true
        body.drawsBackground = false
        body.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(body)
        let canvas = FlippedView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        body.documentView = canvas
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(stack)

        let title = uiLabel("UltraConvert", size: 26, weight: .semibold)
        let subtitle = uiLabel("Convert your files. Keep your originals.", size: 12, color: .secondaryLabelColor)
        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 46).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 46).isActive = true
        helpButton.bezelStyle = .helpButton
        helpButton.target = self; helpButton.action = #selector(showQuickStart)
        helpButton.toolTip = "Quick start, installation help and Finder settings"
        let rules = NSButton(title: "Folder Rules…", target: self, action: #selector(showFolderRules))
        rules.bezelStyle = .rounded; rules.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil); rules.imagePosition = .imageLeading
        let heading = NSStackView(views: [icon, titles, NSView(), rules, helpButton])
        heading.spacing = 12
        addFullWidth(heading)

        let columns = NSStackView()
        columns.orientation = .horizontal; columns.alignment = .top; columns.spacing = 16
        let queue = buildQueueCard()
        let targets = buildFormatsCard()
        columns.addArrangedSubview(queue); columns.addArrangedSubview(targets)
        queue.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: 0.52, constant: -8).isActive = true
        targets.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: 0.48, constant: -8).isActive = true
        queue.heightAnchor.constraint(equalTo: targets.heightAnchor).isActive = true
        targets.heightAnchor.constraint(greaterThanOrEqualToConstant: 335).isActive = true
        addFullWidth(columns)
        addFullWidth(buildDestinationCard())
        addFullWidth(buildOptionsCard())
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.isSelectable = true
        summary.isHidden = true
        addFullWidth(summary)

        let footer = buildConversionBar()
        content.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            body.topAnchor.constraint(equalTo: content.topAnchor),
            body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            canvas.widthAnchor.constraint(equalTo: body.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        refreshQueue()
        refreshPresentation()
    }

    func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func buildQueueCard() -> NSView {
        let card = RoundedCard()
        let contents = card.contents
        let title = uiLabel("Files", size: 15, weight: .semibold)
        queueCount.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        queueCount.textColor = .secondaryLabelColor
        choose.title = "Add Files…"
        styleButton(choose, symbol: "plus", action: #selector(pickFiles))
        let heading = NSStackView(views: [title, queueCount, NSView(), choose])
        heading.spacing = 8
        contents.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        queueSurface.translatesAutoresizingMaskIntoConstraints = false
        queueSurface.onDrop = { [weak self] paths in self?.appendFiles(paths) }
        queueSurface.canAccept = { [weak self] in self?.busy == false }
        contents.addArrangedSubview(queueSurface)
        queueSurface.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        queueSurface.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        let empty = NSStackView(views: [uiSymbol("square.and.arrow.down", size: 32),
                                      uiLabel("Drop files here", size: 17, weight: .medium),
                                      uiLabel("or add them from Finder", size: 12, color: .secondaryLabelColor)])
        empty.orientation = .vertical; empty.spacing = 10
        empty.translatesAutoresizingMaskIntoConstraints = false
        queueSurface.addSubview(empty)
        queueEmpty = empty
        queueScroll.hasVerticalScroller = true
        queueScroll.autohidesScrollers = true
        queueScroll.drawsBackground = false
        queueScroll.borderType = .noBorder
        queueScroll.translatesAutoresizingMaskIntoConstraints = false
        queueSurface.addSubview(queueScroll)
        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        fileTable.addTableColumn(column)
        fileTable.headerView = nil
        fileTable.style = .fullWidth
        fileTable.rowHeight = 56
        fileTable.intercellSpacing = NSSize(width: 0, height: 2)
        fileTable.allowsMultipleSelection = true
        fileTable.backgroundColor = .clear
        fileTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        fileTable.dataSource = self; fileTable.delegate = self
        fileTable.setAccessibilityLabel("Conversion file queue")
        fileTable.onRemove = { [weak self] in self?.removeSelectedFiles() }
        buildQueueMenu()
        queueScroll.documentView = fileTable
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: queueSurface.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: queueSurface.centerYAnchor),
            queueScroll.leadingAnchor.constraint(equalTo: queueSurface.leadingAnchor, constant: 1),
            queueScroll.trailingAnchor.constraint(equalTo: queueSurface.trailingAnchor, constant: -1),
            queueScroll.topAnchor.constraint(equalTo: queueSurface.topAnchor, constant: 1),
            queueScroll.bottomAnchor.constraint(equalTo: queueSurface.bottomAnchor, constant: -1)
        ])
        styleButton(removeFilesButton, symbol: "minus", action: #selector(removeSelectedFiles))
        styleButton(clearFilesButton, symbol: "trash", action: #selector(clearFiles))
        removeFilesButton.controlSize = .small; clearFilesButton.controlSize = .small
        let actions = NSStackView(views: [removeFilesButton, NSView(), clearFilesButton])
        actions.spacing = 8
        contents.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        return card
    }

    func buildFormatsCard() -> NSView {
        let card = RoundedCard()
        card.contents.addArrangedSubview(uiLabel("Output formats", size: 15, weight: .semibold))
        formats.orientation = .vertical; formats.alignment = .leading; formats.spacing = 12
        formatsScroll.hasVerticalScroller = true
        formatsScroll.autohidesScrollers = true
        formatsScroll.drawsBackground = false
        let canvas = FlippedView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        formatsScroll.documentView = canvas
        formats.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(formats)
        card.contents.addArrangedSubview(formatsScroll)
        NSLayoutConstraint.activate([
            formatsScroll.widthAnchor.constraint(equalTo: card.contents.widthAnchor),
            formatsScroll.heightAnchor.constraint(equalToConstant: 230),
            canvas.widthAnchor.constraint(equalTo: formatsScroll.contentView.widthAnchor),
            formats.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            formats.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -3),
            formats.topAnchor.constraint(equalTo: canvas.topAnchor),
            formats.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])
        formatHint.font = .systemFont(ofSize: 16, weight: .medium)
        formatEmpty = NSStackView(views: [uiSymbol("slider.horizontal.3", size: 28),
                                        formatHint,
                                        uiLabel("Compatible formats appear for each type of file.", size: 12, color: .secondaryLabelColor)])
        formatEmpty.orientation = .vertical; formatEmpty.spacing = 10
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        formatEmpty.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(formatEmpty)
        card.contents.addArrangedSubview(holder)
        formatPlaceholder = holder
        holder.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            formatEmpty.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            formatEmpty.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            formatEmpty.widthAnchor.constraint(lessThanOrEqualTo: holder.widthAnchor, constant: -10)
        ])
        crs.placeholderString = "Input CRS, e.g. EPSG:4326"
        crs.toolTip = "Required for WKT without a .prj file or SRID. Use the known source CRS; never guess."
        crs.setAccessibilityLabel("Known input coordinate reference system")
        crs.isHidden = true
        card.contents.addArrangedSubview(crs)
        crs.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        card.contents.addArrangedSubview(uiLabel("Formats are detected from file contents where possible.", size: 11, color: .secondaryLabelColor))
        return card
    }

    func buildDestinationCard() -> NSView {
        let card = RoundedCard()
        location.addItems(withTitles: ["Beside source files", "Saved destination", "Choose destination…"])
        location.target = self; location.action = #selector(locationChanged)
        location.setAccessibilityLabel("Output location")
        location.widthAnchor.constraint(equalToConstant: 200).isActive = true
        styleButton(destination, symbol: "folder", action: #selector(pickDestination))
        styleButton(saveDefault, symbol: "pin", action: #selector(saveDefaultFolder))
        let row = NSStackView(views: [uiSymbol("folder", size: 18), uiLabel("Save to", size: 14, weight: .semibold), location, NSView(), destination, saveDefault])
        row.spacing = 10
        card.contents.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        destinationPath.font = .systemFont(ofSize: 11)
        destinationPath.textColor = .secondaryLabelColor
        destinationPath.isSelectable = true
        card.contents.addArrangedSubview(destinationPath)
        destinationPath.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        return card
    }

    func buildOptionsCard() -> NSView {
        let card = RoundedCard()
        optionsDisclosure.title = "Batch options"
        optionsDisclosure.setButtonType(.pushOnPushOff)
        optionsDisclosure.isBordered = false
        optionsDisclosure.font = .systemFont(ofSize: 13, weight: .medium)
        optionsDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        optionsDisclosure.imagePosition = .imageLeading
        optionsDisclosure.target = self; optionsDisclosure.action = #selector(toggleOptions)
        optionsDisclosure.setAccessibilityLabel("Show conversion options")
        let heading = NSStackView(views: [optionsDisclosure, NSView(), uiLabel("Originals are always kept", size: 11, color: .secondaryLabelColor)])
        heading.spacing = 8
        card.contents.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        optionsBody.orientation = .vertical; optionsBody.alignment = .leading; optionsBody.spacing = 10
        optionsBody.isHidden = true
        skipSame.toolTip = "Matching files are recorded as skipped and remain in their original folder."
        skipSame.state = preferences.bool(forKey: "skipSame") ? .on : .off
        openAfter.state = preferences.bool(forKey: "openAfter") ? .on : .off
        jobs.addItems(withTitles: ["1 file at a time", "2 files at a time", "3 files at a time", "4 files at a time"])
        jobs.selectItem(at: max(0, min(3, preferences.integer(forKey: "jobs") == 0 ? 1 : preferences.integer(forKey: "jobs") - 1)))
        jobs.toolTip = "Two jobs suit most batches; use one for large media or GIS files."
        jobs.setAccessibilityLabel("Batch concurrency")
        optionsBody.addArrangedSubview(skipSame)
        optionsBody.addArrangedSubview(openAfter)
        let concurrency = NSStackView(views: [uiLabel("Convert", size: 12, color: .secondaryLabelColor), jobs]); concurrency.spacing = 10
        optionsBody.addArrangedSubview(concurrency)
        card.contents.addArrangedSubview(optionsBody)
        optionsBody.widthAnchor.constraint(equalTo: card.contents.widthAnchor).isActive = true
        return card
    }

    func buildConversionBar() -> NSView {
        let contents = NSStackView()
        contents.orientation = .vertical; contents.alignment = .leading; contents.spacing = 10
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.maximumNumberOfLines = 3
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        styleButton(start, symbol: "arrow.triangle.2.circlepath", action: #selector(convertFiles))
        styleButton(cancel, symbol: "xmark", action: #selector(cancelConversion))
        styleButton(reveal, symbol: "folder.badge.checkmark", action: #selector(showResults))
        styleButton(reportButton, symbol: "doc.text", action: #selector(showReport))
        styleButton(retryButton, symbol: "arrow.clockwise", action: #selector(retryFailed))
        start.controlSize = .large
        start.font = .systemFont(ofSize: 13, weight: .semibold)
        start.keyEquivalent = "\r"
        start.widthAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
        start.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        reportButton.title = "Report"
        let row = NSStackView(views: [statusIcon, status])
        row.spacing = 10
        contents.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        status.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -28).isActive = true
        let actions = NSStackView(views: [NSView(), reportButton, reveal, retryButton, cancel, start])
        actions.spacing = 8
        contents.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        retryButton.isHidden = true
        progress.minValue = 0; progress.maxValue = 1
        progress.isIndeterminate = false; progress.style = .bar
        progress.controlSize = .small
        contents.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        var background: NSView
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular; glass.cornerRadius = 20
            let host = NSView()
            glass.contentView = host
            pin(contents, in: host, inset: 16)
            background = glass
        } else {
            background = legacyActionBar(contents)
        }
        #else
        background = legacyActionBar(contents)
        #endif
        background.heightAnchor.constraint(equalTo: contents.heightAnchor, constant: 32).isActive = true
        return background
    }

    func legacyActionBar(_ contents: NSView) -> NSView {
        let background = NSVisualEffectView()
        background.material = .headerView
        background.blendingMode = .withinWindow
        background.state = .followsWindowActiveState
        background.wantsLayer = true; background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        pin(contents, in: background, inset: 16)
        return background
    }

    func styleButton(_ button: NSButton, symbol: String, action: Selector) {
        button.target = self; button.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
    }

    func refreshPresentation() {
        let symbols: [BatchPhase: String] = [.empty: "circle.dashed", .inspecting: "doc.text.magnifyingglass", .ready: "checkmark.circle", .converting: "arrow.triangle.2.circlepath", .complete: "checkmark.circle.fill", .attention: "exclamationmark.triangle", .checking: "checkmark.shield"]
        statusIcon.image = NSImage(systemSymbolName: symbols[phase] ?? "circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = phase == .attention ? .systemOrange : (phase == .complete ? .systemGreen : .secondaryLabelColor)
        let count = infos.filter { $0["error"] is NSNull }.count
        start.title = phase == .converting ? "Converting…" : (count > 0 ? "Convert \(count) \(count == 1 ? "File" : "Files")" : "Convert")
        cancel.isHidden = !busy
        start.isHidden = phase == .converting
        progress.isHidden = !busy
        summary.isHidden = summary.stringValue.isEmpty
        removeFilesButton.isEnabled = !busy && !fileTable.selectedRowIndexes.isEmpty
        clearFilesButton.isEnabled = !busy && !files.isEmpty
        retryButton.isHidden = busy || failedPaths.isEmpty
        queueSurface.needsDisplay = true
    }

    func refreshQueue() {
        outcomeRefresh?.cancel(); outcomeRefresh = nil; changedRows = []
        queueRows = !infos.isEmpty ? infos : files.map { ["path": $0, "name": URL(fileURLWithPath: $0).lastPathComponent] }
        rowByPath = [:]
        for (row, item) in queueRows.enumerated() { if let path = item["path"] as? String { rowByPath[path] = row } }
        queueCount.stringValue = "\(queueItems.count)"
        queueEmpty.isHidden = !queueItems.isEmpty
        queueScroll.isHidden = queueItems.isEmpty
        fileTable.reloadData()
        formatPlaceholder.isHidden = !selectors.isEmpty
        formatsScroll.isHidden = selectors.isEmpty
        formatHint.stringValue = phase == .inspecting ? "Recognising formats…" : (files.isEmpty ? "Choose files first" : "No compatible formats")
        refreshPresentation()
    }

    var queueItems: [[String: Any]] {
        queueRows
    }

    func numberOfRows(in tableView: NSTableView) -> Int { queueItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = queueItems
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        let cell = (tableView.makeView(withIdentifier: .init("fileCell"), owner: self) as? QueueCell) ?? QueueCell()
        cell.identifier = .init("fileCell")
        let path = item["path"] as? String ?? ""
        let name = item["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
        let format = (item["format"] as? String ?? "").uppercased()
        let detail: String
        let color: NSColor
        if let outcome = outcomes[path] {
            detail = outcome.failed ? "Failed · right-click for error details" : outcome.text
            color = outcome.failed ? .systemRed : .secondaryLabelColor
        } else if item["error"] is String {
            detail = "Unsupported · right-click for error details"; color = .systemRed
        } else {
            let category = item["category"] as? String ?? ""
            let target = (selectors[category]?.selectedItem?.representedObject as? String)?.uppercased()
            let conversion = target.map { format + " → " + $0 } ?? format
            detail = format.isEmpty ? (phase == .attention ? "Not inspected · see status below" : "Detecting file type…") : "\(conversion) · \(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)"
            color = .secondaryLabelColor
        }
        if fileIcons[path] == nil { fileIcons[path] = NSWorkspace.shared.icon(forFile: path) }
        cell.configure(name: name, detail: detail, icon: fileIcons[path], color: color, path: path)
        if let error = outcomes[path].flatMap({ $0.failed ? $0.text : nil }) ?? item["error"] as? String {
            cell.toolTip = path + "\n" + error
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refreshPresentation() }

    func appendFiles(_ added: [String]) {
        guard !busy else { return }
        let combined = uniquePaths(files + added)
        guard combined.count <= 1000 else {
            status.stringValue = "Select at most 1,000 files per batch."
            phase = .attention; refreshPresentation(); return
        }
        if !combined.isEmpty { loadFiles(combined) }
    }

    @objc func removeSelectedFiles() {
        guard !busy else { return }
        let selected = fileTable.selectedRowIndexes
        guard !selected.isEmpty else { return }
        let items = queueItems
        let remaining = items.enumerated().filter { !selected.contains($0.offset) }.compactMap { $0.element["path"] as? String }
        if remaining.isEmpty { clearFiles() } else { loadFiles(remaining) }
    }

    @objc func clearFiles() {
        guard !busy else { return }
        files = []; infos = []; fileIcons = [:]
        resetOutcomes()
        presetFormat = nil
        selectors.removeAll()
        formats.arrangedSubviews.forEach { formats.removeArrangedSubview($0); $0.removeFromSuperview() }
        resultURL = nil; resultURLs = []; lastSummary = ""
        reportURLs = []; publishedURLs = []; resultsHere = false
        reveal.isHidden = true; reportButton.isHidden = true
        crs.stringValue = ""; crs.isHidden = true
        status.stringValue = "Drop files or add them to get started."
        summary.stringValue = ""
        start.isEnabled = false
        phase = .empty
        refreshQueue()
    }

    @objc func toggleOptions() {
        optionsBody.isHidden = optionsDisclosure.state != .on
        optionsDisclosure.image = NSImage(systemSymbolName: optionsBody.isHidden ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        optionsDisclosure.setAccessibilityLabel(optionsBody.isHidden ? "Show conversion options" : "Hide conversion options")
    }

    @objc func formatChanged(_ sender: NSPopUpButton) {
        if let entry = selectors.first(where: { $0.value === sender }), let value = sender.selectedItem?.representedObject as? String {
            draftTargets[entry.key] = value
        }
        fileTable.reloadData()
    }
}

func uiLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

func uiSymbol(_ name: String, size: CGFloat) -> NSImageView {
    let view = NSImageView()
    view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    view.contentTintColor = .secondaryLabelColor
    view.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
    view.heightAnchor.constraint(equalToConstant: size + 4).isActive = true
    return view
}

func pin(_ view: NSView, in host: NSView, inset: CGFloat) {
    view.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -inset),
        view.topAnchor.constraint(equalTo: host.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -inset)
    ])
}

final class RoundedCard: NSView {
    let contents = NSStackView()
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        contents.orientation = .vertical; contents.alignment = .leading; contents.spacing = 12
        pin(contents, in: self, inset: 16)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() {
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.35).cgColor
        layer?.borderWidth = 1
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class FileDropView: NSView {
    var onDrop: (([String]) -> Void)?
    var canAccept: (() -> Bool)?
    private var hovering = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Drop files to add them to the conversion queue")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        (hovering ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = hovering ? 2 : 1
        if !hovering { path.setLineDash([5, 4], count: 2, phase: 0) }
        path.stroke()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept?() == true,
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        hovering = true; needsDisplay = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { hovering = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false; needsDisplay = true
        guard canAccept?() == true,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        // The converter performs the same inspection and safety checks as picker/Finder inputs.
        onDrop?(urls.map(\.path))
        return true
    }
}

final class QueueTable: NSTableView {
    var onRemove: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117) && !selectedRowIndexes.isEmpty { onRemove?() }
        else { super.keyDown(with: event) }
    }
}

final class QueueCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let icon = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 10)
        detail.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let labels = NSStackView(views: [name, detail])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 3
        let row = NSStackView(views: [icon, labels]); row.spacing = 10
        pin(row, in: self, inset: 8)
        labels.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -40).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(name: String, detail: String, icon: NSImage?, color: NSColor, path: String) {
        self.name.stringValue = name
        self.detail.stringValue = detail
        self.detail.textColor = color
        self.icon.image = icon
        toolTip = path + "\n" + detail
        setAccessibilityLabel(name + ", " + detail)
    }
}

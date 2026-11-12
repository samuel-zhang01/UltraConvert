import AppKit

enum CompressionQuality {
    static let images: Set<String> = ["jpg", "jpeg", "webp", "avif", "heic"]
    static let audio: [String: [Int]] = [
        "mp3": [64, 96, 128, 160, 192, 256, 320],
        "aac": [48, 64, 96, 128, 160, 192, 256, 320],
        "m4a": [48, 64, 96, 128, 160, 192, 256, 320],
        "wma": [48, 64, 96, 128, 160, 192, 256, 320],
        "opus": [24, 32, 48, 64, 96, 128, 160, 192, 256],
        "ogg": [64, 80, 96, 112, 128, 160, 192]
    ]
    static let video = Set(FormatCatalog.groups.first { $0.id == "video" }?.formats ?? []).subtracting(["gif", "mxf"])
    static func supports(_ format: String) -> Bool { images.contains(format) || audio[format] != nil || video.contains(format) }
    static func bitrate(_ format: String, quality: Int) -> Int? {
        guard let ladder = audio[format], (1...100).contains(quality) else { return nil }
        return ladder[((quality - 1) * (ladder.count - 1) + 49) / 99]
    }
    static func estimatedAudioBytes(duration: Double, format: String, quality: Int) -> Double? {
        guard duration.isFinite, duration > 0, let kbps = bitrate(format, quality: quality) else { return nil }
        let bytes = duration * Double(kbps) * 1000 / 8
        return bytes.isFinite && bytes > 0 ? bytes : nil
    }
    static func sameFormat(_ source: String, _ target: String) -> Bool {
        let aliases = ["jpeg": "jpg", "yml": "yaml", "mpeg": "mpg"]
        return (aliases[source] ?? source) == (aliases[target] ?? target)
    }
    static func sourceComparison(bytes: Double, infos: [[String: Any]]) -> String {
        let sizes = infos.compactMap { info -> Double? in
            guard let number = info["size_bytes"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        guard !sizes.isEmpty, sizes.count == infos.count, sizes.allSatisfy({ $0.isFinite && $0 > 0 }) else { return "" }
        let original = sizes.reduce(0, +)
        guard original.isFinite, bytes.isFinite, bytes > 0 else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(min(original, Double(Int64.max / 2))), countStyle: .file)
        let change = (bytes / original - 1) * 100
        guard change.isFinite else { return "" }
        let relation = abs(change) < 1 ? "about the same size" : "about \(abs(change).formatted(.number.precision(.fractionLength(0))))% \(change < 0 ? "smaller" : "larger")"
        return "Source\(infos.count == 1 ? "" : "s"): \(size) · \(relation)."
    }
}

final class CompressionControl: NSView {
    let category: String
    let preferences: UserDefaults
    let custom = NSButton(checkboxWithTitle: "Custom quality", target: nil, action: nil)
    let slider = NSSlider(value: 75, minValue: 1, maxValue: 100, target: nil, action: nil)
    let valueLabel = uiLabel("", size: 13, weight: .medium)
    let estimate = uiLabel("", size: 13, color: .labelColor)
    let skipNotice = uiLabel("", size: 13, color: .secondaryLabelColor)
    let sampleButton = NSButton(title: "Estimate Size…", target: nil, action: nil)
    let adjustment = NSStackView()
    var target: String
    var infos: [[String: Any]]
    var pendingSave: DispatchWorkItem?
    var estimateAction: ((CompressionControl) -> Void)?
    var sampleResult: (key: Data, text: String)?
    var skipsMatchingFiles = false
    var conversionInfos: [[String: Any]] {
        infos.filter { !skipsMatchingFiles || !CompressionQuality.sameFormat($0["format"] as? String ?? "", target) }
    }
    var estimateKey: Data? {
        guard let quality else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["files": conversionInfos, "target": target, "quality": quality], options: .sortedKeys)
    }
    var canSample: Bool {
        guard category == "video", CompressionQuality.video.contains(target), conversionInfos.count == 1,
              let duration = conversionInfos.first?["duration"] as? Double else { return false }
        return duration.isFinite && duration > 0 && quality != nil && estimateAction != nil
    }
    var quality: Int? { !custom.isHidden && custom.state == .on ? Int(slider.doubleValue.rounded()) : nil }

    init(category: String, target: String, infos: [[String: Any]], preferences: UserDefaults) {
        self.category = category; self.target = target; self.infos = infos; self.preferences = preferences
        super.init(frame: .zero)
        let saved = (preferences.dictionary(forKey: "compressionQuality")?[category] as? Int).flatMap { (1...100).contains($0) ? $0 : nil }
        slider.doubleValue = Double(saved ?? 75); custom.state = saved == nil ? .off : .on
        custom.target = self; custom.action = #selector(changed(_:)); custom.font = .systemFont(ofSize: 13)
        custom.setAccessibilityLabel("Custom quality for \(category) output")
        slider.target = self; slider.action = #selector(changed(_:)); slider.isContinuous = true
        slider.setAccessibilityLabel("\(category.capitalized) quality, smaller file to higher quality")
        slider.toolTip = "Encoder quality, not a percentage of file size. Even 100 may still be lossy. Higher settings cannot restore detail missing from the source."
        let header = NSStackView(views: [custom, NSView(), valueLabel]); header.spacing = 8
        adjustment.orientation = .vertical; adjustment.alignment = .leading; adjustment.spacing = 6
        let ends = NSStackView(views: [uiLabel("Smaller", size: 13, color: .secondaryLabelColor), NSView(), uiLabel("Higher quality", size: 13, color: .secondaryLabelColor)])
        ends.spacing = 8
        adjustment.addArrangedSubview(slider); adjustment.addArrangedSubview(ends)
        slider.widthAnchor.constraint(equalTo: adjustment.widthAnchor).isActive = true
        ends.widthAnchor.constraint(equalTo: adjustment.widthAnchor).isActive = true
        sampleButton.target = self; sampleButton.action = #selector(requestEstimate)
        sampleButton.toolTip = "Encode short temporary samples to estimate the size at this quality."
        let stack = NSStackView(views: [skipNotice, header, adjustment, sampleButton, estimate]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        pin(stack, in: self, inset: 0)
        for view in [skipNotice, header, adjustment, estimate] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        estimate.isSelectable = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc func requestEstimate() { if canSample && sampleButton.isEnabled { estimateAction?(self) } }
    func persist() {
        pendingSave?.cancel(); pendingSave = nil
        var saved = preferences.dictionary(forKey: "compressionQuality") as? [String: Int] ?? [:]
        if custom.state == .on { saved[category] = Int(slider.doubleValue.rounded()) } else { saved.removeValue(forKey: category) }
        preferences.set(saved, forKey: "compressionQuality")
    }
    @objc func changed(_ sender: NSControl) {
        if sender === custom {
            persist()
            // NSStackView visibility changes must settle before revealing the
            // controls. Animating its hidden constraints and clip bounds at
            // once made repeated toggles stretch and bounce the whole panel.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0; context.allowsImplicitAnimation = false
                refresh(); (window?.contentView ?? self).layoutSubtreeIfNeeded()
            }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? NSScrollView, let document = scroll.documentView {
                    let visible = scroll.documentVisibleRect, rect = convert(bounds, to: document)
                    var y = visible.minY
                    if custom.state == .on {
                        if rect.maxY > visible.maxY { y = rect.maxY - visible.height + 8 }
                        else if rect.minY < visible.minY { y = rect.minY - 8 }
                    }
                    // One immediate, minimal reveal keeps the checkbox and
                    // estimate coherent; no second scroll animation competes
                    // with the native checkmark or the content fade.
                    InterfaceMotion.snapScroll(scroll, to: NSPoint(x: visible.minX, y: max(0, min(y, max(0, document.bounds.height - visible.height)))))
                    break
                }
                ancestor = view.superview
            }
            if custom.state == .on {
                InterfaceMotion.reveal(adjustment); InterfaceMotion.reveal(estimate)
            }
        } else {
            refresh()
            pendingSave?.cancel()
            let save = DispatchWorkItem { [weak self] in self?.persist() }
            pendingSave = save; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: save)
        }
    }
    func refresh() {
        let supported = CompressionQuality.supports(target)
        let active = conversionInfos, skipped = infos.count - active.count
        skipNotice.isHidden = skipped == 0
        skipNotice.stringValue = "\(skipped) of \(infos.count) will be skipped. To re-encode matching files, turn off ‘Skip files already in target format’ in Batch options."
        custom.isHidden = !supported; adjustment.isHidden = !supported || custom.state == .off
        valueLabel.isHidden = adjustment.isHidden
        if let rates = CompressionQuality.audio[target] {
            slider.numberOfTickMarks = rates.count; slider.allowsTickMarkValuesOnly = true
            valueLabel.stringValue = "\(CompressionQuality.bitrate(target, quality: Int(slider.doubleValue.rounded())) ?? 0) kb/s"
        } else {
            slider.numberOfTickMarks = 0; slider.allowsTickMarkValuesOnly = false
            valueLabel.stringValue = "\(Int(slider.doubleValue.rounded())) / 100"
        }
        estimate.isHidden = !supported || custom.state == .off
        let videoEstimate = canSample
        sampleButton.isHidden = estimate.isHidden || !videoEstimate
        sampleButton.title = sampleResult == nil ? "Estimate Size…" : "Estimate Again…"
        guard supported, let quality else { estimate.stringValue = ""; return }
        guard !active.isEmpty || infos.isEmpty else {
            estimate.stringValue = "No output will be created for this group. Custom quality will not be applied."
            return
        }
        if let bitrate = CompressionQuality.bitrate(target, quality: quality) {
            let durations = active.compactMap { $0["duration"] as? Double }.filter { $0.isFinite && $0 > 0 }
            if durations.count == active.count, !durations.isEmpty,
               let bytes = CompressionQuality.estimatedAudioBytes(duration: durations.reduce(0, +), format: target, quality: quality) {
                let amount = ByteCountFormatter.string(fromByteCount: Int64(min(bytes, Double(Int64.max / 2))), countStyle: .file)
                let comparison = CompressionQuality.sourceComparison(bytes: bytes, infos: active)
                estimate.stringValue = "Estimated audio size ≈ \(amount)\(active.count > 1 ? " total for \(active.count) files" : "")\n\(comparison.isEmpty ? "" : comparison + "\n")Based on duration and bitrate; actual size varies. Short clips can be larger because of file overhead."
            } else { estimate.stringValue = "\(bitrate) kb/s target. Size estimate needs a known duration; actual size varies. Custom audio uses 48 kHz." }
        } else if videoEstimate {
            if let sampleResult, sampleResult.key == estimateKey {
                estimate.stringValue = sampleResult.text
            } else {
                estimate.stringValue = sampleResult == nil
                    ? "Estimate Size samples up to 12 seconds of video. Your original stays unchanged."
                    : "Settings or source changed. Estimate again for this selection."
            }
        } else if CompressionQuality.video.contains(target), active.count == 1 {
            estimate.stringValue = "Size estimate unavailable: this video’s duration could not be read. You can still try converting it."
        } else {
            estimate.stringValue = "\(target.uppercased()) quality \(quality). Even 100 may be lossy. Size depends on \(CompressionQuality.images.contains(target) ? "image detail" : "picture detail and motion"); no reliable estimate before encoding.\(CompressionQuality.video.contains(target) ? " Audio, if present, uses 48 kHz." : "")"
        }
    }
    func setEnabled(_ enabled: Bool) { custom.isEnabled = enabled; slider.isEnabled = enabled; sampleButton.isEnabled = enabled }

    func revealEstimate() {
        (window?.contentView ?? self).layoutSubtreeIfNeeded()
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView, let document = scroll.documentView {
                var rect = estimate.convert(estimate.bounds, to: document)
                if !sampleButton.isHidden { rect = rect.union(sampleButton.convert(sampleButton.bounds, to: document)) }
                let visible = scroll.documentVisibleRect
                let y = rect.height > visible.height || rect.minY < visible.minY
                    ? rect.minY - 8 : max(visible.minY, rect.maxY - visible.height + 8)
                InterfaceMotion.snapScroll(scroll, to: NSPoint(x: visible.minX, y: max(0, min(y, max(0, document.bounds.height - visible.height)))))
                return
            }
            ancestor = view.superview
        }
    }
}

extension ConverterApp {
    func estimateVideoSize(_ control: CompressionControl) {
        guard !busy, control.canSample, let key = control.estimateKey, let quality = control.quality,
              let path = control.conversionInfos.first?["path"] as? String else { return }
        let target = control.target
        let sourceInfos = control.conversionInfos
        let previousStatus = status.stringValue
        let previousProgress = progress.doubleValue
        isEstimatingSize = true
        setBusy(true)
        progress.doubleValue = 0
        progress.isIndeterminate = true; progress.startAnimation(nil)
        status.stringValue = "Estimating size from short video samples…"
        launch(["--estimate-video-size", "--progress", "--to", target, "--quality", String(quality), "--", path]) { code, output, error in
            let result = output.split(separator: "\n").last.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            let text: String
            if code == 0, let bytes = result?["estimated_bytes"] as? Double, bytes.isFinite, bytes > 0,
               let seconds = result?["sample_seconds"] as? Double, seconds.isFinite, seconds > 0 {
                let amount = ByteCountFormatter.string(fromByteCount: Int64(min(bytes, Double(Int64.max / 2))), countStyle: .file)
                let comparison = CompressionQuality.sourceComparison(bytes: bytes, infos: sourceInfos)
                text = "Estimated \(target.uppercased()) size ≈ \(amount)\n\(comparison.isEmpty ? "" : comparison + "\n")Based on \(seconds.formatted(.number.precision(.fractionLength(0...1)))) seconds of sample encoding. Actual size may vary by scene."
            } else if code == 130 {
                text = "Size estimate cancelled. You can try again."
            } else {
                let detail = result?["error"] as? String ?? (error.isEmpty ? "The video could not be sampled." : error)
                text = "Size estimate unavailable. " + String(detail.prefix(240)) + "\nYou can still try converting the file."
            }
            control.sampleResult = (key, text)
            control.refresh()
            control.revealEstimate()
            self.status.stringValue = previousStatus
            self.progress.doubleValue = previousProgress
            self.isEstimatingSize = false
            self.setBusy(false)
            self.loadPendingFiles()
        }
    }

    func flushQualityPreferences() { for control in qualityControls.values { control.persist() } }
    var qualityArguments: [String] {
        flushQualityPreferences()
        return ["image", "audio", "video"].flatMap { category in
            qualityControls[category]?.quality.map { ["--quality-" + category, String($0)] } ?? []
        }
    }
}

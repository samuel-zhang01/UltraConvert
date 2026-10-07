import Foundation
import Darwin

final class AutomationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Process?
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw AutomationIssue("Cancelled. The original was kept.") } }
    func attach(_ process: Process) throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw AutomationIssue("Cancelled. The original was kept.") }; task = process }
    func detach() { lock.lock(); task = nil; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; let running = task; lock.unlock(); if running?.isRunning == true { running?.terminate() } }
}

protocol AutomationEngine {
    func inspect(_ url: URL, cancellation: AutomationCancellation) throws -> RecognizedFile
    func convert(_ file: RecognizedFile, to format: String, staging: URL, cancellation: AutomationCancellation) throws -> URL
}

final class NativeAutomationEngine: AutomationEngine {
    let backend: BackendPaths
    init(backend: BackendPaths) { self.backend = backend }
    func call(_ args: [String], cancellation: AutomationCancellation) throws -> String {
        try cancellation.check()
        let task = Process(); task.executableURL = backend.python
        task.arguments = backend.bundled ? ["-I", "-S", "-B", backend.source.appendingPathComponent("bootstrap.py").path, "convert.py"] + args : ["-E", "-s", "-B", backend.source.appendingPathComponent("convert.py").path] + args
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PYTHON") && !$0.key.hasPrefix("DYLD_") && $0.key != "LD_PRELOAD" && $0.key != "__PYVENV_LAUNCHER__" }
        environment.merge(backend.environment) { _, value in value }; environment["PYTHONDONTWRITEBYTECODE"] = "1"
        task.environment = environment
        let stdout = Pipe(), stderr = Pipe(); task.standardOutput = stdout; task.standardError = stderr
        try cancellation.attach(task)
        defer { cancellation.detach() }
        try task.run()
        // Cancellation can arrive between attach and run. Check again after
        // launch and terminate the child before draining its pipes.
        do { try cancellation.check() } catch { if task.isRunning { task.terminate() } }
        let errorCapture = LockedCapture(), group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true { let chunk = stderr.fileHandleForReading.availableData; if chunk.isEmpty { break }; errorCapture.append(chunk) }
            group.leave()
        }
        var data = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData; if chunk.isEmpty { break }
            data.append(chunk); if data.count > 8 * 1024 * 1024 { data.removeFirst(data.count - 8 * 1024 * 1024) }
        }
        task.waitUntilExit(); group.wait(); try cancellation.check()
        guard task.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            let events = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let diagnostic = (events.last?["results"] as? [[String: Any]])?.first?["error"] as? String
            let error = diagnostic ?? errorCapture.text()
            throw AutomationIssue(error.isEmpty ? "Conversion failed. The original was kept." : String(error.suffix(2000)))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    func inspect(_ url: URL, cancellation: AutomationCancellation) throws -> RecognizedFile {
        let output = try call(["--inspect", "--", url.path], cancellation: cancellation)
        guard let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any], let files = object["files"] as? [[String: Any]], let file = files.first else { throw AutomationIssue("The conversion engine returned an invalid inspection.") }
        if let error = file["error"] as? String { throw AutomationIssue(error) }
        guard let format = file["format"] as? String, let category = file["category"] as? String, let targets = file["targets"] as? [String] else { throw AutomationIssue("Could not recognise this file.") }
        return .init(url: url, format: format, category: category, targets: targets)
    }
    func convert(_ file: RecognizedFile, to format: String, staging: URL, cancellation: AutomationCancellation) throws -> URL {
        guard file.targets.contains(format) else { throw AutomationIssue("Cannot convert \(file.category) to \(format.uppercased()). The original was kept.") }
        let text = try call(["--to", format, "--jobs", "1", "--output", staging.path, "--", file.url.path], cancellation: cancellation)
        let events = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        guard let event = events.last(where: { $0["event"] as? String == "complete" }), event["success"] as? Int == 1, let results = event["results"] as? [[String: Any]], let path = results.first?["output"] as? String else { throw AutomationIssue("The conversion engine did not produce a successful result.") }
        let folder = URL(fileURLWithPath: path).standardizedFileURL
        guard RulePaths.contains(root: staging.path, path: folder.path) else { throw AutomationIssue("The conversion engine returned an output outside its staging folder.") }
        let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        // Companion resources remain in a bundle. A single regular output is
        // published directly, matching manual Convert Here behaviour.
        if children.count == 1, let file = children.first, try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true, try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true { return file }
        return folder
    }
}

struct AutomationResult {
    var message: String
    var output: URL?
}
final class AutomationPipeline {
    let engine: any AutomationEngine
    let scratch: URL
    let trash: (URL) throws -> Void
    init(engine: any AutomationEngine, scratch: URL, trash: @escaping (URL) throws -> Void = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }) {
        self.engine = engine; self.scratch = scratch; self.trash = trash
    }
    func preview(_ url: URL, rule: WatchRule, cancellation: AutomationCancellation) throws -> String {
        guard RulePaths.contains(root: rule.inputFolder, path: url.path) else { throw AutomationIssue("Choose a test file inside this rule’s inbox.") }
        let file = try engine.inspect(url, cancellation: cancellation)
        guard rule.matches(file) else { return "No match: detected \(file.format.uppercased()) / \(file.category). No files changed." }
        var name = url.deletingPathExtension().lastPathComponent, format = file.format
        for step in rule.steps {
            if step.kind == .convert {
                let targets = format == file.format ? file.targets : FormatCatalog.groups.first(where: { $0.formats.contains(format) }).map { $0.formats + ($0.id == "video" ? FormatCatalog.groups[0].formats : []) } ?? []
                guard targets.contains(step.value) else { throw AutomationIssue("This file cannot convert from \(format.uppercased()) to \(step.value.uppercased()). No files changed.") }
                format = step.value
            }
            else { name = try RuleNaming.render(step.value, name: name, format: format) }
        }
        return "Matches \(rule.name). Detected \(file.format.uppercased()). Plan: \(name).\(format) → \(rule.destination). Original: \(rule.originalPolicy.rawValue). No files changed."
    }
    func run(_ url: URL, rule: WatchRule, roots: [String], cancellation: AutomationCancellation, recognized: (RecognizedFile, FileStamp)? = nil) throws -> AutomationResult {
        try cancellation.check(); try rule.validate(roots: roots)
        let originalStamp = try FileStamp.read(url)
        guard RulePaths.contains(root: rule.inputFolder, path: url.path) else { throw AutomationIssue("The file is outside this rule's input folder.") }
        if let recognized { guard recognized.1 == originalStamp, recognized.0.url == url else { throw AutomationIssue("The original changed after recognition. It was kept.") } }
        let original = try recognized?.0 ?? engine.inspect(url, cancellation: cancellation)
        guard rule.matches(original) else { return .init(message: "No matching conditions", output: nil) }
        if rule.originalPolicy != .keep && ["geo", "document"].contains(original.category) { throw AutomationIssue("Geospatial and document originals may have companion files. Use Keep original for this category.") }
        if ["geo", "document"].contains(original.category) && !rule.steps.contains(where: { $0.kind == .convert }) { throw AutomationIssue("Add a conversion block for documents and geospatial files so companion resources are preserved.") }
        let digest = rule.originalPolicy == .keep ? nil : try RulePaths.digest(url)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let stage = scratch.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        var payload = url, current = original, name = url.deletingPathExtension().lastPathComponent, format = original.format
        for (index, step) in rule.steps.enumerated() {
            try cancellation.check()
            switch step.kind {
            case .rename: name = try RuleNaming.render(step.value, name: name, format: format)
            case .convert:
                if payload != url {
                    guard (try? FileStamp.read(payload)) != nil else { throw AutomationIssue("A companion-file bundle cannot feed another conversion block. Keep one conversion block for this file.") }
                    current = try engine.inspect(payload, cancellation: cancellation)
                }
                payload = try engine.convert(current, to: step.value, staging: stage.appendingPathComponent("step-\(index)"), cancellation: cancellation)
                format = step.value
            }
        }
        _ = try RuleNaming.render(name, name: name, format: format)
        try cancellation.check()
        guard try FileStamp.read(url) == originalStamp else { throw AutomationIssue("The original changed during conversion. No result was published; the original was kept.") }
        let destination = try RulePaths.directory(rule.destination)
        guard !roots.contains(where: { RulePaths.contains(root: $0, path: destination.path) }) else { throw AutomationIssue("The output folder moved inside a watched inbox. The original was kept.") }
        let values = try payload.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw AutomationIssue("Symbolic-link outputs cannot be published.") }
        let result = try RulePaths.publish(payload, into: destination, name: name + (values.isDirectory == true ? "-" + format : "." + format), beforeCommit: { try cancellation.check(); guard try FileStamp.read(url) == originalStamp else { throw AutomationIssue("The original changed during publication. It was kept.") } })
        do {
            try cancellation.check()
            if rule.originalPolicy != .keep {
                guard try FileStamp.read(url) == originalStamp, try RulePaths.digest(url) == digest else { throw AutomationIssue("The original changed. The output is ready; the original was kept.") }
                try finishOriginal(url, stamp: originalStamp, digest: digest!, rule: rule, roots: roots, cancellation: cancellation)
            }
            return .init(message: "Finished · original \(rule.originalPolicy == .keep ? "kept" : rule.originalPolicy == .archive ? "archived" : "sent to Trash")", output: result)
        } catch { return .init(message: "Output ready · " + error.localizedDescription, output: result) }
    }
    private func finishOriginal(_ source: URL, stamp: FileStamp, digest: Data, rule: WatchRule, roots: [String], cancellation: AutomationCancellation) throws {
        try cancellation.check()
        let fm = FileManager.default
        // Quarantine on the same filesystem gives the final identity check an
        // exclusive path. A replacement at the old source name cannot be
        // accidentally trashed or removed. Hidden staging is ignored by watches.
        let directory = source.deletingLastPathComponent().appendingPathComponent(".ultraconvert-original-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let held = directory.appendingPathComponent(source.lastPathComponent)
        defer { if (try? fm.contentsOfDirectory(atPath: directory.path).isEmpty) == true { try? fm.removeItem(at: directory) } }
        guard renamex_np(source.path, held.path, UInt32(RENAME_EXCL)) == 0 else { throw AutomationIssue("Could not move the original safely. It was kept.") }
        do {
            try cancellation.check()
            guard try FileStamp.read(held) == stamp, try RulePaths.digest(held) == digest else { throw AutomationIssue("The original changed before its final action.") }
            if rule.originalPolicy == .trash { try trash(held) }
            else {
                let archive = try RulePaths.directory(rule.archiveFolder)
                guard !roots.contains(where: { RulePaths.contains(root: $0, path: archive.path) }) else { throw AutomationIssue("The archive folder moved inside a watched inbox.") }
                _ = try RulePaths.publish(held, into: archive, name: source.lastPathComponent, beforeCommit: {
                    try cancellation.check()
                    guard try FileStamp.read(held) == stamp, try RulePaths.digest(held) == digest else { throw AutomationIssue("The original changed during archive copying.") }
                })
                try cancellation.check()
                guard try FileStamp.read(held) == stamp, try RulePaths.digest(held) == digest else { throw AutomationIssue("The original changed before archive removal.") }
                try fm.removeItem(at: held)
            }
        } catch {
            if fm.fileExists(atPath: held.path) {
                if renamex_np(held.path, source.path, UInt32(RENAME_EXCL)) != 0 {
                    throw AutomationIssue("\(error.localizedDescription) The original is preserved at \(held.path); a file already occupies its former name.")
                }
                throw AutomationIssue("\(error.localizedDescription) The original was restored to the inbox.")
            }
            throw error
        }
    }

}

import Foundation
import CryptoKit
import Darwin

struct AutomationIssue: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum MatchField: String, Codable, CaseIterable {
    case format, category, nameContains, namePrefix, nameSuffix
    var title: String {
        switch self {
        case .format: return "Detected format is"
        case .category: return "File category is"
        case .nameContains: return "Name contains"
        case .namePrefix: return "Name starts with"
        case .nameSuffix: return "Name ends with"
        }
    }
}
struct RuleCondition: Codable, Equatable {
    var field: MatchField = .format
    var value = "mp3"
    func matches(_ file: RecognizedFile) -> Bool {
        let value = value.lowercased()
        let name = file.url.lastPathComponent.lowercased()
        switch field {
        case .format:
            let aliases = ["jpeg": "jpg", "yml": "yaml"]
            return (aliases[file.format.lowercased()] ?? file.format.lowercased()) == (aliases[value] ?? value)
        case .category: return file.category.lowercased() == value
        case .nameContains: return name.contains(value)
        case .namePrefix: return name.hasPrefix(value)
        case .nameSuffix: return name.hasSuffix(value)
        }
    }
}
enum StepKind: String, Codable, CaseIterable { case convert, rename }
struct RuleStep: Codable, Equatable {
    var kind: StepKind = .convert
    var value = "mp3"
}
enum OriginalPolicy: String, Codable, CaseIterable { case keep, archive, trash }
struct WatchRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "New folder rule"
    var enabled = false
    var inputFolder = ""
    var recursive = false
    var settleSeconds: Double = 3
    var matchAll = true
    var conditions = [RuleCondition()]
    var steps = [RuleStep()]
    var destination = ""
    var originalPolicy: OriginalPolicy = .keep
    var archiveFolder = ""
    var acknowledgedRemoval = false

    func matches(_ file: RecognizedFile) -> Bool {
        matchAll ? conditions.allSatisfy { $0.matches(file) } : conditions.contains { $0.matches(file) }
    }
    func validate(roots: [String]) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100 else { throw AutomationIssue("Give the rule a name of up to 100 characters.") }
        guard inputFolder.hasPrefix("/"), destination.hasPrefix("/") else { throw AutomationIssue("Choose an input folder and an output folder.") }
        guard settleSeconds.isFinite, (2...120).contains(settleSeconds) else { throw AutomationIssue("Wait time must be between 2 and 120 seconds.") }
        guard (1...12).contains(conditions.count), (1...8).contains(steps.count) else { throw AutomationIssue("Use 1–12 conditions and 1–8 action blocks.") }
        for condition in conditions {
            guard !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, condition.value.count <= 200 else { throw AutomationIssue("Fill in every condition (up to 200 characters).") }
            if condition.field == .format && !FormatCatalog.all.contains(condition.value.lowercased()) { throw AutomationIssue("Choose a supported input format.") }
            if condition.field == .category && !FormatCatalog.groups.contains(where: { $0.id == condition.value.lowercased() }) { throw AutomationIssue("Choose a supported file category.") }
        }
        // Once a conversion establishes a format, incompatible later blocks
        // can be rejected before enabling the watcher rather than on every file.
        var previousFormat = matchAll ? conditions.first(where: { $0.field == .format })?.value.lowercased() : nil
        for step in steps {
            if step.kind == .convert {
                guard FormatCatalog.all.contains(step.value) else { throw AutomationIssue("Choose a supported conversion format.") }
                if let previousFormat, let group = FormatCatalog.groups.first(where: { $0.formats.contains(previousFormat) }) {
                    let targets = group.formats + (group.id == "video" ? FormatCatalog.groups.first(where: { $0.id == "audio" })!.formats : [])
                    guard targets.contains(step.value) else { throw AutomationIssue("A Convert block cannot go from \(previousFormat.uppercased()) to \(step.value.uppercased()). Change or remove that block, then preview a file.") }
                }
                previousFormat = step.value
            } else { _ = try RuleNaming.render(step.value, name: "Example", format: "mp3", date: Date(timeIntervalSince1970: 0)) }
        }
        let outputs = [destination] + (originalPolicy == .archive ? [archiveFolder] : [])
        for output in outputs {
            guard output.hasPrefix("/") else { throw AutomationIssue("Choose an archive folder.") }
            guard !roots.contains(where: { RulePaths.contains(root: $0, path: output) }) else { throw AutomationIssue("Output and archive folders must be outside every enabled watch folder to prevent conversion loops.") }
            _ = try RulePaths.directory(output)
        }
        _ = try RulePaths.directory(inputFolder)
        if originalPolicy != .keep && !acknowledgedRemoval { throw AutomationIssue("Confirm that this rule can move originals after success.") }
    }
}

struct RecognizedFile {
    let url: URL
    let format: String
    let category: String
    let targets: [String]
}
struct FileStamp: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    static func read(_ url: URL) throws -> FileStamp {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { throw AutomationIssue("Only ordinary files with one link can be automated. Symlinks and hard links are skipped.") }
        return from(info)
    }
    static func from(_ info: stat) -> FileStamp {
        .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: info.st_size, modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec))
    }
}
enum RulePaths {
    static func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
    static func contains(root: String, path: String) -> Bool {
        let root = canonical(root), path = canonical(path)
        if root == "/" || path == root || path.hasPrefix(root + "/") { return true }
        // On case-insensitive volumes or macOS firmlinks, different textual
        // paths can identify the same directory. Compare ancestor identities.
        var rootInfo = stat()
        guard stat(root, &rootInfo) == 0 else { return false }
        var candidate = URL(fileURLWithPath: path)
        for _ in 0..<128 {
            var info = stat()
            if stat(candidate.path, &info) == 0, info.st_dev == rootInfo.st_dev, info.st_ino == rootInfo.st_ino { return true }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }; candidate = parent
        }
        return false
    }
    static func directory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw AutomationIssue("Choose an existing ordinary folder: \(url.lastPathComponent).") }
        return url.resolvingSymlinksInPath()
    }
    static func eligible(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return !name.hasPrefix(".") && !["part", "partial", "download", "crdownload", "tmp"].contains(url.pathExtension.lowercased()) && (try? FileStamp.read(url)) != nil
    }
    static func digest(_ url: URL) throws -> Data {
        let before = try FileStamp.read(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AutomationIssue("Could not read the original safely.") }
        var opened = stat()
        guard fstat(fd, &opened) == 0, FileStamp.from(opened) == before else { close(fd); throw AutomationIssue("The file changed before it could be opened safely.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        guard try FileStamp.read(url) == before else { throw AutomationIssue("The original changed while being checked. It was kept.") }
        return Data(hash.finalize())
    }
    static func publish(_ payload: URL, into folder: URL, name: String, beforeCommit: () throws -> Void = {}) throws -> URL {
        let fm = FileManager.default
        // Complete the copy before reserving a final visible name. renamex_np
        // with RENAME_EXCL guarantees an existing destination cannot be replaced.
        let temporary = folder.appendingPathComponent(".ultraconvert-" + UUID().uuidString)
        try fm.copyItem(at: payload, to: temporary)
        defer { try? fm.removeItem(at: temporary) }
        try beforeCommit()
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        for suffix in 0..<10000 {
            let candidate = folder.appendingPathComponent(suffix == 0 ? name : base + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext))
            if renamex_np(temporary.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return candidate }
            guard errno == EEXIST else { throw AutomationIssue("Could not publish the output: " + String(cString: strerror(errno))) }
        }
        throw AutomationIssue("Too many output-name collisions. Choose another destination.")
    }
}
enum RuleNaming {
    static func render(_ template: String, name: String, format: String, date: Date = Date()) throws -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        var result = template.replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{format}", with: format).replacingOccurrences(of: "{date}", with: formatter.string(from: date))
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result != ".", result != "..", !result.hasPrefix("."), result.utf8.count <= 180, !result.contains(where: { "/\\:\0\n\r{}".contains($0) }) else { throw AutomationIssue("Use a plain filename up to 180 bytes. Tokens: {name}, {format}, {date}. No folders or unknown tokens.") }
        return result
    }
}
struct AutomationDocument: Codable {
    var schema = 1
    var rules: [WatchRule] = []
}
struct AutomationActivity: Codable {
    var date = Date()
    var rule: String
    var file: String
    var message: String
    var output: String?
}

final class AutomationStore {
    let directory: URL
    init(support: URL) throws {
        directory = support.appendingPathComponent("Automation")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AutomationIssue("Automation storage must not be a symbolic link.") }
    }
    func load() throws -> [WatchRule] {
        guard FileManager.default.fileExists(atPath: url("rules.json").path) else { return [] }
        let data = try read("rules.json", limit: 1024 * 1024)
        let document = try JSONDecoder().decode(AutomationDocument.self, from: data)
        guard document.schema == 1, document.rules.count <= 32, Set(document.rules.map(\.id)).count == document.rules.count, document.rules.allSatisfy({ $0.conditions.count <= 12 && $0.steps.count <= 8 }) else { throw AutomationIssue("The folder rules file is invalid. Restore it before enabling automation.") }
        return document.rules
    }
    func save(_ rules: [WatchRule]) throws {
        guard rules.count <= 32, Set(rules.map(\.id)).count == rules.count, rules.allSatisfy({ $0.conditions.count <= 12 && $0.steps.count <= 8 }) else { throw AutomationIssue("Use up to 32 rules with unique identifiers, 12 conditions and 8 actions per rule, including drafts.") }
        let data = try JSONEncoder().encode(AutomationDocument(rules: rules))
        guard data.count <= 1024 * 1024 else { throw AutomationIssue("The rules exceed the 1 MB storage limit. Shorten draft values before saving.") }
        try write(data, "rules.json")
    }
    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    func read(_ name: String, limit: Int) throws -> Data {
        let file = url(name)
        let stamp = try FileStamp.read(file)
        guard stamp.size <= limit else { throw AutomationIssue("The automation data file exceeds its size limit.") }
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AutomationIssue("Could not read automation storage safely.") }
        var opened = stat()
        guard fstat(fd, &opened) == 0, FileStamp.from(opened) == stamp else { close(fd); throw AutomationIssue("Automation storage changed while opening.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65536, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk); guard data.count <= limit else { throw AutomationIssue("Automation storage exceeded its size limit while reading.") }
        }
        guard try FileStamp.read(file) == stamp else { throw AutomationIssue("Automation storage changed while reading.") }
        return data
    }
    func write(_ data: Data, _ name: String) throws {
        let file = url(name)
        if FileManager.default.fileExists(atPath: file.path) { _ = try FileStamp.read(file) }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

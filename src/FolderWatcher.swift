import AppKit
import CoreServices
import Darwin

final class FolderEventStream {
    private var stream: FSEventStreamRef?
    var onChange: ((Bool) -> Void)?
    init(paths: [String], onChange: @escaping (Bool) -> Void) throws {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
            guard let info else { return }
            let rootChanged = (0..<count).contains { flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 }
            Unmanaged<FolderEventStream>.fromOpaque(info).takeUnretainedValue().onChange?(rootChanged)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.8, flags) else { throw AutomationIssue("macOS could not create the folder watcher.") }
        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else { FSEventStreamInvalidate(created); FSEventStreamRelease(created); stream = nil; throw AutomationIssue("macOS could not start watching these folders.") }
    }
    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil; onChange = nil
    }
    deinit { stop() }
}

struct WatchCandidate {
    var stamp: FileStamp
    var unchangedSince: Date
}
struct WatchScan {
    var files: [String: FileStamp] = [:]
    var issue: String?
    static func run(_ rules: [WatchRule], excluding: [URL] = []) -> WatchScan {
        var result = WatchScan()
        let fm = FileManager.default
        let excludedPaths = excluding.map { RulePaths.canonical($0.path) }
        func excluded(_ url: URL) -> Bool { excludedPaths.contains { url.path == $0 || url.path.hasPrefix($0 + "/") || RulePaths.contains(root: $0, path: url.path) } }
        let uniqueRules = Dictionary(grouping: rules, by: { RulePaths.canonical($0.inputFolder) }).values.map { grouped -> WatchRule in
            var rule = grouped[0]; rule.recursive = grouped.contains(where: \.recursive); return rule
        }
        for rule in uniqueRules {
            do {
                let root = try RulePaths.directory(rule.inputFolder)
                let urls: [URL]
                if rule.recursive {
                    var enumerationError: Error?
                    guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) else { throw AutomationIssue("Cannot read the watch folder.") }
                    var collected: [URL] = []
                    var visited = 0
                    for case let url as URL in enumerator {
                        visited += 1
                        if visited > 40000 { throw AutomationIssue("A watch folder exceeds the 40,000-entry traversal limit. Choose a smaller inbox.") }
                        if excluded(url) { enumerator.skipDescendants(); continue }
                        let properties = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                        if properties.isSymbolicLink == true || properties.isPackage == true { enumerator.skipDescendants(); continue }
                        if properties.isDirectory != true { collected.append(url) }
                        if collected.count + result.files.count > 20000 { throw AutomationIssue("A watch folder exceeds the 20,000-file limit. Choose a smaller inbox.") }
                    }
                    if let enumerationError { throw enumerationError }
                    urls = collected
                } else { urls = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) }
                for url in urls where !excluded(url) && RulePaths.eligible(url) {
                    result.files[url.path] = try FileStamp.read(url)
                    if result.files.count > 20000 { throw AutomationIssue("A watch folder exceeds the 20,000-file limit. Choose a smaller inbox.") }
                }
            } catch { result.issue = "\(rule.name): \(error.localizedDescription)"; return result }
        }
        return result
    }
}

/// All mutable scheduling state lives on the main queue. Scans and conversion
/// run on utility queues; no polling timer or child engine exists while idle.
final class FolderAutomation {
    let store: AutomationStore
    var rules: [WatchRule] = []
    var activities: [AutomationActivity] = []
    var onChange: (() -> Void)?
    var manualBusy: () -> Bool = { false }
    var engine: () throws -> any AutomationEngine
    private var stream: FolderEventStream?
    private var known: [String: FileStamp] = [:]
    private var candidates: [String: WatchCandidate] = [:]
    private var handled: [String: FileStamp] = [:]
    private var debounce: DispatchWorkItem?
    private var settle: DispatchWorkItem?
    private var scanRunning = false
    private var scanAgain = false
    private var epoch = 0
    private var lockFD: Int32 = -1
    private var cancellation: AutomationCancellation?
    private var stopping = false
    private(set) var paused = false
    private(set) var running = false
    private(set) var status = "No folders watched"
    private(set) var currentFile: String?
    var enabledRules: [WatchRule] { rules.filter(\.enabled) }
    var keepsRunning: Bool { !enabledRules.isEmpty && lockFD >= 0 }
    var pendingCount: Int { candidates.count }

    init(support: URL, engine: @escaping () throws -> any AutomationEngine) throws {
        store = try AutomationStore(support: support); self.engine = engine
        rules = try store.load()
        if FileManager.default.fileExists(atPath: store.url("state.json").path) {
            let object = try JSONSerialization.jsonObject(with: store.read("state.json", limit: 4096)) as? [String: Any]
            guard let object, object["schema"] as? Int == 1, let savedPause = object["paused"] as? Bool else { throw AutomationIssue("The saved folder-rule pause state is invalid.") }
            paused = savedPause
        }
        if let data = try? store.read("activity.json", limit: 512 * 1024), let saved = try? JSONDecoder().decode([AutomationActivity].self, from: data) { activities = Array(saved.suffix(200)) }
    }
    private func validateStorage(_ rule: WatchRule) throws {
        guard !RulePaths.contains(root: store.directory.path, path: rule.inputFolder) else { throw AutomationIssue("Choose an inbox outside UltraConvert’s automation storage.") }
    }
    func acquireLock() throws {
        guard lockFD < 0 else { return }
        let fd = open(store.url("watch.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AutomationIssue("Cannot open the automation lock.") }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw AutomationIssue("Folder automation is already open in another UltraConvert window. Use that app's menu bar control.") }
        lockFD = fd
    }
    func save(_ next: [WatchRule]) throws {
        let roots = next.filter(\.enabled).map(\.inputFolder)
        for rule in next where rule.enabled { try rule.validate(roots: roots); try validateStorage(rule) }
        try acquireLock()
        defer { if enabledRules.isEmpty && !running { releaseLock() } }
        let previous = enabledRules
        try store.save(next); rules = next
        if previous == enabledRules { if enabledRules.isEmpty && !running { releaseLock() }; onChange?() } else { configure() }
    }
    func configure() {
        stopping = false
        epoch += 1; cancellation?.cancel(); stream?.stop(); stream = nil
        debounce?.cancel(); debounce = nil; settle?.cancel(); settle = nil
        known = [:]; candidates = [:]; handled = [:]; scanAgain = false
        guard !enabledRules.isEmpty else { status = "No folders watched"; releaseLock(); onChange?(); return }
        do {
            try acquireLock()
            if paused { status = "Paused · incoming files will be ignored until resumed"; onChange?(); return }
            let roots = enabledRules.map(\.inputFolder)
            for rule in enabledRules { try rule.validate(roots: roots); try validateStorage(rule) }
            stream = try FolderEventStream(paths: Array(Set(roots)), onChange: { [weak self] rootChanged in
                if rootChanged {
                    DispatchQueue.main.async { guard let self else { return }; self.setPaused(true); self.status = "Watch folder moved or was replaced. Restore it or choose it again, then resume."; self.onChange?() }
                } else { self?.requestScan() }
            })
            status = "Starting · existing files will be ignored"
            scan(baseline: true)
        } catch { status = error.localizedDescription; paused = true; stream?.stop(); stream = nil }
        onChange?()
    }
    func setPaused(_ value: Bool) {
        do {
            try acquireLock()
            try store.write(JSONSerialization.data(withJSONObject: ["schema": 1, "paused": value]), "state.json")
            paused = value; configure()
        } catch { status = "Could not change pause state: " + error.localizedDescription; onChange?() }
    }
    func stop() {
        epoch += 1; cancellation?.cancel(); stream?.stop(); stream = nil
        debounce?.cancel(); settle?.cancel(); candidates = [:]; stopping = true; if !running { releaseLock() }
    }
    private func releaseLock() { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 } }
    deinit { stream?.stop(); cancellation?.cancel(); releaseLock() }
    func requestScan() {
        guard !paused, stream != nil else { return }
        if scanRunning { scanAgain = true; return }
        guard debounce == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.debounce = nil; self?.scan(baseline: false) }
        debounce = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    private func scan(baseline: Bool) {
        if scanRunning {
            // A configuration change waits for the old scan, then establishes a
            // fresh baseline. Old scan results never enter the new scheduler.
            scanAgain = true; return
        }
        scanRunning = true
        let version = epoch, rules = enabledRules, storage = store.directory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = WatchScan.run(rules, excluding: [storage])
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanRunning = false
                guard version == self.epoch else { if self.stream != nil { self.scan(baseline: true) }; return }
                if let issue = result.issue { self.status = issue; self.paused = true; self.stream?.stop(); self.stream = nil; self.onChange?(); return }
                if baseline { self.known = result.files }
                else {
                    let now = Date()
                    for (path, stamp) in result.files where self.known[path] != stamp && self.handled[path] != stamp {
                        if self.candidates.count >= 1000 && self.candidates[path] == nil { self.status = "Queue full (1,000 files). Extra arrivals were skipped; use Run Existing Files after the queue drains."; continue }
                        self.candidates[path] = .init(stamp: stamp, unchangedSince: now)
                    }
                    self.candidates = self.candidates.filter { result.files[$0.key] != nil }
                    self.known = result.files
                }
                self.handled = self.handled.filter { result.files[$0.key] != nil }
                self.updateStatus(); self.schedule()
                if self.scanAgain { self.scanAgain = false; self.requestScan() }
            }
        }
    }
    func runExisting() {
        guard !paused, stream != nil, !scanRunning else { return }
        // Explicit invocation processes the current baseline, without changing
        // the default of ignoring files already present at startup.
        for (path, stamp) in known.sorted(by: { $0.key < $1.key }).prefix(1000) { candidates[path] = .init(stamp: stamp, unchangedSince: Date()) }
        schedule(); updateStatus()
    }
    func manualBatchFinished() { schedule() }
    private func eligibleRules(for path: String) -> [WatchRule] {
        enabledRules.filter { rule in
            RulePaths.contains(root: rule.inputFolder, path: path) && (rule.recursive || URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path == RulePaths.canonical(rule.inputFolder))
        }
    }
    func schedule() {
        settle?.cancel(); settle = nil
        guard !paused, !running, !manualBusy(), stream != nil, !candidates.isEmpty else { return }
        let now = Date()
        var ready: String?, wait: Double = 120
        for path in candidates.keys.sorted() {
            guard var candidate = candidates[path] else { continue }
            guard let stamp = try? FileStamp.read(URL(fileURLWithPath: path)) else { candidates.removeValue(forKey: path); continue }
            if candidate.stamp != stamp { candidate.stamp = stamp; candidate.unchangedSince = now; candidates[path] = candidate; known[path] = stamp }
            let delay = eligibleRules(for: path).map(\.settleSeconds).max() ?? 3
            let remaining = delay - now.timeIntervalSince(candidate.unchangedSince)
            if remaining <= 0 { ready = path; break }
            wait = min(wait, remaining)
        }
        if let ready { start(ready); return }
        guard !candidates.isEmpty else { updateStatus(); return }
        let work = DispatchWorkItem { [weak self] in self?.settle = nil; self?.schedule() }
        settle = work; DispatchQueue.main.asyncAfter(deadline: .now() + max(0.25, wait), execute: work)
    }
    private func start(_ path: String) {
        guard let candidate = candidates.removeValue(forKey: path) else { return }
        handled[path] = candidate.stamp
        running = true; currentFile = URL(fileURLWithPath: path).lastPathComponent
        let token = AutomationCancellation(); cancellation = token
        let choices = eligibleRules(for: path), roots = enabledRules.map(\.inputFolder), scratch = store.url("Staging"), createEngine = engine
        updateStatus()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var ruleName = "Folder rules"
            let activity: AutomationActivity
            do {
                let engine = try createEngine(), url = URL(fileURLWithPath: path), stamp = try FileStamp.read(url), file = try engine.inspect(url, cancellation: token)
                guard let rule = choices.first(where: { $0.matches(file) }) else { throw AutomationIssue("No matching rule · detected \(file.format.uppercased())") }
                ruleName = rule.name
                let pipeline = AutomationPipeline(engine: engine, scratch: scratch)
                let result = try pipeline.run(file.url, rule: rule, roots: roots, cancellation: token, recognized: (file, stamp))
                activity = .init(rule: ruleName, file: file.url.lastPathComponent, message: result.message, output: result.output?.path)
            } catch { activity = .init(rule: ruleName, file: URL(fileURLWithPath: path).lastPathComponent, message: String(error.localizedDescription.prefix(2000))) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false; self.currentFile = nil; self.cancellation = nil
                if self.stopping || self.enabledRules.isEmpty { self.releaseLock() }
                self.activities.append(activity); self.activities = Array(self.activities.suffix(200))
                while let data = try? JSONEncoder().encode(self.activities) {
                    if data.count <= 512 * 1024 { try? self.store.write(data, "activity.json"); break }
                    self.activities.removeFirst()
                }
                self.updateStatus(); self.schedule()
            }
        }
    }
    func updateStatus() {
        if paused { status = "Paused · incoming files will be ignored until resumed" }
        else if running { status = "Processing \(currentFile ?? "file") · \(pendingCount) waiting" }
        else if !enabledRules.isEmpty && stream != nil { status = "Watching \(Set(enabledRules.map(\.inputFolder)).count) folder(s) · \(pendingCount) waiting" }
        onChange?()
    }
}

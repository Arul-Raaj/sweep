import Foundation
import os

public struct Item: Sendable, Hashable, Identifiable {
    /// What the user sees and decides about (a folder, or an app's data folder).
    public let url: URL
    public let bytes: Int64
    /// When it was last modified, used, added or trashed (whatever the rule judges age by).
    public let lastUsed: Date?
    /// What actually gets removed. Empty means `url` itself.
    public let parts: [URL]
    /// Why it can't be cleaned right now (e.g. its app is open). Blocked items are never removed.
    public let blocked: String?
    public var id: URL { url }
    public var targets: [URL] { parts.isEmpty ? [url] : parts }

    public init(url: URL, bytes: Int64, lastUsed: Date? = nil, parts: [URL] = [], blocked: String? = nil) {
        self.url = url
        self.bytes = bytes
        self.lastUsed = lastUsed
        self.parts = parts
        self.blocked = blocked
    }
}

public struct Finding: Sendable, Identifiable {
    public let rule: Rule
    public let items: [Item]
    /// Set when the rule could not run, e.g. missing Full Disk Access.
    public let note: String?
    public var id: String { rule.id }
    /// Items that can be removed right now.
    public var cleanable: [Item] { items.filter { $0.blocked == nil } }
    public var bytes: Int64 { cleanable.reduce(0) { $0 + $1.bytes } }
    /// Nothing to show: no items and no reason it couldn't look.
    public var isEmpty: Bool { items.isEmpty && note == nil }

    public init(rule: Rule, items: [Item], note: String? = nil) {
        self.rule = rule
        self.items = items
        self.note = note
    }
}

public struct CleanReport: Sendable {
    /// Bytes deleted outright.
    public var freed: Int64 = 0
    /// Bytes moved to the Trash (freed only once the Trash is emptied).
    public var trashed: Int64 = 0
    public var removed = 0
    /// Items skipped because they were in use (used again since the scan, or their app is open).
    public var kept = 0
    public var failures: [(path: String, reason: String)] = []
    /// Items cleaned by their owner's command. The cache folder stays, so this is how to tell they're done.
    public var ran: [URL] = []

    public init() {}
}

public enum Sweeper {
    /// Read-only. Finds what each rule would remove and how much space it takes.
    /// Rules are independent and the work is mostly waiting on the disk, so they run in parallel.
    public static func scan(_ rules: [Rule], home: URL, now: Date = .now) -> [Finding] {
        let openFiles = needsOpenFiles(rules) ? OpenFiles.snapshot() : nil
        let projects = ProjectIndex()
        let results = OSAllocatedUnfairLock(initialState: [Finding?](repeating: nil, count: rules.count))
        DispatchQueue.concurrentPerform(iterations: rules.count) { i in
            let finding = scan(rules[i], home: home, now: now, openFiles: openFiles, projects: projects)
            results.withLock { $0[i] = finding }
        }
        return results.withLock { $0.compactMap { $0 } }
    }

    /// nil when the rule doesn't apply to this Mac (its tool isn't installed).
    private static func scan(_ rule: Rule, home: URL, now: Date, openFiles: OpenFiles?, projects: ProjectIndex) -> Finding? {
        switch rule.kind {
        case let .contents(dirs, days, age, filter):
            let block = rule.guardedBy.flatMap { appBlock(owner: $0, openFiles: openFiles) }
            return scanContents(rule, dirs: dirs, cutoff: cutoff(days, now), age: age, filter: filter, block: block)
        case let .staleProjects(roots, days, folders):
            return scanStaleProjects(rule, roots: roots, folders: folders, home: home,
                                     cutoff: cutoff(days, now) ?? now, index: projects)
        case let .webCaches(roots):
            return scanWebCaches(rule, roots: roots, now: now, openFiles: openFiles)
        case let .ownerCommand(cmd):
            return scanOwnerCommand(rule, cmd, home: home, now: now, openFiles: openFiles)
        }
    }

    /// Removes the given items: deletes them, or moves Review-level items to the Trash.
    /// Each item is first re-checked by `Safety` (is it where the rule allows?) and
    /// against its rule again (is it still unused?).
    public static func clean(_ findings: [Finding], home: URL, now: Date = .now) -> CleanReport {
        let openFiles = needsOpenFiles(findings.map(\.rule)) ? OpenFiles.snapshot() : nil
        var report = CleanReport()
        for finding in findings {
            for item in finding.items {
                clean(item, rule: finding.rule, home: home, now: now, openFiles: openFiles, into: &report)
            }
        }
        return report
    }

    private static func needsOpenFiles(_ rules: [Rule]) -> Bool {
        rules.contains { rule in
            if rule.guardedBy != nil { return true }
            switch rule.kind {
            case .webCaches, .ownerCommand: return true
            default: return false
            }
        }
    }

    private static func clean(_ item: Item, rule: Rule, home: URL, now: Date, openFiles: OpenFiles?,
                              into report: inout CleanReport) {
        guard item.blocked == nil else { report.kept += 1; return }
        // Sweep never deletes these files itself; the tool that owns them cleans them.
        if case let .ownerCommand(cmd) = rule.kind {
            cleanOwnerCommand(item, rule: rule, cmd, home: home, now: now, openFiles: openFiles, into: &report)
            return
        }
        if let unsafe = item.targets.first(where: { !Safety.allows($0, rule: rule, home: home) }) {
            report.failures.append((unsafe.path(percentEncoded: false), "blocked by safety check"))
            return
        }
        guard stillMatches(item, rule: rule, home: home, now: now, openFiles: openFiles) else {
            report.kept += 1
            return
        }

        let fm = FileManager.default
        var leftover: [URL] = []
        for target in item.targets {
            do {
                if rule.movesToTrash {
                    try fm.trashItem(at: target, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: target)
                }
            } catch {
                // Already gone is fine; anything else is reported, never fatal.
                let path = target.path(percentEncoded: false)
                if fm.fileExists(atPath: path) || isSymlink(target) {
                    report.failures.append((path, error.localizedDescription))
                    leftover.append(target)
                }
            }
        }
        // Count what actually went, even if some parts couldn't be removed.
        let gone = max(0, item.bytes - leftover.reduce(0) { $0 + measure($1).bytes })
        if leftover.isEmpty { report.removed += 1 }
        if rule.movesToTrash { report.trashed += gone } else { report.freed += gone }
    }

    /// Anything written to this recently is treated as in use, whatever the rule.
    static let settleTime: TimeInterval = 120

    /// True if the item would still be selected, and not blocked, by its rule right now.
    static func stillMatches(_ item: Item, rule: Rule, home: URL, now: Date, openFiles: OpenFiles? = nil) -> Bool {
        if let owner = rule.guardedBy, appBlock(owner: owner, openFiles: openFiles) != nil { return false }
        switch rule.kind {
        case let .contents(_, days, age, _):
            let usage = measure(item.url)
            // Being written right now (a build, a backup in progress), or changed since the scan.
            if now.timeIntervalSince(usage.newest) < settleTime { return false }
            if age == .modified, let scanned = item.lastUsed, usage.newest > scanned.addingTimeInterval(1) { return false }
            guard let cutoff = cutoff(days, now) else { return true }
            return date(of: item.url, usage: usage, age: age) < cutoff
        case let .staleProjects(_, days, _):
            guard let cutoff = cutoff(days, now) else { return true }
            return lastActivity(of: item.url.deletingLastPathComponent(), home: home) < cutoff
        case .webCaches:
            let newest = item.targets.map { measure($0).newest }.max() ?? .distantPast
            return webCacheBlock(owner: item.url, newest: newest, now: now, openFiles: openFiles) == nil
        case let .ownerCommand(cmd):
            return ownerCommandReady(item, cmd, now: now, openFiles: openFiles) != nil
        }
    }

    static func cutoff(_ days: Int, _ now: Date) -> Date? {
        days > 0 ? now.addingTimeInterval(-Double(days) * 86_400) : nil
    }

    /// Why an app's data can't be touched right now (it runs, or has files open in
    /// `owner`), or nil if it can.
    static func appBlock(owner: URL, openFiles: OpenFiles?) -> String? {
        if let app = RunningApps.matching(folder: owner.lastPathComponent) {
            return "\(app) is open. Quit it to clean this."
        }
        if openFiles?.anyOpen(inside: owner) == true {
            return "An open app is using this. Quit it to clean this."
        }
        return nil
    }

    // MARK: - Contents rule

    private static func scanContents(_ rule: Rule, dirs: [URL], cutoff: Date?, age: Rule.Age,
                                     filter: Rule.Filter, block: String?) -> Finding {
        let fm = FileManager.default
        var items: [Item] = []
        var unreadable = false

        for dir in dirs where fm.fileExists(atPath: dir.path) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.addedToDirectoryDateKey], options: []) else {
                unreadable = true
                continue
            }
            for entry in entries where filter.admits(entry) {
                let usage = measure(entry)
                guard usage.bytes > 0 else { continue }   // empty folders free nothing
                let date = date(of: entry, usage: usage, age: age)
                if let cutoff, date >= cutoff { continue }
                items.append(Item(url: entry, bytes: usage.bytes, lastUsed: date, blocked: block))
            }
        }
        let note = unreadable && items.isEmpty
            ? "Sweep can't read this folder. Allow it in System Settings → Privacy & Security → Full Disk Access."
            : nil
        return Finding(rule: rule, items: items.sorted { $0.bytes > $1.bytes }, note: note)
    }

    private static func date(of url: URL, usage: Usage, age: Rule.Age) -> Date {
        switch age {
        case .modified: usage.newest
        case .addedToFolder:
            // Unknown means "just now": never let a missing date make something look old.
            (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .now
        }
    }

    // MARK: - File system helpers

    struct Usage {
        var bytes: Int64 = 0
        var newest = Date.distantPast
    }

    /// Allocated size and newest modification date of a file or folder tree. Never follows symlinks.
    static func measure(_ url: URL) -> Usage {
        // URLs cache what they read; a second measure (after cleaning) must look again.
        var url = url
        url.removeAllCachedResourceValues()
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        var usage = Usage()
        func add(_ v: URLResourceValues) {
            usage.bytes += Int64(v.totalFileAllocatedSize ?? 0)
            if let d = v.contentModificationDate, d > usage.newest { usage.newest = d }
        }
        guard let root = try? url.resourceValues(forKeys: Set(keys)) else { return usage }
        add(root)
        guard root.isDirectory == true, root.isSymbolicLink != true,
              let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return usage }
        while let child = walker.nextObject() as? URL {
            if let v = try? child.resourceValues(forKeys: Set(keys)) { add(v) }
        }
        return usage
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

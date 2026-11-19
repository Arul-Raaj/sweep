import SwiftUI
import SweepCore

/// All window state. Scanning and cleaning run off the main thread.
@MainActor @Observable
final class Model {
    enum Phase { case scanning, ready, cleaning }
    enum Route: Hashable { case overview, rule(String) }

    private(set) var phase = Phase.scanning
    private(set) var findings: [Finding] = []
    private(set) var disk = DiskSpace.current()
    /// A short result or error shown in the clean bar for a few seconds.
    struct Banner: Equatable {
        let text: String
        let success: Bool
    }
    private(set) var banner: Banner?
    private(set) var weekly = Schedule.isOn
    var selected: Set<URL> = []
    /// Optional only because List selection can be cleared; nothing selected means the overview.
    var route: Route? = .overview {
        didSet { if route == nil { route = .overview } }
    }
    var confirming = false

    private let home = Paths.home
    /// Cleanable items from the previous scan, so a rescan keeps the user's choices.
    private var seen: Set<URL> = []

    // MARK: Derived

    func findings(in level: Rule.Level) -> [Finding] {
        findings.filter { $0.rule.level == level && !$0.isEmpty }
    }

    var focused: Finding? {
        guard case let .rule(id) = route else { return nil }
        return findings.first { $0.id == id }
    }

    var selectedItems: [Item] { findings.flatMap { $0.cleanable.filter { selected.contains($0.url) } } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var cleanableBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

    /// The bottom bar shows while something is selected, a clean runs, or a result is showing.
    var showsCleanBar: Bool { !selectedItems.isEmpty || phase == .cleaning || banner != nil }

    /// True if anything selected will go to the Trash rather than be deleted.
    var selectionIncludesTrash: Bool {
        findings.contains { $0.rule.movesToTrash && $0.cleanable.contains { selected.contains($0.url) } }
    }

    // MARK: Selection

    private func cleanable(in level: Rule.Level) -> [Item] { findings(in: level).flatMap(\.cleanable) }

    func bytes(in level: Rule.Level) -> Int64 { cleanable(in: level).reduce(0) { $0 + $1.bytes } }

    func selectedBytes(in level: Rule.Level) -> Int64 {
        cleanable(in: level).filter { selected.contains($0.url) }.reduce(0) { $0 + $1.bytes }
    }

    func isOn(_ level: Rule.Level) -> Bool { allSelected(cleanable(in: level)) }
    func set(_ level: Rule.Level, on: Bool) { set(cleanable(in: level), on: on) }

    func isOn(_ finding: Finding) -> Bool { allSelected(finding.cleanable) }
    func set(_ finding: Finding, on: Bool) { set(finding.cleanable, on: on) }

    func toggle(_ item: Item) {
        guard item.blocked == nil else { return }
        if selected.remove(item.url) == nil { selected.insert(item.url) }
        Feedback.tick()
    }

    private func allSelected(_ items: [Item]) -> Bool {
        !items.isEmpty && items.allSatisfy { selected.contains($0.url) }
    }

    private func set(_ items: [Item], on: Bool) {
        let urls = items.map(\.url)
        if on { selected.formUnion(urls) } else { selected.subtract(urls) }
        Feedback.tick()
    }

    // MARK: Actions

    func scan() async {
        guard phase != .cleaning else { return }
        phase = .scanning
        let home = home
        let result = await Task.detached(priority: .userInitiated) {
            Sweeper.scan(Paths.rules(), home: home)
        }.value

        // Keep earlier choices; new items start selected only if they're Recommended.
        let cleanable = result.flatMap { finding in finding.cleanable.map { (level: finding.rule.level, url: $0.url) } }
        let fresh = cleanable.filter { !seen.contains($0.url) && $0.level == .recommended }.map(\.url)
        selected = selected.intersection(cleanable.map(\.url)).union(fresh)
        seen = Set(cleanable.map(\.url))

        ItemLabel.reset()
        findings = result
        if route != .overview, focused?.isEmpty != false { route = .overview }
        disk = DiskSpace.current()
        phase = .ready
    }

    func clean() async {
        let chosen = findings.compactMap { finding -> Finding? in
            let items = finding.cleanable.filter { selected.contains($0.url) }
            return items.isEmpty ? nil : Finding(rule: finding.rule, items: items)
        }
        guard phase == .ready, !chosen.isEmpty else { return }
        phase = .cleaning
        let home = home
        let report = await Task.detached(priority: .userInitiated) {
            Store.exclusively { () -> CleanReport in
                let report = Sweeper.clean(chosen, home: home)
                Store.record(report)
                return report
            }
        }.value

        guard let report else {
            phase = .ready
            show("Another clean is running. Try again in a moment.", success: false)
            return
        }

        if report.removed > 0 { Feedback.emptiedTrash() }
        // An item is gone when everything it removes is gone (an app's caches, not its folder),
        // or when its tool's own cleanup ran (the cache folder itself stays).
        let fm = FileManager.default
        let gone = Set(chosen.flatMap(\.items)
            .filter { $0.targets.allSatisfy { !fm.fileExists(atPath: $0.path) } }
            .map(\.url)).union(report.ran)
        withAnimation(.smooth(duration: 0.4)) {
            findings = findings.map { Finding(rule: $0.rule, items: $0.items.filter { !gone.contains($0.url) }, note: $0.note) }
            selected.subtract(gone)
            if focused?.isEmpty == true { route = .overview }
            disk = DiskSpace.current()
        }
        phase = .ready
        show(summary(report), success: report.failures.isEmpty)

        // APFS releases space a moment after deletion; refresh once more.
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.smooth) { disk = DiskSpace.current() }
    }

    func setWeekly(_ on: Bool) {
        weekly = on   // reflect the switch at once; launchctl runs off the main thread
        let executable = CLI.executable
        Task {
            let failure = await Task.detached {
                do {
                    if on { try Schedule.turnOn(executable: executable) } else { try Schedule.turnOff() }
                    return nil as String?
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure { show(failure, success: false) }
            weekly = Schedule.isOn
        }
    }

    func refreshWeekly() { weekly = Schedule.isOn }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Banner

    private func summary(_ report: CleanReport) -> String {
        var parts: [String] = []
        if report.freed > 0 || report.trashed == 0 { parts.append("Freed \(formatBytes(report.freed))") }
        if report.trashed > 0 { parts.append("Moved \(formatBytes(report.trashed)) to the Trash") }
        if report.kept > 0 { parts.append("\(report.kept) kept because they're in use") }
        if !report.failures.isEmpty { parts.append("\(report.failures.count) couldn't be removed") }
        return parts.joined(separator: " · ")
    }

    private func show(_ text: String, success: Bool) {
        let message = Banner(text: text, success: success)
        withAnimation(.snappy) { banner = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if banner == message { withAnimation(.smooth) { banner = nil } }
        }
    }
}

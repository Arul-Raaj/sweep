import Foundation

// MARK: - Disk

public struct DiskSpace: Sendable {
    public let free: Int64
    public let total: Int64

    /// Free space as Finder reports it (includes purgeable space).
    public static func current() -> DiskSpace? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity
        else { return nil }
        return DiskSpace(free: free, total: Int64(total))
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - State, log and lock

public enum Store {
    public static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Sweep", directoryHint: .isDirectory)
    public static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Sweep.log")
    private static let lockFile = supportDir.appending(path: "sweep.lock")

    public static func record(_ report: CleanReport) {
        var line = "Cleaned \(report.removed) items, freed \(formatBytes(report.freed))"
        if report.trashed > 0 { line += ", moved \(formatBytes(report.trashed)) to the Trash" }
        if report.kept > 0 { line += ", kept \(report.kept) in use" }
        if !report.failures.isEmpty { line += ", \(report.failures.count) skipped" }
        log(line)
        for failure in report.failures.prefix(50) { log("  skipped \(failure.path): \(failure.reason)") }
    }

    public static func log(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFile, options: .atomic)
        }
    }

    /// Runs `body` while holding an exclusive lock so the menu bar app and the
    /// scheduled job never clean at the same time. Returns nil if another run holds it.
    public static func exclusively<T>(_ body: () throws -> T) rethrows -> T? {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let fd = open(lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

// MARK: - Weekly schedule (launchd)

public enum Schedule {
    public static let label = "local.sweep.weekly"
    static let plist = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/LaunchAgents/\(label).plist")

    public static var isOn: Bool { FileManager.default.fileExists(atPath: plist.path) }

    /// Runs `<executable> clean` (Recommended items only) every Monday at 11:00.
    /// launchd runs a missed job on wake.
    public static func turnOn(executable: URL) throws {
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path, "clean"],
            "StartCalendarInterval": ["Weekday": 1, "Hour": 11, "Minute": 0],
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
            "StandardErrorPath": Store.logFile.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plist, options: .atomic)
        launchctl("bootout", "gui/\(getuid())/\(label)")
        guard launchctl("bootstrap", "gui/\(getuid())", plist.path) else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "launchctl could not load the weekly job"])
        }
    }

    public static func turnOff() throws {
        launchctl("bootout", "gui/\(getuid())/\(label)")
        if isOn { try FileManager.default.removeItem(at: plist) }
    }

    /// Re-points the job if the app was moved since it was scheduled.
    public static func repair(executable: URL) {
        guard isOn,
              let data = try? Data(contentsOf: plist),
              let job = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = job["ProgramArguments"] as? [String],
              args.first != executable.path
        else { return }
        try? turnOn(executable: executable)
    }

    @discardableResult
    private static func launchctl(_ args: String...) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

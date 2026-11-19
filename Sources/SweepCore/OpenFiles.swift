import Foundation

/// Files this user's processes have open right now, from `lsof`.
///
/// Chromium apps keep files open in their profile folder (LevelDB locks, cookie
/// databases) for as long as they run, so this catches an open app whatever its
/// data folder is called (Chrome lives under "Google", Edge under "Microsoft Edge").
struct OpenFiles: Sendable {
    private let paths: [String]

    /// nil when lsof couldn't run; callers then rely on their other signals.
    static func snapshot() -> OpenFiles? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-w", "-Fn", "-u", String(getuid())]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Read before waiting, or a full pipe would block lsof forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // lsof exits 1 when some files can't be listed; the output is still valid.
        let paths = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in line.hasPrefix("n/") ? normalized(String(line.dropFirst())) : nil }
        return paths.isEmpty ? nil : OpenFiles(paths: paths)
    }

    /// lsof reports real paths ("/private/var/…"), but Foundation's `resolvingSymlinksInPath`
    /// strips "/private". Match Foundation so the two compare.
    private static func normalized(_ path: String) -> String {
        for top in ["/private/var/", "/private/tmp/", "/private/etc/"] where path.hasPrefix(top) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// True if any process has a file open anywhere inside `folder`.
    func anyOpen(inside folder: URL) -> Bool {
        let path = folder.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return paths.contains { $0.hasPrefix(prefix) }
    }
}

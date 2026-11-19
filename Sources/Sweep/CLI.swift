import Foundation
import SweepCore

/// `sweep` on the command line. Also what the weekly launchd job runs.
enum CLI {
    static let usage = """
    usage: sweep [command]

      (none)              open the app
      scan [-v]           show what can be removed, by level (removes nothing)
      clean [--level N]   remove levels 1…N (default 1, Recommended only)
                            1 Recommended   rebuilds on its own
                            2 Rebuildable   comes back with a download or install
                            3 Review        your files, moved to the Trash
      schedule on|off     clean Recommended items every Monday at 11:00
      version             show the version
    """

    static func run(_ args: [String]) -> Int32 {
        let home = Paths.home
        let rules = Paths.rules()

        switch args.first {
        case "scan":
            printSummary(Sweeper.scan(rules, home: home), verbose: args.contains("-v"))
            return 0

        case "clean":
            guard let level = level(in: args) else {
                print("--level must be 1, 2 or 3.")
                return 64
            }
            let chosen = rules.filter { $0.level <= level }
            let result = Store.exclusively { () -> CleanReport in
                let findings = Sweeper.scan(chosen, home: home)
                printSummary(findings, verbose: args.contains("-v"))
                let report = Sweeper.clean(findings, home: home)
                Store.record(report)
                return report
            }
            guard let report = result else {
                print("Another clean is already running.")
                return 1
            }
            var line = "\nFreed \(formatBytes(report.freed))."
            if report.trashed > 0 { line += " Moved \(formatBytes(report.trashed)) to the Trash." }
            if let disk = DiskSpace.current() { line += " \(formatBytes(disk.free)) free now." }
            if !report.failures.isEmpty { line += " \(report.failures.count) skipped (see \(Store.logFile.path))." }
            print(line)
            return 0

        case "schedule":
            do {
                switch args.dropFirst().first {
                case "on":
                    try Schedule.turnOn(executable: executable)
                    print("Weekly clean is on: Recommended items, Mondays at 11:00.")
                case "off":
                    try Schedule.turnOff()
                    print("Weekly clean is off.")
                default:
                    print("Weekly clean is \(Schedule.isOn ? "on" : "off").")
                }
                return 0
            } catch {
                print("Error: \(error.localizedDescription)")
                return 1
            }

        case "help", "-h", "--help":
            print(usage)
            return 0

        case "version", "--version":
            print("Sweep \(version)")
            return 0

        default:
            print(usage)
            return 64
        }
    }

    /// Read from the app bundle the real executable lives in, so it's right even when
    /// `sweep` is run through a symlink (where Bundle.main can't find the Info.plist).
    static var version: String {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = Bundle(url: app) ?? .main
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var executable: URL {
        (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    /// `--level N` → that level; no flag → Recommended; anything else → nil.
    private static func level(in args: [String]) -> Rule.Level? {
        guard let flag = args.firstIndex(of: "--level") else { return .recommended }
        guard flag + 1 < args.count, let n = Int(args[flag + 1]) else { return nil }
        return Rule.Level(rawValue: n)
    }

    private static func printSummary(_ findings: [Finding], verbose: Bool) {
        if let disk = DiskSpace.current() {
            print("\(formatBytes(disk.free)) free of \(formatBytes(disk.total))")
        }
        for level in Rule.Level.allCases {
            let group = findings.filter { $0.rule.level == level }
            guard !group.isEmpty else { continue }
            let total = group.reduce(0) { $0 + $1.bytes }
            print("\n\(level.rawValue) \(level.title.uppercased())  \(total > 0 ? formatBytes(total) : "–")")
            for finding in group {
                let detail = finding.note ?? (finding.bytes > 0 ? formatBytes(finding.bytes) : "–")
                let inUse = finding.items.count - finding.cleanable.count
                print("  \(pad(finding.rule.name, 30))\(detail)" + (inUse > 0 ? "  (\(inUse) in use)" : ""))
                guard verbose else { continue }
                for item in finding.items {
                    print("      \(pad(formatBytes(item.bytes), 10))\(item.url.path(percentEncoded: false))"
                          + (item.blocked.map { "  – \($0)" } ?? ""))
                }
            }
        }
        print("\nCan be freed: \(formatBytes(findings.reduce(0) { $0 + $1.bytes }))")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.padding(toLength: max(width, text.count + 1), withPad: " ", startingAt: 0)
    }
}

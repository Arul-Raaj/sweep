import Foundation

/// Where Sweep looks. Setting `SWEEP_HOME` points it at another folder instead of your
/// home (for demos, screenshots and testing); the temporary folder then lives inside
/// that folder too, so nothing outside it can be touched.
public enum Paths {
    public static let demoHome: URL? = {
        guard let custom = ProcessInfo.processInfo.environment["SWEEP_HOME"], !custom.isEmpty else { return nil }
        return URL(filePath: custom, directoryHint: .isDirectory).standardizedFileURL
    }()

    public static var isDemo: Bool { demoHome != nil }

    public static var home: URL { demoHome ?? FileManager.default.homeDirectoryForCurrentUser }

    public static var temp: URL {
        demoHome?.appending(path: "tmp", directoryHint: .isDirectory) ?? FileManager.default.temporaryDirectory
    }

    public static func rules() -> [Rule] { Rule.defaults(home: home, temp: temp) }
}

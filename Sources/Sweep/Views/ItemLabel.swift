import AppKit
import SweepCore

/// Human names and icons for items: app folders show the app's own name and icon.
@MainActor
struct ItemLabel {
    let title: String
    let subtitle: String
    let icon: NSImage
    let age: String

    private static var cache: [URL: ItemLabel] = [:]
    private static let home = Paths.home.path(percentEncoded: false)
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Called on every scan, so ages and folder lists stay current.
    static func reset() { cache.removeAll() }

    static func make(_ item: Item, rule: Rule) -> ItemLabel {
        if let hit = cache[item.url] { return hit }

        var title = item.url.lastPathComponent
        var iconPath = item.url.path(percentEncoded: false)
        var subtitle = tilde(iconPath)

        if !item.parts.isEmpty {
            // Grouped app caches: the title names the app, so list which folders get removed.
            let names = Set(item.parts.map(\.lastPathComponent)).sorted()
            subtitle = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3) more" : "")
        }
        if case let .ownerCommand(cmd) = rule.kind {
            // Cleaned by a command, not deleted: say which command runs, and where.
            title = rule.name
            subtitle = "Runs \(cmd.display) · \(tilde(iconPath))"
        } else if case .staleProjects = rule.kind {
            let project = item.url.deletingLastPathComponent()
            title = projectTitle(project)
            iconPath = project.path(percentEncoded: false)
        } else if let owner = rule.guardedBy, let app = application(forFolderNamed: owner.lastPathComponent) {
            // Data that belongs to one app (e.g. Claude's sandbox): show that app.
            title = app.deletingPathExtension().lastPathComponent
            iconPath = app.path(percentEncoded: false)
        } else if let app = application(forFolderNamed: item.url.lastPathComponent) {
            title = app.deletingPathExtension().lastPathComponent
            iconPath = app.path(percentEncoded: false)
        }

        let label = ItemLabel(title: title, subtitle: subtitle,
                              icon: NSWorkspace.shared.icon(forFile: iconPath),
                              age: age(item.lastUsed, verb: rule.dateVerb))
        cache[item.url] = label
        return label
    }

    /// "Claude" → Claude.app by name; "com.figma.Desktop.ShipIt" → Figma.app by trying
    /// shorter bundle-id prefixes.
    private static func application(forFolderNamed name: String) -> URL? {
        let fm = FileManager.default
        for dir in ["/Applications", "\(home)/Applications"] {
            let app = URL(filePath: dir).appending(path: "\(name).app")
            if fm.fileExists(atPath: app.path) { return app }
        }
        var parts = name.split(separator: ".")
        while parts.count >= 2 {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                return app
            }
            parts.removeLast()
        }
        return nil
    }

    /// "my-app / frontend" for a package inside a repo, so same-named folders stay distinguishable.
    private static func projectTitle(_ project: URL) -> String {
        let fm = FileManager.default
        let name = project.lastPathComponent
        if fm.fileExists(atPath: project.appending(path: ".git").path) { return name }
        var dir = project.deletingLastPathComponent()
        for _ in 0..<5 where dir.path(percentEncoded: false).hasPrefix(home) {
            if fm.fileExists(atPath: dir.appending(path: ".git").path) {
                return "\(dir.lastPathComponent) / \(name)"
            }
            dir = dir.deletingLastPathComponent()
        }
        return name
    }

    private static func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~/" + path.dropFirst(home.count).trimmingPrefix("/") : path
    }

    private static func age(_ date: Date?, verb: String) -> String {
        guard let date, date > .distantPast else { return "" }
        return "\(verb) \(relative.localizedString(for: date, relativeTo: .now))"
    }
}

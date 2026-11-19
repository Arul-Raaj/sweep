import Foundation

/// Generated folders (`node_modules`, `.next`, …) inside JavaScript projects nobody is using.
extension Sweeper {
    private static let maxSearchDepth = 6
    private static let maxActivityEntries = 20_000
    /// Never searched for projects, never counted as activity.
    private static let generatedFolders: Set<String> = [
        "node_modules", ".git", "dist", "build", "out", "coverage",
        ".next", ".turbo", ".nuxt", ".svelte-kit", ".parcel-cache", ".angular",
    ]

    static func scanStaleProjects(_ rule: Rule, roots: [URL], folders: Set<String>, home: URL,
                                  cutoff: Date, index: ProjectIndex) -> Finding {
        let items = index.projects(under: roots)
            .flatMap { project in
                folders.sorted()
                    .map { project.appending(path: $0, directoryHint: .isDirectory) }
                    .filter(Safety.isRealDirectory)
                    .map { (project: project, folder: $0) }
            }
            .compactMap { project, folder -> Item? in
                let active = index.lastActivity(of: project, home: home)
                guard active < cutoff else { return nil }
                let bytes = measure(folder).bytes
                return bytes > 0 ? Item(url: folder, bytes: bytes, lastUsed: active) : nil
            }
            .sorted { $0.bytes > $1.bytes }
        return Finding(rule: rule, items: items)
    }

    /// One scan's shared view of the project folders, so rules that look at the same
    /// projects (node_modules, build output) walk the disk and judge activity only once.
    /// Rules scan in parallel, so all state is behind a lock.
    final class ProjectIndex: @unchecked Sendable {
        private let lock = NSLock()
        private var projects: [[URL]: [URL]] = [:]
        private var activity: [URL: Date] = [:]

        func projects(under roots: [URL]) -> [URL] {
            // Held for the whole walk: a second rule waits for the first walk rather than repeating it.
            lock.withLock {
                if let known = projects[roots] { return known }
                var found: [URL] = []
                for root in roots where Safety.isRealDirectory(root) {
                    findProjects(in: root, depth: 0, into: &found)
                }
                projects[roots] = found
                return found
            }
        }

        func lastActivity(of project: URL, home: URL) -> Date {
            if let known = lock.withLock({ activity[project] }) { return known }
            let date = Sweeper.lastActivity(of: project, home: home)
            lock.withLock { activity[project] = date }
            return date
        }
    }

    /// Collects folders that contain a `package.json`. Never descends into generated
    /// folders, hidden folders, packages or symlinks.
    private static func findProjects(in dir: URL, depth: Int, into found: inout [URL]) {
        guard depth <= maxSearchDepth else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appending(path: "package.json").path) { found.append(dir) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        for child in children {
            guard let v = try? child.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true,
                  child.lastPathComponent != "Library",
                  !generatedFolders.contains(child.lastPathComponent) else { continue }
            findProjects(in: child, depth: depth + 1, into: &found)
        }
    }

    /// Best guess at when a project was last used: the newest of its own files (shallow),
    /// its git index/HEAD (touched by editors and git), install markers, and the top of its
    /// build folders (a dev server writes there). Errs towards "active".
    static func lastActivity(of project: URL, home: URL) -> Date {
        var newest = Date.distantPast
        func bump(_ url: URL) {
            if let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > newest {
                newest = d
            }
        }

        for marker in ["node_modules/.package-lock.json", "node_modules/.modules.yaml", "node_modules/.yarn-state.yml",
                       "node_modules/.vite", "node_modules/.cache", ".next", ".next/cache", ".turbo", ".nuxt",
                       ".svelte-kit", ".parcel-cache", ".angular/cache"] {
            bump(project.appending(path: marker))
        }

        if let walker = FileManager.default.enumerator(
            at: project, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [], errorHandler: { _, _ in true }) {
            var seen = 0
            while let url = walker.nextObject() as? URL {
                seen += 1
                // Too big to check fully: call it active rather than risk a wrong "unused".
                if seen > maxActivityEntries { return .now }
                if generatedFolders.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
                if walker.level >= 4 { walker.skipDescendants() }
                bump(url)
            }
        }

        if let git = gitDirectory(for: project, home: home) {
            for file in ["index", "HEAD", "logs/HEAD", "FETCH_HEAD"] { bump(git.appending(path: file)) }
        }
        return newest
    }

    /// Finds the git dir for a project, following worktree `.git` files.
    static func gitDirectory(for project: URL, home: URL) -> URL? {
        let stop = home.resolvingSymlinksInPath().path
        var dir = project.resolvingSymlinksInPath()
        while dir.path != stop, dir.path != "/" {
            let dotGit = dir.appending(path: ".git")
            if Safety.isRealDirectory(dotGit) { return dotGit }
            if let text = try? String(contentsOf: dotGit, encoding: .utf8),
               let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") {
                let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                return path.hasPrefix("/") ? URL(filePath: path) : dir.appending(path: path)
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}

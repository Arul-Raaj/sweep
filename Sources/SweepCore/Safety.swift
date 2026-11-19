import Foundation

/// Last line of defence before anything is removed. Every item is re-checked here
/// at clean time, independent of how the scan found it.
public enum Safety {
    public static func allows(_ url: URL, rule: Rule, home: URL,
                              temp: URL = FileManager.default.temporaryDirectory) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains("..") else { return false }

        // Resolve symlinks in the parent only: if the item itself is a symlink,
        // the link is removed, never what it points to.
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appending(path: url.lastPathComponent)
        let targetPath = target.path(percentEncoded: false)

        // Only at least two levels inside the home folder (never ~ or ~/Desktop),
        // or directly inside the per-user temporary folder.
        let inHome = components(of: targetPath, below: home) >= 2
        let inTemp = parent.path == temp.resolvingSymlinksInPath().path
        guard inHome || inTemp else { return false }

        switch rule.kind {
        case let .contents(dirs, _, _, filter):
            // Only direct children of one of the rule's folders that its filter admits.
            return dirs.contains { parent.path == $0.resolvingSymlinksInPath().path } && filter.admits(url)

        case let .staleProjects(roots, _, folders):
            // Only a real generated folder next to a package.json, at least <root>/<project>/<folder>.
            guard folders.contains(url.lastPathComponent),
                  isRealDirectory(url),
                  FileManager.default.fileExists(atPath: parent.appending(path: "package.json").path)
            else { return false }
            return roots.contains { components(of: targetPath, below: $0) >= 2 }

        case let .webCaches(roots):
            // Only a real folder in Chromium's cache layout, at least <root>/<app>/<cache>.
            guard Sweeper.webCacheNames.contains(url.lastPathComponent),
                  isRealDirectory(url),
                  Sweeper.isWebCache(url)
            else { return false }
            return roots.contains { components(of: targetPath, below: $0) >= 2 }

        case .ownerCommand:
            // Its files are only ever removed by their own tool, never by Sweep.
            return false
        }
    }

    /// True if Sweep may run `tool` to clean `cache` for this rule: the rule's own tool,
    /// in one of its install folders, and a real cache folder inside home.
    public static func allowsCommand(_ tool: URL, cache: URL, rule: Rule, home: URL) -> Bool {
        guard case let .ownerCommand(cmd) = rule.kind,
              tool.isFileURL, cache.isFileURL,
              !tool.pathComponents.contains(".."), !cache.pathComponents.contains(".."),
              tool.lastPathComponent == cmd.tool,
              cmd.searchDirs.contains(where: { $0.standardizedFileURL.path == tool.deletingLastPathComponent().standardizedFileURL.path }),
              isToolExecutable(tool)
        else { return false }
        return isRealDirectory(cache) && components(of: cache.resolvingSymlinksInPath().path(percentEncoded: false), below: home) >= 2
    }

    /// An executable regular file (following a symlink, as Homebrew installs tools).
    static func isToolExecutable(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true && FileManager.default.isExecutableFile(atPath: path)
    }

    /// How many path components `path` sits below `root`; 0 if it isn't inside it.
    static func components(of path: String, below root: URL) -> Int {
        let r = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = r.hasSuffix("/") ? r : r + "/"
        guard path.hasPrefix(prefix) else { return 0 }
        return path.dropFirst(prefix.count).split(separator: "/").count
    }

    static func isRealDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}

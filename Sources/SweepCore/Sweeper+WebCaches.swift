import Foundation

/// Chromium / Electron app caches.
extension Sweeper {
    /// Folder names Chromium uses for disposable caches. Service-worker caches are
    /// deliberately left out: web editors (Figma, Notion, Docs) keep offline state there.
    public static let webCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GraphiteDawnCache", "GrShaderCache", "ShaderCache",
    ]
    /// Files Chromium keeps in a profile folder; one must sit next to a cache for it to count.
    private static let profileMarkers = [
        "Local Storage", "Session Storage", "Preferences", "Cookies", "Local State", "Network", "IndexedDB",
    ]
    private static let searchSkips: Set<String> = ["node_modules", ".git", "vm_bundles", "scratch-workspaces"]
    private static let recentUse: TimeInterval = 3_600

    static func scanWebCaches(_ rule: Rule, roots: [URL], now: Date, openFiles: OpenFiles?) -> Finding {
        let fm = FileManager.default
        var items: [Item] = []
        for root in roots {
            guard let apps = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for app in apps where Safety.isRealDirectory(app) {
                let parts = findWebCaches(in: app)
                guard !parts.isEmpty else { continue }
                var bytes: Int64 = 0
                var newest = Date.distantPast
                for part in parts {
                    let usage = measure(part)
                    bytes += usage.bytes
                    newest = max(newest, usage.newest)
                }
                guard bytes >= 1_000_000 else { continue }   // not worth a row
                items.append(Item(url: app, bytes: bytes, lastUsed: newest, parts: parts,
                                  blocked: webCacheBlock(owner: app, newest: newest, now: now, openFiles: openFiles)))
            }
        }
        return Finding(rule: rule, items: items.sorted { $0.bytes > $1.bytes })
    }

    /// Breadth-first search for verified cache folders inside one app's folder. Bounded,
    /// never follows symlinks, never looks inside a cache-named folder.
    static func findWebCaches(in app: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var found: [URL] = []
        var queue: [(URL, Int)] = [(app, 0)]
        var next = 0
        while next < queue.count, next < 4_000 {
            let (dir, depth) = queue[next]
            next += 1
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                guard let v = try? child.resourceValues(forKeys: Set(keys)),
                      v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { continue }
                let name = child.lastPathComponent
                if webCacheNames.contains(name) {
                    if isWebCache(child) { found.append(child) }
                } else if depth < 9, !searchSkips.contains(name) {
                    queue.append((child, depth + 1))
                }
            }
        }
        return found
    }

    /// True only for a folder in Chromium's own cache layout, inside a Chromium profile.
    public static func isWebCache(_ dir: URL) -> Bool {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: dir.appending(path: name).path) }
        let profile = dir.deletingLastPathComponent()

        switch dir.lastPathComponent {
        case "Cache":
            guard has("Cache_Data") || has("index-dir") || has("index") else { return false }
        case "Code Cache":
            guard has("js") || has("wasm") else { return false }
        case let name where webCacheNames.contains(name):
            guard has("index") else { return false }   // GPU / shader caches
        default:
            return false
        }
        // The profile, or a profile folder beside the cache (e.g. "Default"), must look like Chromium.
        func looksLikeProfile(_ url: URL) -> Bool {
            profileMarkers.contains { fm.fileExists(atPath: url.appending(path: $0).path) }
        }
        if looksLikeProfile(profile) { return true }
        let siblings = (try? fm.contentsOfDirectory(at: profile, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return siblings.contains { Safety.isRealDirectory($0) && looksLikeProfile($0) }
    }

    /// Why an app's caches can't be cleaned right now, or nil if they can.
    /// Three independent signals; any one of them blocks.
    static func webCacheBlock(owner: URL, newest: Date, now: Date, openFiles: OpenFiles?) -> String? {
        if let block = appBlock(owner: owner, openFiles: openFiles) { return block }
        if now.timeIntervalSince(newest) < recentUse {
            return "Used in the last hour. Try again later."
        }
        return nil
    }
}

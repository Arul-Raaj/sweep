import Foundation

/// One kind of junk Sweep knows how to find, with a plain explanation of why
/// removing it is safe. Rules are data; `Sweeper` does the work.
public struct Rule: Sendable, Identifiable {
    /// How careful the user needs to be. Lower levels are safer.
    public enum Level: Int, Sendable, CaseIterable, Comparable {
        /// Rebuilds itself. Nobody would notice.
        case recommended = 1
        /// Comes back, but costs a download, an install or a rebuild.
        case rebuildable = 2
        /// The user's own files. Only they can judge; moved to the Trash, not deleted.
        case review = 3

        public var title: String {
            switch self {
            case .recommended: "Recommended"
            case .rebuildable: "Rebuildable"
            case .review: "Review"
            }
        }

        public var summary: String {
            switch self {
            case .recommended: "Safe to remove. It rebuilds on its own and you won't notice."
            case .rebuildable: "Comes back when needed, with a download or an install."
            case .review: "Your files. Look before removing. They go to the Trash."
            }
        }

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Age: Sendable {
        /// Newest modification date of anything inside the entry.
        case modified
        /// When the entry was put in its folder (Trash, Downloads).
        case addedToFolder
    }

    /// Which entries of a folder a `contents` rule may take, by name.
    public struct Filter: Sendable {
        /// Names starting with one of these are never taken.
        public var except: [String]
        /// If set, only names starting with one of these.
        public var prefixes: [String]
        /// If set, only files or packages with one of these extensions; plain folders never.
        public var extensions: Set<String>

        public init(except: [String] = [], prefixes: [String] = [], extensions: Set<String> = []) {
            self.except = except
            self.prefixes = prefixes
            self.extensions = extensions
        }

        private static let ignored: Set<String> = [".DS_Store", ".localized"]

        public func admits(_ url: URL) -> Bool {
            let name = url.lastPathComponent
            guard !Self.ignored.contains(name), !except.contains(where: { name.hasPrefix($0) }) else { return false }
            guard prefixes.isEmpty || prefixes.contains(where: { name.hasPrefix($0) }) else { return false }
            guard !extensions.isEmpty else { return true }
            guard extensions.contains(url.pathExtension.lowercased()) else { return false }
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return v?.isDirectory != true || v?.isPackage == true
        }
    }

    public enum Kind: Sendable {
        /// Remove entries directly inside any of `dirs` that pass `filter` and are older
        /// than `days` (0 = any age).
        case contents(dirs: [URL], days: Int, age: Age, filter: Filter = Filter())
        /// Remove the named folders (e.g. `node_modules`, `.next`) of JS projects under
        /// `roots` that have had no activity for `days`.
        case staleProjects(roots: [URL], days: Int, folders: Set<String>)
        /// Remove the Chromium/Electron cache folders inside each app folder under `roots`,
        /// grouped per app, skipping apps that are open or used them recently.
        case webCaches(roots: [URL])
        /// Measure a tool's cache and clean it with the tool's own command. Sweep deletes
        /// nothing itself. Only listed when the tool is installed.
        case ownerCommand(OwnerCommand)
    }

    public let id: String
    public let name: String
    public let symbol: String
    public let level: Level
    public let kind: Kind
    /// What these files are.
    public let what: String
    /// Why removing them can't break anything.
    public let whySafe: String
    /// What you'll notice afterwards.
    public let after: String
    /// Verb for an item's date: "Used 2 weeks ago", "Added 3 months ago".
    public let dateVerb: String
    /// An app's data folder: while that app runs or has files open in it, nothing is removed.
    public let guardedBy: URL?

    /// Review-level items are the user's own files, so they go to the Trash.
    public var movesToTrash: Bool { level == .review }

    public init(id: String, name: String, symbol: String = "folder", level: Level = .recommended,
                kind: Kind, what: String = "", whySafe: String = "", after: String = "",
                dateVerb: String = "Changed", guardedBy: URL? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.level = level
        self.kind = kind
        self.what = what
        self.whySafe = whySafe
        self.after = after
        self.dateVerb = dateVerb
        self.guardedBy = guardedBy
    }
}

public extension Rule {
    /// Conservative defaults, ordered by level. `temp` is the per-user temporary folder.
    static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                         temp: URL = FileManager.default.temporaryDirectory) -> [Rule] {
        func h(_ path: String) -> URL { home.appending(path: path, directoryHint: .isDirectory) }
        let projectRoots = ["Desktop", "Documents", "dev", "Developer", "Projects", "code"].map(h)
        let tools = toolDirs(home: home)
        return [
            // MARK: Recommended

            Rule(id: "webcaches", name: "App web caches", symbol: "globe", level: .recommended,
                 kind: .webCaches(roots: [h("Library/Application Support"), h("Library/Containers")]),
                 what: "Apps built on web technology, like Claude, Figma, Slack, Teams and Notion, keep the same kind of cache a browser does: downloaded page files, compiled code and graphics shaders.",
                 whySafe: "Only Chromium's own cache folders are removed (Cache, Code Cache, GPUCache, shader caches), and only after checking their internal format. Sign-ins, settings, offline data and your files live in other folders and are never touched. Apps that are open, or used their cache in the last hour, are skipped.",
                 after: "Each app re-downloads what it needs, so its next launch may be a little slower."),

            // Some "caches" are live data: Apple's own (fonts, Spotlight, iCloud), model weights,
            // virtual environments, test browsers and offline music.
            Rule(id: "caches", name: "App caches", symbol: "square.stack.3d.up", level: .recommended,
                 kind: .contents(dirs: [h("Library/Caches")], days: 3, age: .modified, filter: Filter(except: [
                    "com.apple.", "CloudKit", "GeoServices", "PassKit", "Animoji",
                    "llama.cpp", "Buzz", "pypoetry", "pnpm", "ms-playwright", "Cypress", "kitty", "Homebrew",
                    "org.R-project.R", "com.spotify.client",
                 ])),
                 what: "Temporary files apps save so they load faster: downloaded images, thumbnails, web data.",
                 whySafe: "Apps are built to work without their caches and recreate them when needed. Only caches no app has touched for 3 days are listed. Apple's own system caches, and \"caches\" that really hold data (local AI models, Python environments, test browsers, offline music), are always left alone.",
                 after: "An app may feel a little slower the first time while it rebuilds its cache."),

            Rule(id: "automation", name: "Automation profiles", symbol: "safari", level: .recommended,
                 kind: .contents(dirs: [temp], days: 1, age: .modified, filter: Filter(prefixes: [
                    "cdp-", "puppeteer_dev_chrome_profile-", "playwright_chromiumdev_profile-", "playwright-artifacts-",
                 ])),
                 what: "Throwaway browser profiles that automation tools (Puppeteer, Playwright, AI browser agents) create in your temporary folder and often leave behind.",
                 whySafe: "Each run makes a fresh profile; old ones are never reused. Only profiles untouched for a day are listed, and macOS would clear them on restart anyway.",
                 after: "Nothing. The next automated run creates a new profile."),

            Rule(id: "iosupdates", name: "iPhone & iPad updates", symbol: "arrow.down.app", level: .recommended,
                 kind: .contents(dirs: [h("Library/iTunes/iPhone Software Updates"),
                                        h("Library/iTunes/iPad Software Updates")], days: 0, age: .modified),
                 what: "Software update files Finder downloaded when you updated an iPhone or iPad from this Mac.",
                 whySafe: "They're only used during an update. Finder downloads a fresh copy the next time it needs one.",
                 after: "The next update over a cable downloads again."),

            Rule(id: "simulator", name: "Simulator caches", symbol: "apps.iphone", level: .recommended,
                 kind: .contents(dirs: [h("Library/Developer/CoreSimulator/Caches")], days: 0, age: .modified),
                 what: "Cached data the iOS Simulator keeps between launches.",
                 whySafe: "The Simulator rebuilds it automatically. Your simulated devices and their apps are stored elsewhere and aren't touched.",
                 after: "A simulator may start more slowly the first time."),

            Rule(id: "logs", name: "Old logs", symbol: "doc.text", level: .recommended,
                 kind: .contents(dirs: [h("Library/Logs")], days: 7, age: .modified),
                 what: "Diagnostic records apps write while they run. Only logs untouched for 7 days are listed.",
                 whySafe: "Logs are only read when troubleshooting a past problem. No app needs old logs to work.",
                 after: "Nothing changes. Apps keep writing new logs."),

            Rule(id: "trash", name: "Old Trash", symbol: "trash", level: .recommended,
                 kind: .contents(dirs: [h(".Trash")], days: 30, age: .addedToFolder),
                 what: "Files you moved to the Trash more than 30 days ago.",
                 whySafe: "You already chose to delete them. It's the same as macOS's own \"Remove items from the Trash after 30 days\" option.",
                 after: "They're gone for good. Items trashed in the last 30 days stay.",
                 dateVerb: "Trashed"),

            // Package managers whose docs say to clean their caches with their own command.
            Rule(id: "uv", name: "uv cache", symbol: "cube", level: .recommended,
                 kind: .ownerCommand(OwnerCommand(tool: "uv", searchDirs: tools, locate: ["cache", "dir"],
                                                  clean: ["cache", "prune"], processNames: ["uv", "uvx"])),
                 what: "Python packages and builds that uv has downloaded, shared by all your Python projects. The size shown is the whole cache. uv removes only the parts nothing uses, so it may free less.",
                 whySafe: "Sweep doesn't delete these files itself. It runs uv's own cleanup, uv cache prune, which removes only entries that are no longer used, and skips anything uv is using. uv's documentation says to clean its cache this way, never by hand. Skipped while uv is running.",
                 after: "Nothing for your projects. A package you haven't used in a while may download again."),

            Rule(id: "brew", name: "Homebrew", symbol: "mug", level: .recommended,
                 kind: .ownerCommand(OwnerCommand(tool: "brew", searchDirs: tools, locate: ["--cache"],
                                                  clean: ["cleanup"], preview: ["cleanup", "--dry-run"],
                                                  environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
                                                                "HOMEBREW_NO_ENV_HINTS": "1"])),
                 what: "Older versions of tools you installed with Homebrew, and downloads it no longer needs.",
                 whySafe: "Sweep doesn't delete these files itself. It runs Homebrew's own cleanup, brew cleanup, which always keeps the version you have installed. Homebrew runs the same cleanup on its own from time to time. The list and size come from brew cleanup --dry-run. Skipped while Homebrew is running.",
                 after: "Nothing changes. Going back to an older version of a tool means installing it again."),

            // MARK: Rebuildable

            Rule(id: "node_modules", name: "node_modules", symbol: "shippingbox", level: .rebuildable,
                 kind: .staleProjects(roots: projectRoots, days: 14, folders: ["node_modules"]),
                 what: "Packages installed for a JavaScript project. Every project keeps its own full copy, often hundreds of megabytes.",
                 whySafe: "They're generated from package.json and the lockfile, which are never touched. Only projects with no file changes, git activity or installs for 14 days are listed, and each one is checked again right before it's removed.",
                 after: "Run npm install (or pnpm, yarn, bun) in the project before you work on it again.",
                 dateVerb: "Used"),

            Rule(id: "buildoutput", name: "Build output", symbol: "gearshape.2", level: .rebuildable,
                 kind: .staleProjects(roots: projectRoots, days: 14,
                                      folders: [".next", ".turbo", ".nuxt", ".svelte-kit", ".parcel-cache", ".angular"]),
                 what: "Folders that Next.js, Turborepo, Nuxt, SvelteKit, Parcel and Angular generate while building and caching a project.",
                 whySafe: "They're produced by the build and are never the source of anything. Only projects unused for 14 days are listed. Folders like dist and build are left alone, since some projects keep real files there.",
                 after: "The next build or dev server run takes longer while it regenerates them.",
                 dateVerb: "Used"),

            Rule(id: "npm", name: "npm cache", symbol: "cube", level: .rebuildable,
                 kind: .contents(dirs: [h(".npm/_cacache")], days: 0, age: .modified),
                 what: "A copy of every package npm has ever downloaded, kept to make later installs faster.",
                 whySafe: "npm treats this folder as disposable and re-downloads anything missing. Your projects never read from it directly.",
                 after: "The next install downloads packages again, so it takes a little longer."),

            Rule(id: "bun", name: "Bun cache", symbol: "cube", level: .rebuildable,
                 kind: .contents(dirs: [h(".bun/install/cache")], days: 0, age: .modified),
                 what: "Packages Bun has downloaded, kept to make later installs faster.",
                 whySafe: "Bun re-downloads anything missing from this cache automatically.",
                 after: "The next bun install takes a little longer."),

            Rule(id: "pnpm", name: "pnpm store", symbol: "cube", level: .rebuildable,
                 kind: .ownerCommand(OwnerCommand(tool: "pnpm", searchDirs: tools, locate: ["store", "path"],
                                                  clean: ["store", "prune"], processNames: ["pnpm", "pnpx"])),
                 what: "The shared store pnpm installs packages from, for all your JavaScript projects. The size shown is the whole store. pnpm removes only packages no project refers to, so it may free less.",
                 whySafe: "Sweep doesn't delete these files itself. It runs pnpm's own cleanup, pnpm store prune. pnpm's documentation says to clean the store this way, never by hand. Your projects keep working, because each one has its own installed copy. Skipped while pnpm is running.",
                 after: "The next pnpm install may download some packages again, so it takes a little longer."),

            Rule(id: "claudevm", name: "Claude Cowork sandbox", symbol: "cube.transparent", level: .rebuildable,
                 kind: .contents(dirs: [h("Library/Application Support/Claude/vm_bundles")], days: 0, age: .modified,
                                 filter: Filter(prefixes: ["claudevm"])),
                 what: "The virtual machine Claude's desktop app runs Cowork and agent tasks in. Its disk grows as it's used and isn't trimmed.",
                 whySafe: "Claude downloads and sets it up again the next time you use Cowork. It can only be removed while Claude is closed, and is never selected for you.",
                 after: "The next Cowork task takes longer to start, and anything installed inside the sandbox is gone.",
                 guardedBy: h("Library/Application Support/Claude")),

            Rule(id: "xcode", name: "Xcode build data", symbol: "hammer", level: .rebuildable,
                 kind: .contents(dirs: [h("Library/Developer/Xcode/DerivedData")], days: 0, age: .modified),
                 what: "Intermediate build products and code indexes Xcode creates for each project.",
                 whySafe: "Xcode recreates all of it on the next build. Deleting this folder is the standard fix for many Xcode problems.",
                 after: "The first build and indexing of each project takes longer."),

            Rule(id: "devicesupport", name: "Xcode device support", symbol: "cable.connector", level: .rebuildable,
                 kind: .contents(dirs: ["iOS", "watchOS", "tvOS", "visionOS"].map { h("Library/Developer/Xcode/\($0) DeviceSupport") },
                                 days: 30, age: .modified),
                 what: "Debug symbols Xcode copies from each iPhone, iPad or Watch you connect, one set per system version. Only sets unused for 30 days are listed.",
                 whySafe: "Xcode copies them again the next time a device with that version connects.",
                 after: "The first debug session on that device takes a few minutes longer."),

            // MARK: Review

            Rule(id: "installers", name: "Old installers & archives", symbol: "arrow.down.circle", level: .review,
                 kind: .contents(dirs: [h("Downloads")], days: 60, age: .addedToFolder, filter: Filter(extensions: [
                    "dmg", "pkg", "mpkg", "zip", "xip", "iso", "ipsw", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "app",
                 ])),
                 what: "Disk images, installers and archives that have sat in Downloads for more than 60 days. Your own folders and documents are never listed.",
                 whySafe: "Once an app is installed or an archive unpacked, the download is usually a spare copy. Check the list. They go to the Trash, so nothing is lost until you empty it.",
                 after: "Anything you still need can be put back from the Trash.",
                 dateVerb: "Added"),

            Rule(id: "archives", name: "Xcode archives", symbol: "archivebox", level: .review,
                 kind: .contents(dirs: [h("Library/Developer/Xcode/Archives")], days: 90, age: .modified),
                 what: "Builds you archived in Xcode for release, with their debug symbols. Only archives older than 90 days are listed.",
                 whySafe: "Only needed to re-export that build or read crash reports from it. They go to the Trash, so you can restore them.",
                 after: "You can't re-export those builds or symbolicate their crash logs anymore.",
                 dateVerb: "Archived"),

            Rule(id: "backups", name: "iPhone & iPad backups", symbol: "iphone", level: .review,
                 kind: .contents(dirs: [h("Library/Application Support/MobileSync/Backup")], days: 0, age: .modified),
                 what: "Full backups of iPhones and iPads made by Finder on this Mac. Each one can be many gigabytes.",
                 whySafe: "Remove only backups you don't need, such as an old phone's, or one that also backs up to iCloud. They go to the Trash first.",
                 after: "That device can no longer be restored from this Mac.",
                 dateVerb: "Backed up"),
        ]
    }
}

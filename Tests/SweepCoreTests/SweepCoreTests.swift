import Foundation
import Testing
@testable import SweepCore

/// Each test gets a throwaway fake home folder.
final class FakeHome {
    let url: URL
    let fm = FileManager.default

    init() throws {
        url = fm.temporaryDirectory.appending(path: "sweep-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? fm.removeItem(at: url) }

    @discardableResult
    /// Files default to a day old: Sweep treats anything written in the last two minutes as in use.
    func file(_ path: String, bytes: Int = 4096, daysOld: Double = 1) throws -> URL {
        let file = url.appending(path: path)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: file)
        try age(path, days: daysOld)
        return file
    }

    func age(_ path: String, days: Double) throws {
        let date = Date.now.addingTimeInterval(-days * 86_400)
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.appending(path: path).path)
    }

    /// Backdates a folder and everything inside it, folders included.
    func ageTree(_ path: String, days: Double) throws {
        let root = url.appending(path: path)
        let date = Date.now.addingTimeInterval(-days * 86_400)
        let inside = (fm.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for item in inside + [root] {
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: item.path)
        }
    }

    /// Backdates a symlink itself (setAttributes would follow it to its target).
    func ageLink(_ path: String, days: Double) {
        let seconds = Int(Date.now.timeIntervalSince1970 - days * 86_400)
        var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
        _ = lutimes(url.appending(path: path).path, &times)
    }

    func exists(_ path: String) -> Bool { fm.fileExists(atPath: url.appending(path: path).path) }
    func dir(_ path: String) -> URL { url.appending(path: path, directoryHint: .isDirectory) }
}

@Suite struct ContentsRule {
    @Test func removesEverythingInsideButKeepsTheFolder() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/app/blob")
        try home.file("Library/Caches/other.db")
        try home.ageTree("Library/Caches", days: 1)
        let rule = Rule(id: "c", name: "c", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified))

        let findings = Sweeper.scan([rule], home: home.url)
        #expect(findings[0].items.count == 2)
        #expect(findings[0].bytes > 0)

        let report = Sweeper.clean(findings, home: home.url)
        #expect(report.removed == 2)
        #expect(report.failures.isEmpty)
        #expect(home.exists("Library/Caches"))
        #expect(!home.exists("Library/Caches/app"))
    }

    @Test func respectsAgeUsingNewestFileInside() throws {
        let home = try FakeHome()
        try home.file("Library/Logs/old.log", daysOld: 10)
        try home.file("Library/Logs/new.log", daysOld: 1)
        try home.file("Library/Logs/mixed/old.log", daysOld: 30)
        try home.file("Library/Logs/mixed/fresh.log", daysOld: 0)
        let rule = Rule(id: "l", name: "l", kind: .contents(dirs: [home.dir("Library/Logs")], days: 7, age: .modified))

        let names = Sweeper.scan([rule], home: home.url)[0].items.map(\.url.lastPathComponent)
        #expect(names == ["old.log"])
    }

    @Test func excludedNamesAreNeverSelectedOrDeleted() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/com.apple.daemon/db")
        try home.file("Library/Caches/com.figma/blob")
        let rule = Rule(id: "c", name: "c", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified, filter: Rule.Filter(except: ["com.apple."])))

        let findings = Sweeper.scan([rule], home: home.url)
        #expect(findings[0].items.map(\.url.lastPathComponent) == ["com.figma"])
        #expect(!Safety.allows(home.url.appending(path: "Library/Caches/com.apple.daemon"), rule: rule, home: home.url))
    }

    @Test func extensionFilterSkipsFoldersAndOtherFiles() throws {
        let home = try FakeHome()
        try home.file("Downloads/Installer.dmg", daysOld: 90)
        try home.file("Downloads/notes.pdf", daysOld: 90)
        try home.file("Downloads/Receipts/2024.pdf", daysOld: 90)
        try home.ageTree("Downloads/Receipts", days: 90)
        let rule = Rule(id: "i", name: "i", level: .review, kind: .contents(
            dirs: [home.dir("Downloads")], days: 60, age: .modified, filter: Rule.Filter(extensions: ["dmg", "zip"])))

        #expect(Sweeper.scan([rule], home: home.url)[0].items.map(\.url.lastPathComponent) == ["Installer.dmg"])
        #expect(!Safety.allows(home.dir("Downloads/Receipts"), rule: rule, home: home.url))
        #expect(!Safety.allows(home.url.appending(path: "Downloads/notes.pdf"), rule: rule, home: home.url))
    }

    @Test func itemChangedAfterScanIsKept() throws {
        let home = try FakeHome()
        try home.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o")
        try home.ageTree("Library/Developer/Xcode/DerivedData/App-abc", days: 1)
        let rule = Rule(id: "x", name: "x", kind: .contents(
            dirs: [home.dir("Library/Developer/Xcode/DerivedData")], days: 0, age: .modified))
        let findings = Sweeper.scan([rule], home: home.url)
        #expect(findings[0].items.count == 1)

        try home.file("Library/Developer/Xcode/DerivedData/App-abc/Build/y.o", daysOld: 0)   // a build starts
        let report = Sweeper.clean(findings, home: home.url)
        #expect(report.removed == 0)
        #expect(report.kept == 1)
        #expect(home.exists("Library/Developer/Xcode/DerivedData/App-abc"))
    }

    @Test func missingFolderIsNotAnError() throws {
        let home = try FakeHome()
        let rule = Rule(id: "x", name: "x", kind: .contents(dirs: [home.dir("nope")], days: 0, age: .modified))
        let finding = Sweeper.scan([rule], home: home.url)[0]
        #expect(finding.items.isEmpty)
        #expect(finding.note == nil)
    }

    @Test func deletesSymlinkNotItsTarget() throws {
        let home = try FakeHome()
        let precious = try home.file("Documents/precious.txt")
        try home.fm.createDirectory(at: home.dir("Library/Caches"), withIntermediateDirectories: true)
        try home.fm.createSymbolicLink(at: home.url.appending(path: "Library/Caches/link"), withDestinationURL: precious.deletingLastPathComponent())
        home.ageLink("Library/Caches/link", days: 1)
        let rule = Rule(id: "c", name: "c", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified))

        // A link has no size of its own, so a scan skips it; feed it to clean directly.
        let link = Item(url: home.url.appending(path: "Library/Caches/link"), bytes: 0)
        let report = Sweeper.clean([Finding(rule: rule, items: [link])], home: home.url)
        #expect(report.removed == 1)
        #expect(home.exists("Documents/precious.txt"))
        #expect(!home.exists("Library/Caches/link"))
    }
}

@Suite struct NodeModulesRule {
    func makeProject(_ home: FakeHome, _ name: String, daysOld: Double) throws {
        try home.file("dev/\(name)/package.json", daysOld: daysOld)
        try home.file("dev/\(name)/src/index.js", daysOld: daysOld)
        try home.file("dev/\(name)/node_modules/lib/index.js", bytes: 10_000, daysOld: daysOld)
        for path in ["src", "node_modules/lib", "node_modules", ""] { try home.age("dev/\(name)/\(path)", days: daysOld) }
    }

    @Test func onlyStaleProjectsAreSelected() throws {
        let home = try FakeHome()
        try makeProject(home, "old", daysOld: 30)
        try makeProject(home, "active", daysOld: 2)
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))

        let items = Sweeper.scan([rule], home: home.url)[0].items
        #expect(items.map { $0.url.deletingLastPathComponent().lastPathComponent } == ["old"])

        _ = Sweeper.clean(Sweeper.scan([rule], home: home.url), home: home.url)
        #expect(!home.exists("dev/old/node_modules"))
        #expect(home.exists("dev/old/package.json"))
        #expect(home.exists("dev/active/node_modules"))
    }

    @Test func projectUsedAfterScanIsKeptAtDeleteTime() throws {
        let home = try FakeHome()
        try makeProject(home, "old", daysOld: 30)
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))
        let findings = Sweeper.scan([rule], home: home.url)
        #expect(findings[0].items.count == 1)

        try home.file("dev/old/src/edited.js")   // you open the project again
        let report = Sweeper.clean(findings, home: home.url)
        #expect(report.removed == 0)
        #expect(report.kept == 1)
        #expect(home.exists("dev/old/node_modules"))
    }

    @Test func recentGitActivityKeepsProjectAlive() throws {
        let home = try FakeHome()
        try makeProject(home, "repo", daysOld: 60)
        try home.file("dev/repo/.git/index", daysOld: 1)
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))
        #expect(Sweeper.scan([rule], home: home.url)[0].items.isEmpty)
    }

    @Test func worktreeGitFileIsFollowed() throws {
        let home = try FakeHome()
        try makeProject(home, "wt", daysOld: 60)
        try home.file("dev/main/.git/worktrees/wt/index", daysOld: 0)
        try "gitdir: \(home.url.path)/dev/main/.git/worktrees/wt\n"
            .write(to: home.url.appending(path: "dev/wt/.git"), atomically: true, encoding: .utf8)
        try home.age("dev/wt/.git", days: 60)
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))
        #expect(Sweeper.scan([rule], home: home.url)[0].items.isEmpty)
    }

    @Test func folderWithoutPackageJsonIsIgnored() throws {
        let home = try FakeHome()
        try home.file("dev/thing/node_modules/x.js", daysOld: 90)
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))
        #expect(Sweeper.scan([rule], home: home.url)[0].items.isEmpty)
    }
}

@Suite struct DefaultRules {
    let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
    let temp = URL(filePath: "/private/var/folders/xy/T", directoryHint: .isDirectory)

    @Test func idsAreUniqueAndOrderedByLevel() {
        let rules = Rule.defaults(home: home, temp: temp)
        #expect(Set(rules.map(\.id)).count == rules.count)
        #expect(rules.map(\.level) == rules.map(\.level).sorted())
    }

    @Test func reviewLevelAlwaysMovesToTrash() {
        for rule in Rule.defaults(home: home, temp: temp) {
            #expect(rule.movesToTrash == (rule.level == .review), "\(rule.id)")
        }
    }

    @Test func everyRuleStaysInsideHomeAndExplainsItself() {
        for rule in Rule.defaults(home: home, temp: temp) {
            let paths: [URL] = switch rule.kind {
            case let .contents(dirs, _, _, _): dirs
            case let .staleProjects(roots, _, _): roots
            case let .webCaches(roots): roots
            case let .ownerCommand(cmd): cmd.searchDirs
            }
            #expect(paths.allSatisfy { $0.path.hasPrefix("/Users/someone/") || $0 == temp }, "\(rule.id)")
            #expect(!rule.what.isEmpty && !rule.whySafe.isEmpty && !rule.after.isEmpty, "\(rule.id)")
        }
    }

    @Test func ownerCommandsUseTheirToolsAtTheRightLevel() {
        let rules = Dictionary(uniqueKeysWithValues: Rule.defaults(home: home, temp: temp).map { ($0.id, $0) })
        for (id, level, command) in [("uv", Rule.Level.recommended, "uv cache prune"),
                                     ("brew", .recommended, "brew cleanup"),
                                     ("pnpm", .rebuildable, "pnpm store prune")] {
            guard let rule = rules[id], case let .ownerCommand(cmd) = rule.kind else {
                Issue.record("missing \(id)")
                continue
            }
            #expect(rule.level == level)
            #expect(cmd.display == command)
        }
    }

    @Test func multiFolderRuleScansAndGuardsEachFolder() throws {
        let fake = try FakeHome()
        try fake.file("Library/iTunes/iPhone Software Updates/a.ipsw", bytes: 8192)
        try fake.file("Library/iTunes/iPad Software Updates/b.ipsw", bytes: 8192)
        try fake.file("Library/iTunes/other.txt")
        let rule = Rule(id: "u", name: "u", kind: .contents(
            dirs: [fake.dir("Library/iTunes/iPhone Software Updates"), fake.dir("Library/iTunes/iPad Software Updates")],
            days: 0, age: .modified))

        let names = Sweeper.scan([rule], home: fake.url)[0].items.map(\.url.lastPathComponent).sorted()
        #expect(names == ["a.ipsw", "b.ipsw"])
        #expect(!Safety.allows(fake.url.appending(path: "Library/iTunes/other.txt"), rule: rule, home: fake.url))
    }
}

/// The real default rules, end to end, on a fake home with every category and decoys.
@Suite struct EndToEnd {
    @Test func defaultRulesRemoveOnlyWhatTheyShould() throws {
        let home = try FakeHome()
        func make(_ path: String, days: Double, bytes: Int = 8192) throws {
            try home.file(path, bytes: bytes, daysOld: days)
        }

        // Should go (Recommended + Rebuildable).
        let targets = [
            "Library/Caches/com.figma.Desktop",
            "Library/Logs/old.log",
            "Library/iTunes/iPhone Software Updates/iPhone.ipsw",
            "Library/Developer/CoreSimulator/Caches/dyld",
            ".npm/_cacache/content-v2",
            "Library/Developer/Xcode/DerivedData/App-abc",
            "dev/oldproj/node_modules",
            "Library/Application Support/FakeElectronApp/Cache",
            "Library/Application Support/FakeElectronApp/Code Cache",
        ]
        try make("Library/Caches/com.figma.Desktop/blob", days: 5)
        try make("Library/Logs/old.log", days: 10)
        try make("Library/iTunes/iPhone Software Updates/iPhone.ipsw", days: 1)
        try make("Library/Developer/CoreSimulator/Caches/dyld/x", days: 1)
        try make(".npm/_cacache/content-v2/x", days: 1)
        try make("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", days: 1)
        try make("dev/oldproj/package.json", days: 30)
        try make("dev/oldproj/node_modules/lib/index.js", days: 30)
        let app = "Library/Application Support/FakeElectronApp"
        try make("\(app)/Local Storage/leveldb/000003.log", days: 5)
        try make("\(app)/Cache/Cache_Data/f_000001", days: 5, bytes: 1_200_000)
        try make("\(app)/Code Cache/js/abc", days: 5)

        // Must stay.
        let decoys = [
            "Documents/thesis.pdf",
            "Downloads/Receipts/2024.pdf",
            "Library/Application Support/SomeTool/Cache/important.db",
            "\(app)/Local Storage/leveldb/000003.log",
            "Library/Caches/com.apple.Safari/x",
            "Library/Caches/RecentApp/x",
            "Library/Logs/new.log",
            "dev/oldproj/package.json",
            "dev/activeproj/node_modules/lib/index.js",
            "Downloads/Installer.dmg",   // Review level: not part of this run
        ]
        try make("Documents/thesis.pdf", days: 400)
        try make("Downloads/Receipts/2024.pdf", days: 400)
        try make("Library/Application Support/SomeTool/Cache/important.db", days: 400, bytes: 2_000_000)
        try make("Library/Caches/com.apple.Safari/x", days: 30)
        try make("Library/Caches/RecentApp/x", days: 1)
        try make("Library/Logs/new.log", days: 2)
        try make("dev/activeproj/package.json", days: 1)
        try make("dev/activeproj/node_modules/lib/index.js", days: 1)
        try make("Downloads/Installer.dmg", days: 400)

        // Folders carry their own dates: age every tree to match its files.
        for (dir, days) in [("Library/Caches/com.figma.Desktop", 5.0), ("Library/Caches/com.apple.Safari", 30),
                            ("Library/Developer/CoreSimulator/Caches/dyld", 1), (".npm/_cacache/content-v2", 1),
                            ("Library/Developer/Xcode/DerivedData/App-abc", 1), ("dev/oldproj", 30), (app, 5),
                            ("Library/Application Support/SomeTool", 400), ("Documents", 400), ("Downloads", 400)] {
            try home.ageTree(dir, days: days)
        }

        try make("dev/oldproj/.next/cache/webpack/x.pack", days: 30)
        try make("dev/oldproj/dist/index.js", days: 30)
        try make("tmp/cdp-abc/Default/Preferences", days: 2)
        try make("tmp/cdp-fresh/Default/Preferences", days: 0)
        try make("tmp/com.example.app.lock/x", days: 30)
        try home.ageTree("dev/oldproj", days: 30)
        try home.ageTree("tmp/cdp-abc", days: 2)
        try home.ageTree("tmp/com.example.app.lock", days: 30)

        // A fake uv in the fake home's own tool folder; the real one is never reached.
        let uv = Rule.toolDirs(home: home.url)[0].appending(path: "uv")
        try home.fm.createDirectory(at: uv.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
            #!/bin/sh
            case "$1 $2" in
            "cache dir") echo "$HOME/.cache/uv" ;;
            "cache prune") rm -rf "$HOME/.cache/uv/wheels-old" ;;
            *) exit 2 ;;
            esac
            """.write(to: uv, atomically: true, encoding: .utf8)
        try home.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv.path)
        try make(".cache/uv/wheels-old/a.whl", days: 1, bytes: 300_000)
        try make(".cache/uv/wheels-v5/b.whl", days: 1)
        try make("Library/Caches/Homebrew/downloads/x.tar.gz", days: 30)
        try home.ageTree(".cache/uv", days: 1)
        try home.ageTree("Library/Caches/Homebrew", days: 30)

        let rules = Rule.defaults(home: home.url, temp: home.dir("tmp"))
            .filter { $0.level <= .rebuildable }
            .map(ignoringRealProcesses)
        let report = Sweeper.clean(Sweeper.scan(rules, home: home.url), home: home.url)

        #expect(!home.exists(".cache/uv/wheels-old"), "uv cache prune should have run")
        #expect(home.exists(".cache/uv/wheels-v5/b.whl"))
        #expect(home.exists("Library/Caches/Homebrew/downloads/x.tar.gz"), "Homebrew's cache is brew's to clean")
        #expect(report.ran.count == 1)

        for path in targets + ["dev/oldproj/.next", "tmp/cdp-abc"] { #expect(!home.exists(path), "should be removed: \(path)") }
        for path in ["dev/oldproj/dist/index.js", "tmp/cdp-fresh", "tmp/com.example.app.lock"] {
            #expect(home.exists(path), "must stay: \(path)")
        }
        for path in decoys { #expect(home.exists(path), "must stay: \(path)") }
        #expect(report.failures.isEmpty)
        #expect(report.trashed == 0)
        #expect(report.freed > 1_200_000)
    }
}

/// The test runs real default rules, so a real uv running on this Mac would (rightly) make
/// Sweep wait. Watch for a process name nothing uses instead.
func ignoringRealProcesses(_ rule: Rule) -> Rule {
    guard case var .ownerCommand(cmd) = rule.kind else { return rule }
    cmd.processNames = ["sweep-test-no-such-process"]
    return Rule(id: rule.id, name: rule.name, symbol: rule.symbol, level: rule.level, kind: .ownerCommand(cmd),
                what: rule.what, whySafe: rule.whySafe, after: rule.after, dateVerb: rule.dateVerb, guardedBy: rule.guardedBy)
}

@Suite struct WebCachesRule {
    /// A fake Electron app with a real-looking Chromium profile.
    func makeApp(_ home: FakeHome, _ name: String, daysOld: Double) throws {
        let base = "Library/Application Support/\(name)"
        try home.file("\(base)/Local Storage/leveldb/000003.log", daysOld: daysOld)
        try home.file("\(base)/Preferences", daysOld: daysOld)
        try home.file("\(base)/Cache/Cache_Data/f_000001", bytes: 1_200_000, daysOld: daysOld)
        try home.file("\(base)/Code Cache/js/abc", daysOld: daysOld)
        try home.file("\(base)/GPUCache/index", daysOld: daysOld)
        try home.file("\(base)/Service Worker/CacheStorage/123/data", daysOld: daysOld)
        try home.ageTree(base, days: daysOld)
    }

    func rule(_ home: FakeHome) -> Rule {
        Rule(id: "w", name: "w", kind: .webCaches(roots: [home.dir("Library/Application Support")]))
    }

    @Test func groupsAnAppsCachesAndKeepsItsData() throws {
        let home = try FakeHome()
        try makeApp(home, "FakeElectronApp", daysOld: 5)
        let findings = Sweeper.scan([rule(home)], home: home.url)
        let item = try #require(findings[0].items.first)
        #expect(findings[0].items.count == 1)
        #expect(item.parts.count == 3)   // Cache, Code Cache, GPUCache; never service-worker caches
        #expect(item.blocked == nil)

        let report = Sweeper.clean(findings, home: home.url)
        #expect(report.removed == 1)
        let base = "Library/Application Support/FakeElectronApp"
        #expect(!home.exists("\(base)/Cache"))
        #expect(!home.exists("\(base)/Code Cache"))
        #expect(home.exists("\(base)/Service Worker/CacheStorage"))   // web editors keep offline state here
        #expect(home.exists("\(base)/Local Storage/leveldb/000003.log"))
        #expect(home.exists("\(base)/Preferences"))
    }

    @Test func recentlyUsedCachesAreBlocked() throws {
        let home = try FakeHome()
        try makeApp(home, "FakeElectronApp", daysOld: 0)
        let findings = Sweeper.scan([rule(home)], home: home.url)
        #expect(findings[0].items.first?.blocked != nil)
        #expect(findings[0].bytes == 0)

        let report = Sweeper.clean(findings, home: home.url)
        #expect(report.removed == 0)
        #expect(home.exists("Library/Application Support/FakeElectronApp/Cache"))
    }

    @Test func openFileInAppFolderBlocksItsCaches() throws {
        let home = try FakeHome()
        try makeApp(home, "VendorFolder", daysOld: 5)   // not named after any running app
        let lock = home.url.appending(path: "Library/Application Support/VendorFolder/Local Storage/leveldb/000003.log")
        let handle = try FileHandle(forReadingFrom: lock)   // this test process now "runs" the app
        defer { try? handle.close() }

        let item = try #require(Sweeper.scan([rule(home)], home: home.url)[0].items.first)
        #expect(item.blocked != nil)
    }

    @Test func lookAlikeCacheFoldersAreIgnored() throws {
        let home = try FakeHome()
        // A "Cache" folder in an app that isn't Chromium: no profile markers, no Chromium layout.
        try home.file("Library/Application Support/SomeTool/Cache/important.db", bytes: 2_000_000, daysOld: 30)
        #expect(Sweeper.scan([rule(home)], home: home.url)[0].items.isEmpty)
        #expect(!Safety.allows(home.dir("Library/Application Support/SomeTool/Cache"), rule: rule(home), home: home.url))
    }
}

@Suite struct GuardedAndTemp {
    @Test func guardedRuleIsBlockedWhileItsAppHasFilesOpen() throws {
        let home = try FakeHome()
        let owner = "Library/Application Support/SandboxApp"
        try home.file("\(owner)/vm_bundles/appvm.bundle/rootfs.img", bytes: 64_000, daysOld: 5)
        try home.file("\(owner)/Local Storage/leveldb/LOCK", daysOld: 5)
        try home.ageTree(owner, days: 5)
        let rule = Rule(id: "vm", name: "vm", level: .rebuildable,
                        kind: .contents(dirs: [home.dir("\(owner)/vm_bundles")], days: 0, age: .modified,
                                        filter: Rule.Filter(prefixes: ["appvm"])),
                        guardedBy: home.dir(owner))

        let closed = try #require(Sweeper.scan([rule], home: home.url)[0].items.first)
        #expect(closed.blocked == nil)

        let handle = try FileHandle(forReadingFrom: home.url.appending(path: "\(owner)/Local Storage/leveldb/LOCK"))
        defer { try? handle.close() }
        let open = try #require(Sweeper.scan([rule], home: home.url)[0].items.first)
        #expect(open.blocked != nil)
        // Even an item scanned while closed is kept if the app opens before the clean.
        let report = Sweeper.clean([Finding(rule: rule, items: [closed])], home: home.url)
        #expect(report.removed == 0)
        #expect(home.exists("\(owner)/vm_bundles/appvm.bundle"))
    }

    @Test func tempFolderOnlyAllowsDirectChildrenForItsRule() throws {
        let home = try FakeHome()
        let temp = URL(filePath: NSTemporaryDirectory()).appending(path: "sweep-temp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp.appending(path: "cdp-1/sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let rule = Rule(id: "a", name: "a", kind: .contents(dirs: [temp], days: 1, age: .modified,
                                                            filter: Rule.Filter(prefixes: ["cdp-"])))
        let other = Rule(id: "o", name: "o", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified))

        #expect(Safety.allows(temp.appending(path: "cdp-1"), rule: rule, home: home.url, temp: temp))
        #expect(!Safety.allows(temp.appending(path: "cdp-1/sub"), rule: rule, home: home.url, temp: temp))
        #expect(!Safety.allows(temp.appending(path: "other"), rule: rule, home: home.url, temp: temp))
        #expect(!Safety.allows(temp.appending(path: "cdp-1"), rule: other, home: home.url, temp: temp))
    }
}

@Suite struct SafetyGuard {
    @Test func blocksAnythingOutsideTheRule() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/a")
        try home.file("Documents/b")
        let caches = Rule(id: "c", name: "c", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified))

        #expect(Safety.allows(home.url.appending(path: "Library/Caches/a"), rule: caches, home: home.url))
        #expect(!Safety.allows(home.url.appending(path: "Documents/b"), rule: caches, home: home.url))
        #expect(!Safety.allows(home.dir("Library/Caches"), rule: caches, home: home.url))
        #expect(!Safety.allows(home.url, rule: caches, home: home.url))
        #expect(!Safety.allows(URL(filePath: "/usr/bin/a"), rule: caches, home: home.url))
        #expect(!Safety.allows(URL(filePath: home.url.path + "/Library/Caches/../../Documents/b"), rule: caches, home: home.url))
    }

    @Test func blocksTamperedItemsAtCleanTime() throws {
        let home = try FakeHome()
        try home.file("Documents/keep.txt")
        let caches = Rule(id: "c", name: "c", kind: .contents(dirs: [home.dir("Library/Caches")], days: 0, age: .modified))
        let forged = Finding(rule: caches, items: [Item(url: home.url.appending(path: "Documents/keep.txt"), bytes: 1)], note: nil)

        let report = Sweeper.clean([forged], home: home.url)
        #expect(report.removed == 0)
        #expect(report.failures.count == 1)
        #expect(home.exists("Documents/keep.txt"))
    }

    @Test func nodeModulesMustBeARealFolderNextToPackageJson() throws {
        let home = try FakeHome()
        try home.file("dev/p/package.json")
        try home.file("dev/p/node_modules/x")
        try home.file("dev/q/node_modules/x")
        let rule = Rule(id: "n", name: "n", kind: .staleProjects(roots: [home.dir("dev")], days: 14, folders: ["node_modules"]))

        #expect(Safety.allows(home.dir("dev/p/node_modules"), rule: rule, home: home.url))
        #expect(!Safety.allows(home.dir("dev/q/node_modules"), rule: rule, home: home.url))
        #expect(!Safety.allows(home.dir("dev/p"), rule: rule, home: home.url))
    }
}

// MARK: - Owner commands

/// A fake command-line tool: a shell script installed in the fake home's own
/// opt/homebrew/bin, where `Rule.toolDirs` looks for tools when home isn't yours.
/// Tests never run the real pnpm, uv or brew.
struct FakeTool {
    let name: String
    let url: URL

    init(_ home: FakeHome, name: String = "sweepfake" + UUID().uuidString.prefix(8).lowercased(), script: String) throws {
        self.name = name
        let dir = Rule.toolDirs(home: home.url)[0]
        url = dir.appending(path: name)
        try home.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try home.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func rule(_ home: FakeHome, locate: [String] = ["cache", "dir"], preview: [String]? = nil,
              level: Rule.Level = .recommended, timeout: TimeInterval = 30) -> Rule {
        Rule(id: name, name: name, level: level, kind: .ownerCommand(OwnerCommand(
            tool: name, searchDirs: Rule.toolDirs(home: home.url), locate: locate,
            clean: ["cache", "prune"], preview: preview, timeout: timeout)))
    }

    /// Runs the tool so it shows up as a running process, until the handle is terminated.
    func hold() throws -> Process {
        let process = Process()
        process.executableURL = url
        process.arguments = ["hold"]
        try process.run()
        return process
    }
}

/// A uv-like tool: `cache dir` prints the cache, `cache prune` removes the unused part.
func pruningTool(_ home: FakeHome, prune: String = #"rm -rf "$HOME/.cache/fake/unused"; echo "Removed 1 entry""#) throws -> FakeTool {
    try FakeTool(home, script: """
        case "$1 $2" in
        "cache dir") echo "$HOME/.cache/fake" ;;
        "cache prune") \(prune) ;;
        "hold ") sleep 30 ;;
        *) echo "unknown command" >&2; exit 2 ;;
        esac
        """)
}

func makeCache(_ home: FakeHome) throws {
    try home.file(".cache/fake/unused/a.whl", bytes: 200_000)
    try home.file(".cache/fake/used/b.whl", bytes: 50_000)
    try home.ageTree(".cache/fake", days: 1)
}

func samePath(_ a: URL?, _ b: URL) -> Bool {
    a?.resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/")
        == b.resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/")
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
}

@Suite struct OwnerCommandRule {
    @Test func notInstalledMeansNoCategory() throws {
        let home = try FakeHome()
        let rule = Rule(id: "t", name: "t", kind: .ownerCommand(OwnerCommand(
            tool: "sweep-missing-tool", searchDirs: Rule.toolDirs(home: home.url), locate: ["dir"], clean: ["prune"])))
        #expect(Sweeper.scan([rule], home: home.url).isEmpty)
    }

    @Test func measuresTheCacheThenRunsTheToolsOwnCleanup() throws {
        let home = try FakeHome()
        try makeCache(home)
        let tool = try pruningTool(home)
        let rule = tool.rule(home)

        let finding = try #require(Sweeper.scan([rule], home: home.url).first)
        let item = try #require(finding.items.first)
        #expect(finding.note == nil)
        #expect(samePath(item.url, home.dir(".cache/fake")))
        #expect(item.bytes >= 250_000)
        #expect(item.blocked == nil)

        let report = Sweeper.clean([finding], home: home.url)
        #expect(report.failures.isEmpty)
        #expect(report.removed == 1)
        #expect(report.ran == [item.url])
        // Freed is measured before and after: only what the tool removed, not the whole cache.
        #expect(report.freed >= 200_000 && report.freed < item.bytes)
        #expect(!home.exists(".cache/fake/unused"))
        #expect(home.exists(".cache/fake/used/b.whl"))
    }

    @Test func failingCommandIsReportedAndNothingElseHappens() throws {
        let home = try FakeHome()
        try makeCache(home)
        let tool = try pruningTool(home, prune: #"echo "error: cache is locked" >&2; exit 3"#)

        let report = Sweeper.clean(Sweeper.scan([tool.rule(home)], home: home.url), home: home.url)
        #expect(report.removed == 0)
        #expect(report.freed == 0)
        #expect(report.ran.isEmpty)
        #expect(report.failures.count == 1)
        #expect(report.failures.first?.reason.contains("cache is locked") == true)
        #expect(home.exists(".cache/fake/unused/a.whl"))
    }

    @Test func timeoutStopsTheToolAndEverythingItStarted() throws {
        let home = try FakeHome()
        try makeCache(home)
        // Not exec'd: the sleeping child must be stopped too, or it would hold the output open.
        let tool = try pruningTool(home, prune: #"sleep 30; rm -rf "$HOME/.cache/fake/unused""#)
        let findings = Sweeper.scan([tool.rule(home, timeout: 2)], home: home.url)
        #expect(findings.first?.items.count == 1)

        let start = Date.now
        let report = Sweeper.clean(findings, home: home.url)
        #expect(Date.now.timeIntervalSince(start) < 10)
        #expect(report.removed == 0)
        #expect(report.failures.first?.reason.contains("didn't finish") == true)
        #expect(home.exists(".cache/fake/unused/a.whl"))
    }

    @Test func runningToolIsSkippedAtScanAndAtCleanTime() throws {
        let home = try FakeHome()
        try makeCache(home)
        let tool = try pruningTool(home)
        let rule = tool.rule(home)
        let idle = Sweeper.scan([rule], home: home.url)
        #expect(idle.first?.items.count == 1)

        let running = try tool.hold()
        defer { running.terminate() }
        let busy = try #require(Sweeper.scan([rule], home: home.url).first)
        #expect(busy.items.isEmpty)
        #expect(busy.note?.contains("is running") == true)

        // Scanned while idle, but the tool started before the clean: keep everything.
        let report = Sweeper.clean(idle, home: home.url)
        #expect(report.kept == 1)
        #expect(report.removed == 0)
        #expect(home.exists(".cache/fake/unused/a.whl"))
    }

    @Test func openFileInTheCacheBlocksIt() throws {
        let home = try FakeHome()
        try makeCache(home)
        let tool = try pruningTool(home)
        let handle = try FileHandle(forReadingFrom: home.url.appending(path: ".cache/fake/used/b.whl"))
        defer { try? handle.close() }

        let finding = try #require(Sweeper.scan([tool.rule(home)], home: home.url).first)
        #expect(finding.items.isEmpty)
        #expect(finding.note != nil)
    }

    @Test func recentlyWrittenCacheIsBlocked() throws {
        let home = try FakeHome()
        try home.file(".cache/fake/unused/a.whl", bytes: 200_000, daysOld: 0)
        let tool = try pruningTool(home)
        let finding = try #require(Sweeper.scan([tool.rule(home)], home: home.url).first)
        #expect(finding.items.first?.blocked != nil)
        #expect(Sweeper.clean([finding], home: home.url).removed == 0)
        #expect(home.exists(".cache/fake/unused/a.whl"))
    }

    @Test func cacheOutsideHomeIsLeftAlone() throws {
        let home = try FakeHome()
        let tool = try FakeTool(home, script: #"[ "$1" = "dir" ] && echo /usr/lib; exit 0"#)
        let finding = try #require(Sweeper.scan([tool.rule(home, locate: ["dir"])], home: home.url).first)
        #expect(finding.items.isEmpty)
        #expect(finding.note != nil)
    }

    @Test func dryRunListsExactlyWhatWillGo() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/FakeBrew/old--1.0.tar.gz", bytes: 300_000)
        try home.file("Library/Caches/FakeBrew/current--2.0.tar.gz", bytes: 300_000)
        try home.file("Cellar/thing/1.0/bin/thing", bytes: 100_000)
        try home.file("Cellar/thing/2.0/bin/thing", bytes: 100_000)
        try home.ageTree("Library/Caches/FakeBrew", days: 1)
        try home.ageTree("Cellar", days: 1)
        let tool = try FakeTool(home, script: #"""
            C="$HOME/Library/Caches/FakeBrew"
            case "$1 $2" in
            "--cache ") echo "$C" ;;
            "cache prune --dry-run"|"cache prune") ;;
            esac
            if [ "$1 $2 $3" = "cache prune --dry-run" ]; then
                echo "Would remove: $C/old--1.0.tar.gz (293KB)"
                echo "Would remove: $HOME/Cellar/thing/1.0 (1 file, 97.7KB)"
                echo "Would remove: $HOME/Cellar/thing/1.0/bin (1 file, 97.7KB)"
                echo "Would remove: $HOME/gone-already (1KB)"
                echo "==> This operation would free approximately 390KB of disk space."
            elif [ "$1 $2" = "cache prune" ]; then
                rm -rf "$C/old--1.0.tar.gz" "$HOME/Cellar/thing/1.0"
            fi
            """#)
        let rule = tool.rule(home, locate: ["--cache"], preview: ["cache", "prune", "--dry-run"])

        let item = try #require(Sweeper.scan([rule], home: home.url).first?.items.first)
        #expect(item.parts.map(\.lastPathComponent).sorted() == ["1.0", "old--1.0.tar.gz"])
        #expect(item.bytes >= 400_000 && item.bytes < 600_000)

        let report = Sweeper.clean([Finding(rule: rule, items: [item])], home: home.url)
        #expect(report.removed == 1)
        #expect(report.freed >= 400_000 && report.freed < 600_000, "freed \(report.freed) of \(item.bytes): \(report.failures)")
        #expect(home.exists("Library/Caches/FakeBrew/current--2.0.tar.gz"))
        #expect(home.exists("Cellar/thing/2.0/bin/thing"))
    }

    @Test func dryRunParsing() throws {
        let home = try FakeHome()
        try home.file("a b/old (copy).tar.gz")
        try home.file("Cellar/x/1.0/bin/x")
        let base = home.url.path(percentEncoded: false).trimmingSuffix("/")
        let output = """
            Would remove: \(base)/a b/old (copy).tar.gz (4KB)
            Would remove: \(base)/Cellar/x/1.0 (1 file, 4KB)
            Would remove: \(base)/Cellar/x/1.0/bin (1 file, 4KB)
            Would remove: \(base)/Cellar/../a b (4KB)
            Would remove: relative/path (1KB)
            Would remove: \(base)/missing (1KB)
            Pruned 3 symbolic links from /opt/homebrew
            """
        #expect(Sweeper.dryRunPaths(output).map(\.lastPathComponent).sorted() == ["1.0", "old (copy).tar.gz"])
    }

    @Test func sweepNeverDeletesFilesForAnOwnerCommand() throws {
        let home = try FakeHome()
        try makeCache(home)
        let tool = try pruningTool(home)
        let rule = tool.rule(home)
        let cache = home.dir(".cache/fake")
        #expect(!Safety.allows(cache.appending(path: "unused"), rule: rule, home: home.url))
        #expect(Safety.allowsCommand(tool.url, cache: cache, rule: rule, home: home.url))

        // The same tool anywhere else, or another tool, is refused.
        let elsewhere = try home.file("other/bin/\(tool.name)")
        try home.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: elsewhere.path)
        #expect(!Safety.allowsCommand(elsewhere, cache: cache, rule: rule, home: home.url))
        #expect(!Safety.allowsCommand(URL(filePath: "/bin/rm"), cache: cache, rule: rule, home: home.url))
        #expect(!Safety.allowsCommand(tool.url, cache: home.url, rule: rule, home: home.url))
    }

    @Test func fakeHomeNeverReachesRealTools() throws {
        let home = try FakeHome()
        let dirs = Rule.toolDirs(home: home.url)
        #expect(dirs.allSatisfy { $0.path.hasPrefix(home.url.path) })
        let real = Rule.toolDirs(home: FileManager.default.homeDirectoryForCurrentUser)
        #expect(real.contains { $0.path == "/opt/homebrew/bin" })
        #expect(real.contains { $0.path == "/usr/local/bin" })
    }
}

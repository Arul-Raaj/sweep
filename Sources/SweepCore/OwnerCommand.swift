import Foundation

/// A cache that its own tool must clean (`uv cache prune`, `pnpm store prune`,
/// `brew cleanup`). Their documentation says not to delete these files by hand, so
/// Sweep never does: it measures the cache, runs the tool's command, and measures again.
public struct OwnerCommand: Sendable {
    /// The executable's file name, e.g. "uv".
    public var tool: String
    /// Folders the tool may be installed in, in order. Absolute paths only: the weekly
    /// job runs with launchd's minimal PATH, and nothing is ever looked up on PATH.
    public var searchDirs: [URL]
    /// Arguments that print the cache folder, e.g. `cache dir`.
    public var locate: [String]
    /// Arguments that clean, e.g. `cache prune`.
    public var clean: [String]
    /// Arguments that list what `clean` would remove, as "Would remove: <path> (size)"
    /// lines (`brew cleanup -n`). Without a preview the whole cache folder is measured,
    /// and the tool may free less than that.
    public var preview: [String]?
    /// Process names that mean the tool is at work, so cleaning waits.
    public var processNames: [String]
    /// Extra environment for every call, e.g. to stop Homebrew from updating itself.
    public var environment: [String: String]
    /// How long cleaning may take before the tool is stopped. Questions get at most two minutes.
    public var timeout: TimeInterval

    public init(tool: String, searchDirs: [URL], locate: [String], clean: [String], preview: [String]? = nil,
                processNames: [String]? = nil, environment: [String: String] = [:], timeout: TimeInterval = 600) {
        self.tool = tool
        self.searchDirs = searchDirs
        self.locate = locate
        self.clean = clean
        self.preview = preview
        self.processNames = processNames ?? [tool]
        self.environment = environment
        self.timeout = timeout
    }

    /// The command as you'd type it: "uv cache prune".
    public var display: String { ([tool] + clean).joined(separator: " ") }

    /// True when the size shown is the whole cache, of which the tool removes only part.
    public var measuresWholeCache: Bool { preview == nil }

    var queryTimeout: TimeInterval { min(timeout, 120) }

    /// The first installed copy of the tool in `searchDirs`, or nil.
    public func find() -> URL? {
        searchDirs.lazy
            .map { $0.appending(path: tool) }
            .first { Safety.isToolExecutable($0) }
    }
}

public extension Rule {
    /// Where Sweep looks for tools. For your own home, the standard install folders;
    /// for any other folder (a demo home, a test), the same folders *inside* it, so
    /// trying Sweep on a fake home can never run a real tool on your real caches.
    static func toolDirs(home: URL) -> [URL] {
        let real = FileManager.default.homeDirectoryForCurrentUser
        let isReal = home.standardizedFileURL.resolvingSymlinksInPath().path == real.standardizedFileURL.resolvingSymlinksInPath().path
        let root = isReal ? URL(filePath: "/", directoryHint: .isDirectory) : home
        return [
            root.appending(path: "opt/homebrew/bin", directoryHint: .isDirectory),
            root.appending(path: "usr/local/bin", directoryHint: .isDirectory),
            home.appending(path: ".local/bin", directoryHint: .isDirectory),
            home.appending(path: "Library/pnpm", directoryHint: .isDirectory),   // pnpm's own installer
        ]
    }
}

// MARK: - Scan and clean

extension Sweeper {
    static func scanOwnerCommand(_ rule: Rule, _ cmd: OwnerCommand, home: URL, now: Date, openFiles: OpenFiles?) -> Finding? {
        guard let tool = cmd.find() else { return nil }   // not installed: no category at all
        if let busy = toolBusy(cmd) { return Finding(rule: rule, items: [], note: busy) }

        guard let located = OwnerTool.run(tool, cmd.locate, cmd: cmd, home: home, timeout: cmd.queryTimeout),
              located.status == 0
        else { return Finding(rule: rule, items: [], note: "\(cmd.tool) didn't say where its cache is, so nothing will be cleaned.") }
        guard let cache = cacheFolder(located.text, home: home) else {
            return Finding(rule: rule, items: [], note: "\(cmd.tool)'s cache isn't inside your home folder, so Sweep leaves it alone.")
        }
        if openFiles?.anyOpen(inside: cache) == true {
            return Finding(rule: rule, items: [], note: "\(cmd.tool) is using its cache right now. Sweep will check again next time.")
        }

        var parts: [URL] = []
        if let preview = cmd.preview {
            guard let listed = OwnerTool.run(tool, preview, cmd: cmd, home: home, timeout: cmd.queryTimeout),
                  listed.status == 0
            else { return Finding(rule: rule, items: [], note: "\(cmd.tool) couldn't list what it would remove, so nothing will be cleaned.") }
            parts = dryRunPaths(listed.text)
            guard !parts.isEmpty else { return Finding(rule: rule, items: []) }
        }

        let item = Item(url: cache, bytes: 0, parts: parts)
        let usage = item.targets.map(measure)
        let bytes = usage.reduce(0) { $0 + $1.bytes }
        guard bytes > 0 else { return Finding(rule: rule, items: []) }
        let newest = usage.map(\.newest).max() ?? .distantPast
        let blocked = now.timeIntervalSince(newest) < settleTime ? "Changed in the last few minutes. Try again later." : nil
        return Finding(rule: rule, items: [Item(url: cache, bytes: bytes, lastUsed: cmd.preview == nil ? newest : nil,
                                                parts: parts, blocked: blocked)])
    }

    static func cleanOwnerCommand(_ item: Item, rule: Rule, _ cmd: OwnerCommand, home: URL, now: Date,
                                  openFiles: OpenFiles?, into report: inout CleanReport) {
        guard let tool = cmd.find(), Safety.allowsCommand(tool, cache: item.url, rule: rule, home: home) else {
            report.failures.append((item.url.path(percentEncoded: false), "blocked by safety check"))
            return
        }
        guard let before = ownerCommandReady(item, cmd, now: now, openFiles: openFiles) else {
            report.kept += 1
            return
        }

        let result = OwnerTool.run(tool, cmd.clean, cmd: cmd, home: home, timeout: cmd.timeout)
        // Whatever happened, report only what the tool really freed.
        let after = item.targets.reduce(0) { $0 + measure($1).bytes }
        report.freed += max(0, before - after)

        let path = item.url.path(percentEncoded: false)
        guard let result else {
            report.failures.append((path, "\(cmd.display) didn't finish in time and was stopped"))
            return
        }
        guard result.status == 0 else {
            let detail = result.text.split(separator: "\n").last.map { ": \($0)" } ?? ""
            report.failures.append((path, "\(cmd.display) failed (exit \(result.status))\(detail)"))
            return
        }
        report.removed += 1
        report.ran.append(item.url)
    }

    /// The item's size right before cleaning, or nil if the tool is busy or the cache
    /// is being written to.
    static func ownerCommandReady(_ item: Item, _ cmd: OwnerCommand, now: Date, openFiles: OpenFiles?) -> Int64? {
        if toolBusy(cmd) != nil || openFiles?.anyOpen(inside: item.url) == true { return nil }
        let usage = item.targets.map(measure)
        let newest = usage.map(\.newest).max() ?? .distantPast
        guard now.timeIntervalSince(newest) >= settleTime else { return nil }
        return usage.reduce(0) { $0 + $1.bytes }
    }

    /// Why the tool can't be cleaned right now (it's running), or nil.
    /// If Sweep can't tell, it assumes the tool is busy.
    static func toolBusy(_ cmd: OwnerCommand) -> String? {
        let names = cmd.processNames.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // The name as a whole word at the start of an argument, optionally with an
        // extension (pnpm.cjs, brew.rb), so "/opt/homebrew/bin/uv sync" counts.
        let pattern = "(^|/)(\(names))(\\.[A-Za-z]+)?( |$)"
        let pgrep = OwnerTool.spawn(URL(filePath: "/usr/bin/pgrep"), ["-U", String(getuid()), "-f", pattern],
                                    environment: ["PATH": "/usr/bin:/bin"], directory: URL(filePath: "/"), timeout: 10)
        switch pgrep?.status {
        case 1: return nil
        case 0: return "\(cmd.tool) is running. Sweep will clean it when it's done."
        default: return "Sweep couldn't check whether \(cmd.tool) is running, so it waits."
        }
    }

    /// The folder a tool printed, if it's a real folder at least two levels inside home.
    static func cacheFolder(_ output: String, home: URL) -> URL? {
        guard let line = output.split(whereSeparator: \.isNewline).last?.trimmingCharacters(in: .whitespaces),
              line.hasPrefix("/"), !line.split(separator: "/").contains("..")
        else { return nil }
        let url = URL(filePath: line, directoryHint: .isDirectory).standardizedFileURL
        let real = url.resolvingSymlinksInPath()
        guard Safety.isRealDirectory(real), Safety.components(of: real.path(percentEncoded: false), below: home) >= 2 else { return nil }
        return url
    }

    /// Paths from "Would remove: /path (12 files, 3.4MB)" lines, without duplicates or
    /// paths inside another listed path. Missing paths are dropped.
    static func dryRunPaths(_ output: String) -> [URL] {
        let prefix = "Would remove: "
        var paths: [String] = []
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix(prefix) {
            var rest = line.dropFirst(prefix.count)
            if rest.hasSuffix(")"), let size = rest.range(of: " (", options: .backwards) {
                rest = rest[..<size.lowerBound]
            }
            let path = String(rest).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { continue }
            paths.append(path)
        }
        var kept: [String] = []
        for path in Set(paths).sorted() where !kept.contains(where: { path.hasPrefix($0 + "/") }) {
            let url = URL(filePath: path)
            if FileManager.default.fileExists(atPath: path) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                kept.append(path)
            }
        }
        return kept.map { URL(filePath: $0) }
    }
}

// MARK: - Running a tool

enum OwnerTool {
    struct Output {
        let status: Int32
        let text: String
    }

    /// Runs a tool with a clean environment: HOME, a PATH of its own folder and the
    /// system folders, no colour. Its working folder is home.
    static func run(_ tool: URL, _ args: [String], cmd: OwnerCommand, home: URL, timeout: TimeInterval) -> Output? {
        let dirs = [tool.deletingLastPathComponent()] + cmd.searchDirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].map { URL(filePath: $0) }
        let homePath = home.path(percentEncoded: false)
        var env = [
            "HOME": homePath.count > 1 && homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath,
            "PATH": dirs.map { $0.path(percentEncoded: false) }.joined(separator: ":"),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "NO_COLOR": "1",
            "TERM": "dumb",
            "LANG": "en_US.UTF-8",
        ]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = tmp }
        env.merge(cmd.environment) { _, new in new }
        return spawn(tool, args, environment: env, directory: home, timeout: timeout)
    }

    /// Runs `executable` in its own process group with stdin from /dev/null and
    /// stdout and stderr captured. Returns nil if it couldn't start or ran out of time;
    /// then the whole group (anything the tool started too) is stopped.
    static func spawn(_ executable: URL, _ args: [String], environment: [String: String], directory: URL,
                      timeout: TimeInterval) -> Output? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        let (readEnd, writeEnd) = (fds[0], fds[1])

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, 1)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path(percentEncoded: false))

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Own process group (so a timeout can stop everything), only fds 0–2 inherited,
        // and default signal handling (a parent that ignores SIGPIPE mustn't pass that on).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                              | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attr, 0)
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setsigmask(&attr, &none)

        let argv = ([executable.path(percentEncoded: false)] + args).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable.path(percentEncoded: false), &actions, &attr, argv, envp)
        close(writeEnd)
        guard spawned == 0 else { close(readEnd); return nil }
        defer { close(readEnd) }

        let deadline = Date.now.addingTimeInterval(timeout)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var status: Int32 = 0
        var exited = false
        var drainUntil: Date?

        // Read until the pipe closes. If the tool exits but something it started keeps
        // the pipe open, stop reading shortly after.
        while true {
            let now = Date.now
            if now >= deadline || (drainUntil.map { now >= $0 } ?? false) { break }
            if !exited, waitpid(pid, &status, WNOHANG) == pid {
                exited = true
                drainUntil = now.addingTimeInterval(1)
            }
            var poller = pollfd(fd: readEnd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 100)
            if ready < 0 { if errno == EINTR { continue } else { break } }
            if ready == 0 { continue }
            let count = read(readEnd, &buffer, buffer.count)
            if count > 0 {
                if output.count < 4_000_000 { output.append(buffer, count: count) }
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                break
            }
        }

        // Wait for the exit, within the time left.
        while !exited {
            let reaped = waitpid(pid, &status, WNOHANG)
            if reaped == pid { exited = true; break }
            if reaped < 0, errno != EINTR { break }
            if Date.now >= deadline { break }
            usleep(20_000)
        }
        guard exited else {
            stop(group: pid)
            return nil
        }
        // Low 7 bits: the signal that ended it, or 0 for a normal exit with the code above them.
        let signal = status & 0x7f
        let code = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return Output(status: code, text: String(decoding: output, as: UTF8.self))
    }

    /// Asks a process group to stop, then makes it.
    private static func stop(group pid: pid_t) {
        killpg(pid, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<100 {   // up to 2 seconds
            if waitpid(pid, &status, WNOHANG) == pid { break }
            usleep(20_000)
        }
        killpg(pid, SIGKILL)
        _ = waitpid(pid, &status, WNOHANG)
    }
}

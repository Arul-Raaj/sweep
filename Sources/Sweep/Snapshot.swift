#if DEBUG
import AppKit
import SwiftUI
import SweepCore

/// Developer tool, debug builds only: renders the window offscreen to a PNG so the UI can
/// be checked (and screenshots made) without screen access. Runs on a demo home only.
///
///   tools/make-demo-home.sh /tmp/sweep-demo
///   SWEEP_HOME=/tmp/sweep-demo .build/debug/Sweep snapshot out.png [category-id] [--select 1|2|3|category-id]... [--clean] [--light]
@MainActor
enum Snapshot {
    static func run(_ args: [String]) -> Int32 {
        guard Paths.isDemo, let out = args.first, out.hasSuffix(".png") else {
            print("usage: SWEEP_HOME=<demo home> Sweep snapshot <out.png> [category-id] [--select 1|2|3|category-id]... [--clean] [--light]")
            return 64
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let model = Model()
        // Offscreen there's no window chrome to draw the background, so draw it here.
        let host = NSHostingView(rootView: ContentView(model: model)
            .frame(width: 940, height: 620)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 940, height: 620)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: args.contains("--light") ? .aqua : .darkAqua)
        window.contentView = host

        // The view's own .task starts the scan; wait for it to finish.
        wait { model.phase == .ready && !model.findings.isEmpty }

        var rest = Array(args.dropFirst())
        while let arg = rest.first {
            rest.removeFirst()
            if arg == "--select", let value = rest.first {
                rest.removeFirst()
                if let n = Int(value), let level = Rule.Level(rawValue: n) {
                    model.set(level, on: true)
                } else if let finding = model.findings.first(where: { $0.id == value }) {
                    model.set(finding, on: true)
                }
            } else if arg == "--clean" {
                var finished = false
                Task { await model.clean(); finished = true }
                wait { finished }
            } else if !arg.hasPrefix("--") {
                model.route = .rule(arg)
            }
        }

        wait(seconds: 0.6)   // let transitions settle
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try png.write(to: URL(filePath: out))
            print("Wrote \(out)")
            return 0
        } catch {
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }

    private static func wait(until condition: () -> Bool = { false }, seconds: TimeInterval = 60) {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !condition(), Date.now < deadline {
            RunLoop.main.run(until: .now.addingTimeInterval(0.05))
        }
    }

    private static func wait(_ condition: () -> Bool) { wait(until: condition) }
}
#endif

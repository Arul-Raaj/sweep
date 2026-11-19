// Draws Sweep's app icon and writes App/AppIcon.icns (plus docs/icon.png).
// Run from the package folder: swift tools/make-icon.swift
//
// The mark: a storage ring, mostly cleared, with a sparkle where the sweep ends,
// on a continuous-curve (superellipse) tile like Apple's own icons.
import AppKit

/// Apple-style continuous corners: a superellipse |x|^n + |y|^n = 1 fitted to `rect`.
func squircle(_ rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = NSPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

/// A four-pointed sparkle centred on `center`: sharp tips, gently curved sides.
func sparkle(at center: NSPoint, radius r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let tips = (0..<4).map { i -> NSPoint in
        let angle = CGFloat(i) * .pi / 2 + .pi / 2
        return NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    }
    path.move(to: tips[0])
    for i in 1...4 {
        let from = tips[i - 1], to = tips[i % 4]
        // Pull each side towards the centre: a concave curve between two tips.
        let pull: CGFloat = 0.62
        let control = NSPoint(x: (from.x + to.x) / 2 + (center.x - (from.x + to.x) / 2) * pull,
                              y: (from.y + to.y) / 2 + (center.y - (from.y + to.y) / 2) * pull)
        path.curve(to: to, controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS icon grid: an 824/1024 tile centred in the canvas.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = squircle(tile)

    NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.47, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.78, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // Soft light from the top edge.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The storage ring: a faint full track, and the part still "used" in solid white.
    let center = NSPoint(x: tile.midX, y: tile.midY - tile.height * 0.01)
    let radius = tile.width * 0.27
    let width = tile.width * 0.085

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor.white.withAlphaComponent(0.22).setStroke()
    track.stroke()

    // Used space: from 12 o'clock clockwise to about 4 o'clock (a third of the disk).
    let start: CGFloat = 90, end: CGFloat = -30
    let used = NSBezierPath()
    used.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    used.lineWidth = width
    used.lineCapStyle = .round
    NSColor.white.setStroke()
    used.stroke()

    // The sweep's sparkle, just past the end of the used arc, and a smaller companion.
    func onRing(_ degrees: CGFloat, _ r: CGFloat) -> NSPoint {
        NSPoint(x: center.x + cos(degrees * .pi / 180) * r, y: center.y + sin(degrees * .pi / 180) * r)
    }
    NSColor.white.setFill()
    sparkle(at: onRing(-62, radius), radius: tile.width * 0.13).fill()
    sparkle(at: onRing(-100, radius * 1.03), radius: tile.width * 0.06).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try! render(256).write(to: URL(filePath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "App/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote App/AppIcon.icns and docs/icon.png" : "iconutil failed")

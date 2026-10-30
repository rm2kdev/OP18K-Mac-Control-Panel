// Draws the OP1 Control app icon and writes Resources/AppIcon.icns.
// Drawn in code because the Command Line Tools have no actool for Icon Composer files.
//
// Usage: swift tools/make_icon.swift <repo root>
import AppKit

let root = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")
let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    // macOS icon grid: an 824 pt squircle centered on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Deep blue to violet background.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(colorSpace: space, components: [0.33, 0.20, 0.95, 1])!,
        CGColor(colorSpace: space, components: [0.10, 0.45, 1.00, 1])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])

    // Polling rings: concentric arcs radiating from the mouse.
    let center = CGPoint(x: 512, y: 470)
    for (i, radius) in [250.0, 330.0, 410.0, 490.0].enumerated() {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22 - Double(i) * 0.045).cgColor)
        ctx.setLineWidth(18)
        ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: false)
        ctx.strokePath()
    }

    // Top highlight.
    let shine = CGGradient(colorsSpace: space, colors: [
        CGColor(colorSpace: space, components: [1, 1, 1, 0.22])!,
        CGColor(colorSpace: space, components: [1, 1, 1, 0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // The mouse: a white symmetric shell with a split for the two buttons and a wheel.
    let mouse = CGRect(x: 512 - 150, y: 210, width: 300, height: 440)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    ctx.addPath(CGPath(roundedRect: mouse, cornerWidth: 150, cornerHeight: 150, transform: nil))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    let ink = CGColor(colorSpace: space, components: [0.22, 0.30, 0.85, 1])!
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 512, y: 640))
    ctx.addLine(to: CGPoint(x: 512, y: 470))
    ctx.move(to: CGPoint(x: 372, y: 470))
    ctx.addQuadCurve(to: CGPoint(x: 652, y: 470), control: CGPoint(x: 512, y: 440))
    ctx.strokePath()
    let wheel = CGRect(x: 512 - 20, y: 530, width: 40, height: 80)
    ctx.addPath(CGPath(roundedRect: wheel, cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(ink)
    ctx.fillPath()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let resources = root.appending(path: "Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try png(size: 1024).write(to: root.appending(path: "docs/images/icon.png"))
let task = Process()
task.executableURL = URL(filePath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print("wrote Resources/AppIcon.icns and docs/images/icon.png")

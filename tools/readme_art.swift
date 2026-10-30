// Turns window snapshots into the README images in docs/images.
// Crops off the title bar (it does not render off screen), rounds the corners,
// adds a shadow, and lays light and dark windows on the icon's gradient.
//
// Usage: OP1Control --snapshot <dir>; swift tools/readme_art.swift <dir> <repo root>
import AppKit

let args = CommandLine.arguments
let shots = URL(filePath: args[1])
let out = URL(filePath: args[2]).appending(path: "docs/images")
let titleBar: CGFloat = 104 // pixels at 2x
let radius: CGFloat = 44

func load(_ name: String) -> CGImage {
    let image = NSImage(contentsOf: shots.appending(path: "\(name).png"))!
    var rect = CGRect(origin: .zero, size: image.size)
    let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    return cg.cropping(to: CGRect(x: 0, y: Int(titleBar), width: cg.width, height: cg.height - Int(titleBar)))!
}

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
    print("wrote docs/images/\(name)")
}

/// Draws a window image with rounded corners, a hairline border and a soft shadow.
func drawWindow(_ image: CGImage, at origin: CGPoint, in ctx: CGContext, dark: Bool) {
    let rect = CGRect(origin: origin, size: CGSize(width: image.width, height: image.height))
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: dark ? 0.12 : 0.97, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.18 : 0.12))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func gradient(_ ctx: CGContext, _ w: Int, _ h: Int) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let g = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.33, green: 0.20, blue: 0.95, alpha: 1),
        CGColor(red: 0.10, green: 0.45, blue: 1.00, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
}

// Hero: the light and dark windows side by side, the dark one raised.
let light = load("main-light"), dark = load("split-dark")
let pad = 120, gap = 80
let w = light.width + dark.width + gap + pad * 2
let h = max(light.height, dark.height) + pad * 2 + 60
let hero = context(w, h)
gradient(hero, w, h)
drawWindow(dark, at: CGPoint(x: pad + light.width + gap, y: h - pad - dark.height), in: hero, dark: true)
drawWindow(light, at: CGPoint(x: pad, y: h - pad - 60 - light.height), in: hero, dark: false)
save(hero, "hero.png")

// One framed image per state, on a transparent background.
for name in ["main-light", "main-dark", "split-dark", "saved-light", "not-connected-light", "no-permission-dark"] {
    let image = load(name)
    let m = 80
    let ctx = context(image.width + m * 2, image.height + m * 2)
    drawWindow(image, at: CGPoint(x: m, y: m), in: ctx, dark: name.hasSuffix("dark"))
    save(ctx, "\(name).png")
}

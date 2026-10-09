import AppKit

// Draws the app icon (folder + sparkle on warm squircle) -> AppIcon.iconset PNGs. Run via build-icon.sh.
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

// squircle plate (macOS icon grid: 824pt in 1024 canvas)
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
color(0xF0603A).setFill(); platePath.fill()
ctx.restoreGState()
ctx.saveGState()
platePath.addClip()
NSGradient(starting: color(0xFFB36B), ending: color(0xEE5A3C))!.draw(in: plate, angle: -90)
// soft top highlight
NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
ctx.restoreGState()

// folder
let fx: CGFloat = 512 - 270, fy: CGFloat = 330, fw: CGFloat = 540, fh: CGFloat = 340
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.22).cgColor)
// back panel with tab
let back = NSBezierPath()
back.append(NSBezierPath(roundedRect: NSRect(x: fx, y: fy + 20, width: fw, height: fh - 10), xRadius: 40, yRadius: 40))
back.append(NSBezierPath(roundedRect: NSRect(x: fx, y: fy + fh - 40, width: 210, height: 80), xRadius: 34, yRadius: 34))
NSColor.white.withAlphaComponent(0.62).setFill(); back.fill()
ctx.restoreGState()
// front panel
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.18).cgColor)
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: fx, y: fy - 10, width: fw, height: fh - 70), xRadius: 40, yRadius: 40).fill()
ctx.restoreGState()

// sparkle (4-point star), top right of folder
func star(_ c: CGPoint, _ r: CGFloat, _ fill: NSColor) {
    let k = r * 0.13
    let p = NSBezierPath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint1: CGPoint(x: c.x + k, y: c.y + k), controlPoint2: CGPoint(x: c.x + k, y: c.y + k))
    p.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint1: CGPoint(x: c.x + k, y: c.y - k), controlPoint2: CGPoint(x: c.x + k, y: c.y - k))
    p.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint1: CGPoint(x: c.x - k, y: c.y - k), controlPoint2: CGPoint(x: c.x - k, y: c.y - k))
    p.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint1: CGPoint(x: c.x - k, y: c.y + k), controlPoint2: CGPoint(x: c.x - k, y: c.y + k))
    fill.setFill(); p.fill()
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
star(CGPoint(x: 700, y: 640), 120, color(0xFFD23F))
ctx.restoreGState()
star(CGPoint(x: 800, y: 760), 46, NSColor.white)
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let master = NSImage(size: NSSize(width: S, height: S)); master.addRepresentation(rep)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    NSGraphicsContext.current!.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}

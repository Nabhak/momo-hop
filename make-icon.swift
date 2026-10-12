// Momo Hop: one-click project launcher for macOS.
// Copyright (C) 2026 Nabhak <https://github.com/Nabhak/momo-hop>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see the
// GNU General Public License (LICENSE) for details. Derivative works must keep this notice.

import AppKit

// Builds AppIcon.iconset PNGs from assets/logo-source.png (the logo art) placed on the macOS icon grid
// (824pt squircle plate in a 1024 canvas, soft shadow).
// Usage: swift make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o AppIcon.icns
let S: CGFloat = 1024
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
guard let logo = NSImage(contentsOf: here.appendingPathComponent("assets/logo-source.png")) else {
    fatalError("assets/logo-source.png not found")
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
let ctx = NSGraphicsContext.current!.cgContext

let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
NSColor(red: 1, green: 0.45, blue: 0.02, alpha: 1).setFill(); platePath.fill()
ctx.restoreGState()
ctx.saveGState()
platePath.addClip()
logo.draw(in: plate, from: .zero, operation: .sourceOver, fraction: 1)
ctx.restoreGState()
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

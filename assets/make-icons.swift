#!/usr/bin/env swift
// Regenerates the PWA icons in ../icons: a starfield streaking out from the center on black.
// Usage (macOS): swift assets/make-icons.swift
import AppKit

func render(size: Int, safe: CGFloat, path: String) {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setLineCap(.round)

    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return CGFloat(seed >> 11) / CGFloat(1 << 53)
    }
    let c = s / 2, reach = s / 2 * safe       // `safe` keeps content inside the maskable safe zone
    for _ in 0..<70 {
        let a = rnd() * 2 * .pi
        let t = 0.12 + rnd() * 0.88            // distance from center, 0..1
        let len = 0.05 + t * 0.22
        let r0 = t * reach, r1 = min(reach, (t + len) * reach)
        let v = 0.35 + 0.65 * t
        ctx.setStrokeColor(CGColor(red: v, green: v, blue: v, alpha: 1))
        ctx.setLineWidth(s * (0.004 + 0.016 * t))
        ctx.move(to: CGPoint(x: c + cos(a) * r0, y: c + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: c + cos(a) * r1, y: c + sin(a) * r1))
        ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("../icons").standardized.path
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
render(size: 180, safe: 1.0, path: "\(dir)/apple-touch-icon.png")
render(size: 192, safe: 1.0, path: "\(dir)/icon-192.png")
render(size: 512, safe: 1.0, path: "\(dir)/icon-512.png")
render(size: 512, safe: 0.8, path: "\(dir)/icon-maskable-512.png")
print("Wrote icons to \(dir)")

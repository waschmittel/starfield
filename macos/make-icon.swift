// Renders Resources/AppIcon.icns: a starfield in a macOS-style rounded square (needs iconutil).
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Apple's icon grid: the shape fills 80% of the canvas, with a soft drop shadow in the margin.
    let body = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = CGPath(roundedRect: body, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.5))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.clip()
    var seed: UInt64 = 0x9E3779B97F4A7C15   // fixed seed: reproducible output
    func rnd() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return CGFloat(seed >> 11) / CGFloat(1 << 53)
    }
    let c = s / 2, reach = s * 0.4 * 1.42   // reaches the corners
    ctx.setLineCap(.round)
    for _ in 0..<110 {
        let a = rnd() * 2 * .pi
        let t = 0.06 + rnd() * 0.94
        let r0 = t * reach, r1 = min(reach, (t + 0.04 + t * 0.2) * reach)
        let v = 0.4 + 0.6 * t
        ctx.setStrokeColor(CGColor(gray: v, alpha: 1))
        ctx.setLineWidth(s * (0.003 + 0.014 * t))
        ctx.move(to: CGPoint(x: c + cos(a) * r0, y: c + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: c + cos(a) * r1, y: c + sin(a) * r1))
        ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: set)
exit(iconutil.terminationStatus)

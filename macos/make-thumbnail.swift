// Renders Resources/thumbnail.png (+ @2x): a small starfield for the Screen Saver settings list.
import AppKit

func render(width: Int, height: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    var rng = SystemRandomNumberGenerator()
    let cx = Double(width) / 2, cy = Double(height) / 2
    let scale = Double(width) / 180
    ctx.setLineCap(.round)
    for _ in 0..<500 {
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let t = pow(Double.random(in: 0...1, using: &rng), 1.3)   // bias toward center
        let r0 = t * Double(width) * 0.55
        let r1 = r0 + (0.4 + 3.5 * t * t) * scale
        let v = 0.35 + 0.65 * t
        ctx.setStrokeColor(CGColor(gray: v, alpha: 1))
        ctx.setLineWidth((0.5 + 1.6 * t * t) * scale)
        ctx.move(to: CGPoint(x: cx + cos(angle) * r0, y: cy + sin(angle) * r0))
        ctx.addLine(to: CGPoint(x: cx + cos(angle) * r1, y: cy + sin(angle) * r1))
        ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(width: 90, height: 58, to: "Resources/thumbnail.png")
render(width: 180, height: 116, to: "Resources/thumbnail@2x.png")

// Renders a seamlessly looping starfield as PNG frames for the README animation.
// Usage: render-frames <fps> <outDir>
// Same projection, brightness buckets, line widths, speed and trail as the macOS saver defaults, but
// with 2400 stars (twice the default, for a denser picture) at fixed positions that wrap in z, so the
// last frame flows straight into the first.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fps = Double(CommandLine.arguments[1])!
let outDir = CommandLine.arguments[2]

let width = 800, height = 450, pixelScale = 2          // render at 2x, downscale when encoding
let starCount = 2400, buckets = 8, spread: Float = 2000
let speed: Float = 6, trailLength: Float = 0.4         // saver defaults; speed is z units per 1/60 s

let dz = speed * 60 / Float(fps)                        // z units per frame
let frames = Int((1000 / dz).rounded())                 // one full pass through the depth range
let range = dz * Float(frames)                          // exact travel per loop => seamless

var rng = SystemRandomNumberGenerator()
struct Seeded: RandomNumberGenerator {                  // fixed seed: reproducible output
    var s: UInt64 = 0x9E3779B97F4A7C15
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
}
var seeded = Seeded()
let xs = (0..<starCount).map { _ in (Float.random(in: 0..<1, using: &seeded) - 0.5) * spread }
let ys = (0..<starCount).map { _ in (Float.random(in: 0..<1, using: &seeded) - 0.5) * spread }
let phase = (0..<starCount).map { _ in Float.random(in: 0..<range, using: &seeded) }

let w = width * pixelScale, h = height * pixelScale
let colorSpace = CGColorSpaceCreateDeviceRGB()
let focal = Float(max(width, height)) * 0.5
let cx = Float(width) / 2, cy = Float(height) / 2
let grays: [CGColor] = (0..<buckets).map { b in
    CGColor(gray: CGFloat(70 + 185 * Double(b) / Double(buckets - 1)) / 255, alpha: 1)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for f in 0..<frames {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixelScale), y: CGFloat(pixelScale))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setLineCap(.round)

    var lines = [[CGPoint]](repeating: [], count: buckets)
    for i in 0..<starCount {
        let z = range - (phase[i] + Float(f) * dz).truncatingRemainder(dividingBy: range)
        if z < 1 { continue }
        let k = focal / z, kp = focal / (z + speed * trailLength)
        let sx = cx + xs[i] * k, sy = cy + ys[i] * k
        if sx < -50 || sx > Float(width) + 50 || sy < -50 || sy > Float(height) + 50 { continue }
        let t = 1 - z / range
        let b = min(buckets - 1, max(0, Int(t * Float(buckets))))
        lines[b].append(CGPoint(x: CGFloat(cx + xs[i] * kp), y: CGFloat(cy + ys[i] * kp)))
        lines[b].append(CGPoint(x: CGFloat(sx), y: CGFloat(sy)))
    }
    for b in 0..<buckets where !lines[b].isEmpty {
        ctx.setStrokeColor(grays[b])
        ctx.setLineWidth(CGFloat(0.6 + Float(b) / Float(buckets - 1) * 2.4))
        for j in stride(from: 0, to: lines[b].count, by: 2) {
            ctx.move(to: lines[b][j]); ctx.addLine(to: lines[b][j + 1])
        }
        ctx.strokePath()
    }

    let url = URL(fileURLWithPath: String(format: "%@/f%04d.png", outDir, f)) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
print(frames)

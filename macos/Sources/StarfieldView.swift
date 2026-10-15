import AppKit
import ScreenSaver

/// Native Core Graphics port of starfield.html. A web view can't be used here: the screensaver
/// host reports it as hidden, so WebKit suspends it and the saver goes black.
@objc(StarfieldView)
final class StarfieldView: ScreenSaverView {
    private enum Key {
        static let speed = "speed"
        static let trailLength = "trailLength"
        static let starCount = "starCount"
    }
    private static let defaultSettings: [String: Any] = [
        Key.speed: 6.0, Key.trailLength: 0.4, Key.starCount: 1200,
    ]
    private static let previewStarCount = 300

    private static let maxStars = 5000
    private static let depth: Float = 1000
    private static let near: Float = 1
    private static let spread: Float = 2000
    private static let buckets = 8

    private var speed: Float = 6
    private var trailLength: Float = 0.4
    private var starCount = 1200

    // Raw buffers: the per-frame loops are hot, and array bounds/uniqueness checks showed up as stutter.
    private let x = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let y = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let z = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    // Per-frame projected positions, grouped by brightness bucket.
    private let sx = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let sy = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let px = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let py = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let sz = UnsafeMutablePointer<Float>.allocate(capacity: maxStars)
    private let bucketIdx = UnsafeMutablePointer<Int32>.allocate(capacity: maxStars * buckets)
    private let bucketLen = UnsafeMutablePointer<Int>.allocate(capacity: buckets)

    deinit {
        for p in [x, y, z, sx, sy, px, py, sz] { p.deallocate() }
        bucketIdx.deallocate()
        bucketLen.deallocate()
    }

    private let colors: [CGColor] = (0..<buckets).map { b in
        let v = CGFloat(70 + 185 * Double(b) / Double(buckets - 1)) / 255
        return CGColor(gray: v, alpha: 1)
    }

    private var lastTick = CACurrentMediaTime()
    private var displayLink: AnyObject?   // CADisplayLink (macOS 14+)
    private var configSheet: ConfigSheet?

    private var defaults: ScreenSaverDefaults? {
        let id = Bundle(for: StarfieldView.self).bundleIdentifier ?? "starfield"
        let d = ScreenSaverDefaults(forModuleWithName: id)
        d?.register(defaults: Self.defaultSettings)
        return d
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        animationTimeInterval = 1.0 / 60.0
        for i in 0..<Self.maxStars { respawn(i, anywhere: true) }
        loadConfig()
    }

    private func respawn(_ i: Int, anywhere: Bool) {
        x[i] = (Float.random(in: 0..<1) - 0.5) * Self.spread
        y[i] = (Float.random(in: 0..<1) - 0.5) * Self.spread
        z[i] = anywhere ? Float.random(in: 0..<1) * Self.depth + Self.near : Self.depth
    }

    private func loadConfig() {
        guard let d = defaults else { return }
        speed = Float(min(60, max(0.5, d.double(forKey: Key.speed))))
        trailLength = Float(min(4, max(0, d.double(forKey: Key.trailLength))))
        let stars = min(Self.maxStars, max(50, d.integer(forKey: Key.starCount)))
        starCount = isPreview ? min(Self.previewStarCount, stars) : stars
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        guard let d = defaults else { return nil }
        let sheet = ConfigSheet(
            speed: d.double(forKey: Key.speed),
            trailLength: d.double(forKey: Key.trailLength),
            starCount: d.integer(forKey: Key.starCount)
        ) { [weak self] speed, trail, stars in
            d.set(speed, forKey: Key.speed)
            d.set(trail, forKey: Key.trailLength)
            d.set(stars, forKey: Key.starCount)
            d.synchronize()
            self?.loadConfig()
        }
        configSheet = sheet
        return sheet.window
    }

    override func startAnimation() {
        super.startAnimation()
        lastTick = CACurrentMediaTime()
        attachDisplayLink()
    }

    override func stopAnimation() {
        super.stopAnimation()
        detachDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isAnimating { attachDisplayLink() }
    }

    // A display link fires once per refresh of the screen the view is on (60/120/144 Hz, ProMotion),
    // which AppKit's fixed-interval timer can't match. Older macOS falls back to the timer.
    private func attachDisplayLink() {
        detachDisplayLink()
        guard #available(macOS 14.0, *), window != nil else { return }
        let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = CACurrentMediaTime()
    }

    private func detachDisplayLink() {
        if #available(macOS 14.0, *) { (displayLink as? CADisplayLink)?.invalidate() }
        displayLink = nil
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp)
    }

    override func animateOneFrame() {
        if displayLink == nil { advance(to: CACurrentMediaTime()) }
    }

    private func advance(to time: CFTimeInterval) {
        let dt = Float(min(4, max(0, (time - lastTick) * 60)))
        lastTick = time
        step(dt: dt)
        needsDisplay = true
    }

    private func step(dt: Float) {
        let w = Float(bounds.width), h = Float(bounds.height)
        let cx = w / 2, cy = h / 2
        let focal = max(w, h) * 0.5
        let stepZ = speed * dt
        let trailZ = speed * trailLength
        let buckets = Self.buckets

        for b in 0..<buckets { bucketLen[b] = 0 }
        for i in 0..<starCount {
            z[i] -= stepZ
            if z[i] < Self.near { respawn(i, anywhere: false); continue }

            let zi = z[i], k = focal / zi
            let sxi = cx + x[i] * k, syi = cy + y[i] * k
            if sxi < -50 || sxi > w + 50 || syi < -50 || syi > h + 50 { respawn(i, anywhere: false); continue }

            let kp = focal / (zi + trailZ)
            sx[i] = sxi; sy[i] = syi
            px[i] = cx + x[i] * kp; py[i] = cy + y[i] * kp

            let t = 1 - zi / Self.depth
            sz[i] = 0.6 + t * t * 2.6
            let b = min(buckets - 1, Int(t * Float(buckets)))
            bucketIdx[b * Self.maxStars + bucketLen[b]] = Int32(i)
            bucketLen[b] += 1
        }
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        ctx.setLineCap(.round)

        let buckets = Self.buckets
        for b in 0..<buckets {
            let n = bucketLen[b]
            if n == 0 { continue }
            if trailLength > 0 {
                ctx.setStrokeColor(colors[b])
                ctx.setLineWidth(CGFloat(0.6 + Float(b) / Float(buckets - 1) * 2.4))
                for j in 0..<n {
                    let i = Int(bucketIdx[b * Self.maxStars + j])
                    ctx.move(to: CGPoint(x: CGFloat(px[i]), y: CGFloat(py[i])))
                    ctx.addLine(to: CGPoint(x: CGFloat(sx[i]), y: CGFloat(sy[i])))
                }
                ctx.strokePath()
            } else {
                ctx.setFillColor(colors[b])
                for j in 0..<n {
                    let i = Int(bucketIdx[b * Self.maxStars + j])
                    let s = CGFloat(sz[i])
                    ctx.fill(CGRect(x: CGFloat(sx[i]) - s / 2, y: CGFloat(sy[i]) - s / 2, width: s, height: s))
                }
            }
        }
    }
}

/// Modal settings sheet: three sliders with live value labels.
final class ConfigSheet: NSObject {
    let window: NSWindow
    private let speed = NSSlider(value: 6, minValue: 0.5, maxValue: 30, target: nil, action: nil)
    private let trail = NSSlider(value: 0.4, minValue: 0, maxValue: 4, target: nil, action: nil)
    private let stars = NSSlider(value: 1200, minValue: 50, maxValue: 5000, target: nil, action: nil)
    private let labels = [NSTextField(labelWithString: ""), NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let onSave: (Double, Double, Int) -> Void

    init(speed s: Double, trailLength t: Double, starCount c: Int, onSave: @escaping (Double, Double, Int) -> Void) {
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        speed.doubleValue = s
        trail.doubleValue = t
        stars.integerValue = c
        for slider in [speed, trail, stars] {
            slider.target = self
            slider.action = #selector(changed)
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Speed"), speed, labels[0]],
            [NSTextField(labelWithString: "Trail length"), trail, labels[1]],
            [NSTextField(labelWithString: "Star density"), stars, labels[2]],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).width = 50

        let ok = NSButton(title: "OK", target: self, action: #selector(save))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, ok])
        buttons.spacing = 8

        let root = NSStackView(views: [grid, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = root
        changed()
    }

    @objc private func changed() {
        labels[0].stringValue = String(format: "%.1f", speed.doubleValue)
        labels[1].stringValue = String(format: "%.1f", (trail.doubleValue * 10).rounded() / 10)
        labels[2].stringValue = "\(stars.integerValue)"
    }

    @objc private func save() {
        onSave(speed.doubleValue, (trail.doubleValue * 10).rounded() / 10, stars.integerValue)
        close()
    }

    @objc private func cancelTapped() { close() }

    private func close() {
        window.sheetParent?.endSheet(window)
    }
}

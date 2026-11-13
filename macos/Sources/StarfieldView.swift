// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenSaver

/// Native port of starfield.html, drawn by `MetalRenderer`. A web view can't be used here: the screensaver
/// host reports it as hidden, so WebKit suspends it and the saver goes black.
@objc(StarfieldView)
final class StarfieldView: ScreenSaverView {
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

    private static let willStop = Notification.Name("com.apple.screensaver.willstop")
    private var willStopObserver: NSObjectProtocol?

    deinit {
        detachDisplayLink()
        if let willStopObserver { DistributedNotificationCenter.default().removeObserver(willStopObserver) }
        for p in [x, y, z, sx, sy, px, py, sz] { p.deallocate() }
        bucketIdx.deallocate()
        bucketLen.deallocate()
    }

    private var metal: MetalRenderer?
    private var messageLayer: CATextLayer?   // shown instead of the stars when Metal is unavailable
    private var lastTick = CACurrentMediaTime()
    private var displayLink: CAMetalDisplayLink?
    private var configSheet: ConfigSheet?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        if !isPreview { observeWillStop() }
        for i in 0..<Self.maxStars { respawn(i, anywhere: true) }
        loadConfig()
        installLayer()
    }

    /// Layer-hosting view with the renderer's own Metal layer, so AppKit doesn't manage its backing
    /// scale. Without Metal (e.g. in some VMs) it shows a message instead; the reason is logged.
    private func installLayer() {
        if let m = MetalRenderer(capacity: Self.maxStars) {
            metal = m
            layer = m.layer
        } else {
            let root = CALayer()
            root.backgroundColor = CGColor(gray: 0, alpha: 1)
            let text = CATextLayer()
            text.string = "Starfield needs Metal, which is not available on this system."
            text.alignmentMode = .center
            text.fontSize = 16
            text.foregroundColor = CGColor(gray: 0.5, alpha: 1)
            root.addSublayer(text)
            messageLayer = text
            layer = root
        }
        wantsLayer = true   // after setting `layer`: that is what makes the view layer-hosting
    }

    override var isOpaque: Bool { true }

    private func layoutMessage() {
        guard let text = messageLayer else { return }
        let height = text.fontSize * 1.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        text.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        text.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    private func updateBackingScale() {
        layoutMessage()
        guard let metal, let w = window else { return }
        layer?.contentsScale = w.backingScaleFactor
        metal.resize(size: bounds.size, scale: w.backingScaleFactor)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateBackingScale()
    }

    private func respawn(_ i: Int, anywhere: Bool) {
        x[i] = (Float.random(in: 0..<1) - 0.5) * Self.spread
        y[i] = (Float.random(in: 0..<1) - 0.5) * Self.spread
        z[i] = anywhere ? Float.random(in: 0..<1) * Self.depth + Self.near : Self.depth
    }

    private func loadConfig() {
        guard let d = Settings.defaults() else { return }
        speed = Float(min(60, max(0.5, d.double(forKey: Settings.Key.speed))))
        trailLength = Float(min(4, max(0, d.double(forKey: Settings.Key.trailLength))))
        let stars = min(Self.maxStars, max(50, d.integer(forKey: Settings.Key.starCount)))
        starCount = isPreview ? min(Self.previewStarCount, stars) : stars
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let sheet = ConfigSheet(onSaved: { [weak self] in self?.loadConfig() }, onClose: { [weak self] in
            guard let w = self?.configSheet?.window else { return }
            w.sheetParent?.endSheet(w)
        })
        configSheet = sheet
        return sheet.window
    }

    override func startAnimation() {
        super.startAnimation()
        if metal == nil && messageLayer == nil { installLayer() }
        loadConfig()
        updateBackingScale()
        lastTick = CACurrentMediaTime()
        attachDisplayLink()
    }

    override func stopAnimation() {
        super.stopAnimation()
        releaseGPUResources()
    }

    /// `legacyScreenSaver` keeps stopped views alive (and often never calls `stopAnimation` outside the
    /// preview), so each one must give back its full-screen drawables itself or they pile up to GBs.
    private func releaseGPUResources() {
        detachDisplayLink()
        guard metal != nil else { return }
        metal = nil
        layer = CALayer()
    }

    private func observeWillStop() {
        willStopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.willStop, object: nil, queue: .main
        ) { [weak self] _ in self?.stopAnimation() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimation()
            return
        }
        updateBackingScale()
        if isAnimating { attachDisplayLink() }
    }

    // A display link fires once per refresh of the screen the view is on (60/120/144 Hz, ProMotion),
    // which AppKit's fixed-interval timer can't match.
    private func attachDisplayLink() {
        detachDisplayLink()
        guard let metal, window != nil else { return }
        let link = metal.makeDisplayLink { [weak self] update in
            self?.advance(to: update.targetPresentationTimestamp, drawable: update.drawable)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = CACurrentMediaTime()
    }

    private func detachDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func advance(to time: CFTimeInterval, drawable: CAMetalDrawable) {
        let dt = Float(min(4, max(0, (time - lastTick) * 60)))
        lastTick = time
        step(dt: dt)
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 1
        metal?.render(size: bounds.size, scale: scale, drawable: drawable) { fillInstances($0) }
    }

    /// Writes the visible stars as GPU instances (see `MetalRenderer`), dimmest bucket first so brighter
    /// stars end up on top.
    private func fillInstances(_ out: UnsafeMutablePointer<Float>) -> Int {
        let buckets = Self.buckets
        let hasTrail = trailLength > 0
        var n = 0
        for b in 0..<buckets {
            let f = Float(b) / Float(buckets - 1)
            let gray = (70 + 185 * f) / 255
            let trailRadius = (0.6 + f * 2.4) / 2
            for j in 0..<bucketLen[b] {
                let i = Int(bucketIdx[b * Self.maxStars + j])
                let o = out + n * MetalRenderer.floatsPerInstance
                o[0] = hasTrail ? px[i] : sx[i]
                o[1] = hasTrail ? py[i] : sy[i]
                o[2] = sx[i]
                o[3] = sy[i]
                o[4] = hasTrail ? trailRadius : sz[i] / 2
                o[5] = gray
                n += 1
            }
        }
        return n
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
}

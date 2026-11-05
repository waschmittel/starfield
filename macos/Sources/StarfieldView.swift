// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenSaver

/// Native port of starfield.html, drawn by `MetalRenderer`. A web view can't be used here: the screensaver
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

    private var metal: MetalRenderer?
    private var messageLayer: CATextLayer?   // shown instead of the stars when Metal is unavailable
    private var lastTick = CACurrentMediaTime()
    private var displayLink: CAMetalDisplayLink?
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
        // Layer-hosting view with the renderer's own Metal layer, so AppKit doesn't manage its backing
        // scale. Without Metal (e.g. in some VMs) it shows a message instead; the reason is logged.
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
        wantsLayer = true
        for i in 0..<Self.maxStars { respawn(i, anywhere: true) }
        loadConfig()
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
        updateBackingScale()
        lastTick = CACurrentMediaTime()
        attachDisplayLink()
    }

    override func stopAnimation() {
        super.stopAnimation()
        detachDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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

        let linkText = NSMutableAttributedString(string: "GPLv3 · Source code", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let range = (linkText.string as NSString).range(of: "Source code")
        linkText.addAttributes([
            .link: URL(string: "https://github.com/waschmittel/starfield")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: range)
        let licenseLabel = NSTextField(labelWithAttributedString: linkText)
        licenseLabel.allowsEditingTextAttributes = true
        licenseLabel.isSelectable = true

        let ok = NSButton(title: "OK", target: self, action: #selector(save))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [licenseLabel, spacer, cancel, ok])
        footer.spacing = 8
        footer.alignment = .centerY

        let root = NSStackView(views: [grid, footer])
        root.orientation = .vertical
        root.alignment = .width
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

// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenSaver

/// Settings shared by the saver view and its configuration sheet, for both the `.saver` and the app extension.
enum Settings {
    enum Key {
        static let speed = "speed"
        static let trailLength = "trailLength"
        static let starCount = "starCount"
    }
    private static let defaultValues: [String: Any] = [Key.speed: 6.0, Key.trailLength: 0.4, Key.starCount: 1200]

    /// Always re-synchronized: the sheet and the saver can run in different processes, and the Wallpaper agent
    /// keeps its extension process across sessions.
    static func defaults() -> ScreenSaverDefaults? {
        let id = Bundle(for: StarfieldView.self).bundleIdentifier ?? "starfield"
        let d = ScreenSaverDefaults(forModuleWithName: id)
        d?.register(defaults: defaultValues)
        d?.synchronize()
        return d
    }
}

/// Modal settings sheet: three sliders with live value labels.
final class ConfigSheet: NSObject {
    private(set) var view = NSView()
    /// Only used by the `.saver`; the app extension embeds `view` in a view controller instead.
    private(set) lazy var window: NSWindow = {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: view.frame.size), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = view
        return w
    }()
    private let speed = NSSlider(value: 6, minValue: 0.5, maxValue: 30, target: nil, action: nil)
    private let trail = NSSlider(value: 0.4, minValue: 0, maxValue: 4, target: nil, action: nil)
    private let stars = NSSlider(value: 1200, minValue: 50, maxValue: 5000, target: nil, action: nil)
    private let labels = [NSTextField(labelWithString: ""), NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let onSaved: () -> Void
    private let onClose: () -> Void

    /// `onSaved` runs after OK has stored the values; `onClose` ends the sheet (OK and Cancel).
    init(onSaved: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSaved = onSaved
        self.onClose = onClose
        super.init()
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
        view = root
        view.frame.size = NSSize(width: 380, height: 190)
        reload()
    }

    /// Shows the stored values.
    func reload() {
        guard let d = Settings.defaults() else { return }
        speed.doubleValue = d.double(forKey: Settings.Key.speed)
        trail.doubleValue = d.double(forKey: Settings.Key.trailLength)
        stars.integerValue = d.integer(forKey: Settings.Key.starCount)
        changed()
    }

    @objc private func changed() {
        labels[0].stringValue = String(format: "%.1f", speed.doubleValue)
        labels[1].stringValue = String(format: "%.1f", (trail.doubleValue * 10).rounded() / 10)
        labels[2].stringValue = "\(stars.integerValue)"
    }

    @objc private func save() {
        guard let d = Settings.defaults() else { return onClose() }
        d.set(speed.doubleValue, forKey: Settings.Key.speed)
        d.set((trail.doubleValue * 10).rounded() / 10, forKey: Settings.Key.trailLength)
        d.set(stars.integerValue, forKey: Settings.Key.starCount)
        d.synchronize()
        onSaved()
        onClose()
    }

    @objc private func cancelTapped() { onClose() }
}

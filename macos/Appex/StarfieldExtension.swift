// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenSaver

// App-extension (`.appex`) flavour of the saver. The classes are named in Appex/Info.plist; the view and the
// options UI are shared with the `.saver` (Sources/).

@objc(StarfieldExtension)
final class StarfieldExtension: ScreenSaverExtension {
    @objc override init() { super.init() }
}

@objc(StarfieldViewController)
final class StarfieldViewController: ScreenSaverViewController {
    /// The host sizes the view after attaching it and passes no preview flag, so: zero frame, autoresizing.
    override func loadView() {
        let v = StarfieldView(frame: .zero, isPreview: false)
        v?.autoresizingMask = [.width, .height]
        view = v ?? NSView()
    }
}

@objc(StarfieldConfigViewController)
final class StarfieldConfigViewController: ScreenSaverConfigurationViewController {
    private var sheet: ConfigSheet?

    override func loadView() {
        let sheet = ConfigSheet(onSaved: {}, onClose: { [weak self] in self?.configureSheetDidEnd() })
        self.sheet = sheet
        view = sheet.view
        preferredContentSize = sheet.view.frame.size
    }

    override func configureSheetWillPresent() {
        super.configureSheetWillPresent()
        sheet?.reload()
    }
}

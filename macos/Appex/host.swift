// SPDX-License-Identifier: GPL-3.0-or-later
// Host app: the app extension has to live inside an app. Opening it registers the extension with PlugInKit
// and says where to enable it.
import AppKit

let appex = Bundle.main.builtInPlugInsURL!.appendingPathComponent("Starfield.appex")
let pluginkit = Process()
pluginkit.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
pluginkit.arguments = ["-a", appex.path]
try? pluginkit.run()
pluginkit.waitUntilExit()

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate()
let alert = NSAlert()
alert.messageText = pluginkit.terminationStatus == 0 ? "Starfield is registered" : "Registering Starfield failed"
alert.informativeText = "Choose Starfield in System Settings > Wallpaper > Screen Saver (macOS 26) or "
    + "System Settings > Screen Saver (macOS 14 and 15)."
alert.runModal()

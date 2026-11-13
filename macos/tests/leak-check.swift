// SPDX-License-Identifier: GPL-3.0-or-later
// Regression check for the legacyScreenSaver leak: the host never deallocates stopped views, so each
// one must release its drawables on `willstop`/`stopAnimation`. Usage: leak-check <Starfield.saver>
import AppKit
import ScreenSaver

let views = 30
let limitMB = 500
guard CommandLine.arguments.count > 1, let bundle = Bundle(path: CommandLine.arguments[1]), bundle.load(),
      let saverClass = bundle.principalClass as? ScreenSaverView.Type else {
    fputs("usage: leak-check <Starfield.saver>\n", stderr)
    exit(2)
}
_ = NSApplication.shared

func footprintMB() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return Int(info.phys_footprint >> 20)
}
func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

var leaked: [ScreenSaverView] = []   // the host keeps stopped views alive, so do the same
let baseline = footprintMB()
for i in 0..<views {
    let window = NSWindow(contentRect: NSScreen.main!.frame, styleMask: .borderless, backing: .buffered, defer: false)
    let view = saverClass.init(frame: window.contentView!.bounds, isPreview: false)!
    window.contentView!.addSubview(view)
    window.orderFront(nil)
    view.startAnimation()
    spin(0.3)
    if i == 0 {   // a stopped view must be restartable
        view.stopAnimation()
        view.startAnimation()
        spin(0.3)
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.apple.screensaver.willstop"), object: nil, deliverImmediately: true)
    spin(0.2)
    view.removeFromSuperview()
    window.close()
    leaked.append(view)
}
spin(1)
let grown = footprintMB() - baseline
print("footprint grew \(grown) MB over \(views) leaked views (limit \(limitMB) MB)")
exit(grown < limitMB ? 0 : 1)

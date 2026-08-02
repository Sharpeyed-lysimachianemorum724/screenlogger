import AppKit
import QuartzCore

final class DemoBackdropDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            NSApp.terminate(nil)
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isOpaque = true
        window.level = .normal
        window.hasShadow = false

        let backdrop = NSView(frame: screen.frame)
        backdrop.wantsLayer = true

        let gradient = CAGradientLayer()
        gradient.frame = backdrop.bounds
        gradient.colors = [
            NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.115, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.125, green: 0.175, blue: 0.250, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.12, y: 0.92)
        gradient.endPoint = CGPoint(x: 0.88, y: 0.08)
        backdrop.layer = gradient

        window.contentView = backdrop
        window.orderFrontRegardless()
        self.window = window
    }
}

let application = NSApplication.shared
let delegate = DemoBackdropDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()

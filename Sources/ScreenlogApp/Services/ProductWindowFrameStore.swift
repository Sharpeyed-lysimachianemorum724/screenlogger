import AppKit
import ScreenlogCore

/// Persists product-window frames in Screenlogger's selected preference domain.
///
/// AppKit's frame autosave always targets the standard application domain,
/// bypassing the authenticated preference suite used by routed UI tests. This
/// store keeps production behavior native while making test window state truly
/// isolated. A one-time legacy read preserves frames saved by older builds.
@MainActor
enum ProductWindowFrameStore {
    static func restore(
        _ window: NSWindow,
        name: String,
        allowsLegacyAppKitMigration: Bool
    ) -> Bool {
        if let encoded = ScreenlogProcessPreferences.current.string(forKey: key(name)),
            let frame = validFrame(from: encoded)
        {
            apply(frame, to: window)
            return true
        }

        guard allowsLegacyAppKitMigration, window.setFrameUsingName(name) else {
            return false
        }
        save(window, name: name)
        return true
    }

    static func save(_ window: NSWindow, name: String) {
        let frame = window.frame
        guard frame.width.isFinite, frame.height.isFinite,
            frame.origin.x.isFinite, frame.origin.y.isFinite,
            frame.width > 0, frame.height > 0
        else { return }
        ScreenlogProcessPreferences.current.set(
            NSStringFromRect(frame),
            forKey: key(name)
        )
    }

    private static func key(_ name: String) -> String {
        "productWindowFrame.\(name)"
    }

    private static func validFrame(from encoded: String) -> NSRect? {
        let frame = NSRectFromString(encoded)
        guard frame.width.isFinite, frame.height.isFinite,
            frame.origin.x.isFinite, frame.origin.y.isFinite,
            frame.width > 0, frame.height > 0
        else { return nil }
        return frame
    }

    private static func apply(_ frame: NSRect, to window: NSWindow) {
        let screens = NSScreen.screens
        let bestScreen = screens.max { lhs, rhs in
            intersectionArea(frame, lhs.visibleFrame) < intersectionArea(frame, rhs.visibleFrame)
        }
        let targetScreen = bestScreen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? frame
        let constrained = window.constrainFrameRect(frame, to: targetScreen)

        // `constrainFrameRect` keeps the title bar reachable. Clamp an
        // oversized saved frame as well when a monitor has since disappeared
        // or changed resolution.
        var restored = constrained
        restored.size.width = min(restored.width, visibleFrame.width)
        restored.size.height = min(restored.height, visibleFrame.height)
        restored.origin.x = min(max(visibleFrame.minX, restored.minX), visibleFrame.maxX - restored.width)
        restored.origin.y = min(max(visibleFrame.minY, restored.minY), visibleFrame.maxY - restored.height)
        window.setFrame(restored, display: false)
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

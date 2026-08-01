import CoreGraphics
import Foundation

/// System input idle time (keyboard / mouse / tablet) for Pause on Inactivity.
public enum SystemIdleMonitor {
    /// Seconds since the last HID event in the combined session.
    /// Returns `0` if the query is unavailable (never treat as 'idle forever').
    public static func secondsSinceLastInput() -> TimeInterval {
        // `CGEventType(rawValue: ~0)` is the documented 'any event' sentinel.
        let any = CGEventType(rawValue: UInt32.max)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return seconds
    }

    /// Whether the user has been idle at least `thresholdSeconds`.
    public static func isIdle(thresholdSeconds: TimeInterval) -> Bool {
        guard thresholdSeconds > 0 else { return false }
        return secondsSinceLastInput() >= thresholdSeconds
    }
}

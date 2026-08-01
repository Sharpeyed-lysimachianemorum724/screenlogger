import CoreGraphics
import Foundation

/// Deterministic time-to-position mapping for the Timeline activity ribbon.
///
/// A drag must retain the same ``Window`` from its first update through its
/// final update. Recomputing a window from the newly selected moment while a
/// drag is in progress creates a feedback loop that moves the viewport under
/// the pointer.
public enum TimelineRibbonMapping {
    public struct Window: Sendable, Equatable {
        public let startMs: Int64
        public let endMs: Int64

        public init(startMs: Int64, endMs: Int64) {
            self.startMs = min(startMs, endMs)
            self.endMs = max(startMs, endMs)
        }

        public var durationMs: Int64 {
            max(1, endMs - startMs)
        }
    }

    /// Builds the visible time window for a range step. Step zero shows the
    /// full range; each following step halves it, down to a 30-second floor.
    public static func window(
        firstTimestampMs: Int64,
        lastTimestampMs: Int64,
        selectedTimestampMs: Int64?,
        scaleStep: Int
    ) -> Window {
        let fullStart = min(firstTimestampMs, lastTimestampMs)
        let fullEnd = max(firstTimestampMs, lastTimestampMs)
        let fullDuration = max(1, fullEnd - fullStart)
        let divisor = Int64(1 << min(max(scaleStep, 0), 6))
        let visibleDuration = min(fullDuration, max(30_000, fullDuration / divisor))
        let center = min(fullEnd, max(fullStart, selectedTimestampMs ?? fullEnd))
        let proposedStart = center - visibleDuration / 2
        let start = min(fullEnd - visibleDuration, max(fullStart, proposedStart))
        return Window(startMs: start, endMs: start + visibleDuration)
    }

    /// Converts a timestamp to a clamped horizontal position.
    public static func x(timestampMs: Int64, in window: Window, width: CGFloat) -> CGFloat {
        let safeWidth = max(width, 0)
        let fraction = Double(timestampMs - window.startMs) / Double(window.durationMs)
        return CGFloat(min(1, max(0, fraction))) * safeWidth
    }

    /// Converts a horizontal position to a clamped timestamp.
    public static func timestamp(x: CGFloat, in window: Window, width: CGFloat) -> Int64 {
        let fraction = Double(min(1, max(0, x / max(width, 1))))
        return window.startMs + Int64(fraction * Double(window.durationMs))
    }
}

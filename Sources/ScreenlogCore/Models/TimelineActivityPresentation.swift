import Foundation

/// Pure, immutable presentation data for the Timeline activity ribbon.
///
/// Adjacent captures are treated as one continuous block only when they are
/// close enough for the configured capture cadence. Longer spans remain gaps;
/// the UI must not paint a source across time for which no capture exists.
public struct TimelineActivityPresentation: Sendable, Equatable {
    public static let minimumGapThresholdMs: Int64 = 10_000
    public static let defaultSessionBoundaryMs: Int64 = 5 * 60 * 1_000

    public struct Source: Sendable, Equatable, Hashable {
        public let identity: String
        public let appLabel: String
        public let bundleID: String?
        public let domain: String?

        fileprivate init(frame: TimelineFrame) {
            let bundleID = Self.nonempty(frame.bundleID)
            let domain = Self.nonempty(frame.domain)
            let appLabel = frame.appLabel

            self.bundleID = bundleID
            self.domain = domain
            self.appLabel = appLabel
            if let bundleID {
                identity = "bundle:\(bundleID)"
            } else if let domain {
                identity = "domain:\(domain)"
            } else {
                identity = "label:\(appLabel)"
            }
        }

        private static func nonempty(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else { return nil }
            return value
        }
    }

    public struct Interval: Sendable, Equatable, Identifiable {
        public let id: Int64
        public let startMs: Int64
        public let endMs: Int64
        public let source: Source
        public let momentCount: Int
        public let representativeFrameID: Int64

        public var durationMs: Int64 { max(0, endMs - startMs) }
    }

    public struct Gap: Sendable, Equatable, Identifiable {
        public let id: Int64
        public let startMs: Int64
        public let endMs: Int64

        public var durationMs: Int64 { max(0, endMs - startMs) }
    }

    public struct Selection: Sendable, Equatable {
        public let frameID: Int64
        public let timestampMs: Int64
        /// True when the requested time was strictly between disconnected blocks.
        public let crossedGap: Bool
    }

    public let intervals: [Interval]
    public let gaps: [Gap]
    public let gapThresholdMs: Int64

    private let anchors: [Anchor]

    /// Builds ribbon intervals from frames in nondecreasing timestamp order.
    ///
    /// Source transitions meet at the midpoint between their neighboring
    /// captures. Capture gaps do not: the open interval between the two actual
    /// capture timestamps remains uncovered.
    public init(
        chronologicalFrames frames: [TimelineFrame],
        visibleStartMs: Int64,
        visibleEndMs: Int64,
        expectedCaptureIntervalMs: Int64,
        sessionBoundaryMs: Int64 = defaultSessionBoundaryMs
    ) {
        let visibleStart = min(visibleStartMs, visibleEndMs)
        let visibleEnd = max(visibleStartMs, visibleEndMs)
        let threshold = Self.gapThreshold(
            expectedCaptureIntervalMs: expectedCaptureIntervalMs,
            sessionBoundaryMs: sessionBoundaryMs
        )

        gapThresholdMs = threshold
        anchors = frames.map { Anchor(frameID: $0.id, timestampMs: $0.timestampMs) }

        guard !frames.isEmpty else {
            intervals = []
            gaps = []
            return
        }

        var builtIntervals: [Interval] = []
        var builtGaps: [Gap] = []
        builtIntervals.reserveCapacity(frames.count)

        var blockStart = 0
        for index in frames.indices.dropFirst() {
            let delta = Self.nonnegativeDelta(
                from: frames[index - 1].timestampMs,
                to: frames[index].timestampMs
            )
            guard delta >= threshold else { continue }

            Self.appendIntervals(
                frames: frames,
                range: blockStart...(index - 1),
                visibleStartMs: visibleStart,
                visibleEndMs: visibleEnd,
                to: &builtIntervals
            )
            Self.appendGap(
                startMs: frames[index - 1].timestampMs,
                endMs: frames[index].timestampMs,
                visibleStartMs: visibleStart,
                visibleEndMs: visibleEnd,
                to: &builtGaps
            )
            blockStart = index
        }

        Self.appendIntervals(
            frames: frames,
            range: blockStart...(frames.count - 1),
            visibleStartMs: visibleStart,
            visibleEndMs: visibleEnd,
            to: &builtIntervals
        )

        intervals = builtIntervals
        gaps = builtGaps
    }

    /// The inferred-continuity tolerance is four expected capture cycles. A
    /// ten-second floor absorbs ordinary scheduling/OCR jitter, while the
    /// session boundary is a hard upper limit.
    public static func gapThreshold(
        expectedCaptureIntervalMs: Int64,
        sessionBoundaryMs: Int64 = defaultSessionBoundaryMs
    ) -> Int64 {
        let boundary = max(1, sessionBoundaryMs)
        let expected = max(1, expectedCaptureIntervalMs)
        let multiplied = expected.multipliedReportingOverflow(by: 4)
        let cadenceTolerance = multiplied.overflow ? Int64.max : multiplied.partialValue
        return min(boundary, max(minimumGapThresholdMs, cadenceTolerance))
    }

    /// Returns the closest captured moment. Inside a gap, only its two boundary
    /// captures can win; an exact midpoint tie deterministically chooses the
    /// earlier boundary.
    public func selection(at timestampMs: Int64) -> Selection? {
        guard !anchors.isEmpty else { return nil }

        var low = 0
        var high = anchors.count
        while low < high {
            let middle = (low + high) / 2
            if anchors[middle].timestampMs < timestampMs {
                low = middle + 1
            } else {
                high = middle
            }
        }

        if low == 0 {
            return Selection(
                frameID: anchors[0].frameID,
                timestampMs: anchors[0].timestampMs,
                crossedGap: false
            )
        }
        if low == anchors.count {
            let last = anchors[anchors.count - 1]
            return Selection(frameID: last.frameID, timestampMs: last.timestampMs, crossedGap: false)
        }

        let before = anchors[low - 1]
        let after = anchors[low]
        let crossedGap =
            Self.nonnegativeDelta(from: before.timestampMs, to: after.timestampMs) >= gapThresholdMs
            && timestampMs > before.timestampMs
            && timestampMs < after.timestampMs
        let beforeDistance = Self.nonnegativeDelta(from: before.timestampMs, to: timestampMs)
        let afterDistance = Self.nonnegativeDelta(from: timestampMs, to: after.timestampMs)
        let selected = beforeDistance <= afterDistance ? before : after
        return Selection(
            frameID: selected.frameID,
            timestampMs: selected.timestampMs,
            crossedGap: crossedGap
        )
    }

    private struct Anchor: Sendable, Equatable {
        let frameID: Int64
        let timestampMs: Int64
    }

    private static func appendIntervals(
        frames: [TimelineFrame],
        range: ClosedRange<Int>,
        visibleStartMs: Int64,
        visibleEndMs: Int64,
        to intervals: inout [Interval]
    ) {
        var runStart = range.lowerBound
        var runSource = Source(frame: frames[runStart])

        for index in (range.lowerBound + 1)...(range.upperBound + 1) {
            let reachedEnd = index > range.upperBound
            let nextSource = reachedEnd ? nil : Source(frame: frames[index])
            guard reachedEnd || nextSource != runSource else { continue }

            let runEnd = index - 1
            let startMs: Int64
            if runStart == range.lowerBound {
                startMs = frames[runStart].timestampMs
            } else {
                startMs = midpoint(
                    frames[runStart - 1].timestampMs,
                    frames[runStart].timestampMs
                )
            }

            let endMs: Int64
            if runEnd == range.upperBound {
                endMs = frames[runEnd].timestampMs
            } else {
                endMs = midpoint(
                    frames[runEnd].timestampMs,
                    frames[runEnd + 1].timestampMs
                )
            }

            let clippedStart = max(visibleStartMs, startMs)
            let clippedEnd = min(visibleEndMs, endMs)
            if clippedStart <= clippedEnd {
                intervals.append(
                    Interval(
                        id: frames[runStart].id,
                        startMs: clippedStart,
                        endMs: clippedEnd,
                        source: runSource,
                        momentCount: runEnd - runStart + 1,
                        representativeFrameID: frames[runStart].id
                    )
                )
            }

            guard let nextSource else { return }
            runStart = index
            runSource = nextSource
        }
    }

    private static func appendGap(
        startMs: Int64,
        endMs: Int64,
        visibleStartMs: Int64,
        visibleEndMs: Int64,
        to gaps: inout [Gap]
    ) {
        let clippedStart = max(visibleStartMs, startMs)
        let clippedEnd = min(visibleEndMs, endMs)
        guard clippedStart < clippedEnd else { return }
        gaps.append(
            Gap(
                id: startMs,
                startMs: clippedStart,
                endMs: clippedEnd
            )
        )
    }

    private static func midpoint(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        lhs + (rhs - lhs) / 2
    }

    private static func nonnegativeDelta(from start: Int64, to end: Int64) -> Int64 {
        let result = end.subtractingReportingOverflow(start)
        guard !result.overflow else { return Int64.max }
        return max(0, result.partialValue)
    }
}

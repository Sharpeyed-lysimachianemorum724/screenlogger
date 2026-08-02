/// Immutable navigation metadata for a loaded Timeline window.
///
/// Timeline views ask for the selected frame and its neighbors many times during a
/// single render. Building this index once when the window changes keeps those
/// lookups constant-time without changing the source array or its identity.
public struct TimelineNavigationIndex: Sendable {
    private let positionByFrameID: [Int64: Int]
    private let momentPositionByFrameID: [Int64: Int]
    private let framePositionsByMoment: [[Int]]

    /// Number of synchronized capture intervals in the loaded Timeline. A
    /// multi-display interval is one moment with several frame positions.
    public let momentCount: Int

    /// True when frame identifiers are already in nondecreasing capture order.
    public let isChronological: Bool

    public init(frames: [TimelineFrame]) {
        var positions: [Int64: Int] = [:]
        positions.reserveCapacity(frames.count)
        var momentPositions: [Int64: Int] = [:]
        var moments: [[Int]] = []
        var frameMoments: [Int64: Int] = [:]

        var previousID: Int64?
        var previousTimestamp: Int64?
        var chronological = true
        for (position, frame) in frames.enumerated() {
            // Match Array.firstIndex semantics if corrupt input contains a duplicate.
            if positions[frame.id] == nil {
                positions[frame.id] = position
            }
            if let previousTimestamp,
                frame.timestampMs < previousTimestamp
                    || (frame.timestampMs == previousTimestamp && frame.id < (previousID ?? frame.id))
            {
                chronological = false
            }

            let momentPosition: Int
            if let existing = momentPositions[frame.timestampMs] {
                momentPosition = existing
                moments[existing].append(position)
            } else {
                momentPosition = moments.count
                momentPositions[frame.timestampMs] = momentPosition
                moments.append([position])
            }
            if frameMoments[frame.id] == nil {
                frameMoments[frame.id] = momentPosition
            }

            previousID = frame.id
            previousTimestamp = frame.timestampMs
        }

        positionByFrameID = positions
        momentPositionByFrameID = frameMoments
        framePositionsByMoment = moments
        momentCount = moments.count
        isChronological = chronological
    }

    public func position(of frameID: Int64) -> Int? {
        positionByFrameID[frameID]
    }

    public func momentPosition(of frameID: Int64) -> Int? {
        momentPositionByFrameID[frameID]
    }

    public func framePositions(inMoment position: Int) -> [Int] {
        guard framePositionsByMoment.indices.contains(position) else { return [] }
        return framePositionsByMoment[position]
    }

    public func framePositions(inMomentContaining frameID: Int64) -> [Int] {
        guard let position = momentPosition(of: frameID) else { return [] }
        return framePositions(inMoment: position)
    }

    public var representativeFramePositions: [Int] {
        framePositionsByMoment.compactMap(\.first)
    }
}

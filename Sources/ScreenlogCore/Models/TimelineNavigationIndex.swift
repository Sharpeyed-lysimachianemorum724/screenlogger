/// Immutable navigation metadata for a loaded Timeline window.
///
/// Timeline views ask for the selected frame and its neighbors many times during a
/// single render. Building this index once when the window changes keeps those
/// lookups constant-time without changing the source array or its identity.
public struct TimelineNavigationIndex: Sendable {
    private let positionByFrameID: [Int64: Int]

    /// True when frame identifiers are already in nondecreasing capture order.
    public let isChronological: Bool

    public init(frames: [TimelineFrame]) {
        var positions: [Int64: Int] = [:]
        positions.reserveCapacity(frames.count)

        var previousID: Int64?
        var chronological = true
        for (position, frame) in frames.enumerated() {
            // Match Array.firstIndex semantics if corrupt input contains a duplicate.
            if positions[frame.id] == nil {
                positions[frame.id] = position
            }
            if let previousID, frame.id < previousID {
                chronological = false
            }
            previousID = frame.id
        }

        positionByFrameID = positions
        isChronological = chronological
    }

    public func position(of frameID: Int64) -> Int? {
        positionByFrameID[frameID]
    }
}

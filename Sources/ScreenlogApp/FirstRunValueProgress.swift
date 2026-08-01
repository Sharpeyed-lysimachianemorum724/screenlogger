import Foundation

/// Tracks the first-run promise from starting capture to a durably stored,
/// searchable Library moment.
///
/// Recording state alone is not completion: the capture loop can be running
/// before its first frame has finished storage and indexing. A new frame ID is
/// the existing post-storage signal from `RecordingEngine`.
struct FirstRunValueProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case waiting
        case ready(frameID: Int64)
    }

    private(set) var phase: Phase = .idle
    private var baselineFrameID: Int64?

    var isWaiting: Bool {
        phase == .waiting
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    mutating func begin(after frameID: Int64?) {
        baselineFrameID = frameID
        phase = .waiting
    }

    /// Returns true only for the first frame stored after this journey began.
    @discardableResult
    mutating func observeDurableFrame(_ frameID: Int64) -> Bool {
        guard phase == .waiting else { return false }
        if let baselineFrameID, frameID <= baselineFrameID { return false }
        phase = .ready(frameID: frameID)
        return true
    }

    mutating func reset() {
        baselineFrameID = nil
        phase = .idle
    }
}

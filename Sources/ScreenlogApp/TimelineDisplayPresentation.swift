import Foundation
import ScreenlogCore

enum TimelineDisplayPresentation {
    static func label(for index: Int, in frames: [TimelineFrame]) -> String {
        guard frames.indices.contains(index) else { return "Display" }
        let frame = frames[index]
        let mainCandidates = frames.filter { frame in
            guard let display = frame.captureDisplay else { return false }
            return abs(display.x) < 0.5 && abs(display.y) < 0.5
        }
        if mainCandidates.count == 1,
            let display = frame.captureDisplay,
            abs(display.x) < 0.5,
            abs(display.y) < 0.5
        {
            return "Main Display"
        }
        return "Display \(index + 1)"
    }

    static func deletionDetail(frame: TimelineFrame, displayCount: Int) -> String {
        var detail = "\(frame.appLabel) at \(SLTimeFormat.full(frame.timestampMs))."
        if displayCount > 1 {
            detail += " This removes all \(displayCount) display captures from this moment."
        }
        return detail
    }
}

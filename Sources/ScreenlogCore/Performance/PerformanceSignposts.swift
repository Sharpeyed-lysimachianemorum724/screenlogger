import Foundation
import OSLog

/// Instruments points of interest for the interactions covered by the release
/// benchmark. Signposts have negligible cost when no trace is attached.
public enum ScreenlogPerformanceSignposts {
    private static let log = OSLog(subsystem: "dev.screenlog", category: "Performance")

    @discardableResult
    public static func measure<T>(
        _ metric: PerformanceMetricID,
        operation: () throws -> T
    ) rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        let name = signpostName(metric)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer { os_signpost(.end, log: log, name: name, signpostID: signpostID) }
        return try operation()
    }

    @discardableResult
    public static func measure<T>(
        _ metric: PerformanceMetricID,
        operation: () async throws -> T
    ) async rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        let name = signpostName(metric)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer { os_signpost(.end, log: log, name: name, signpostID: signpostID) }
        return try await operation()
    }

    private static func signpostName(_ metric: PerformanceMetricID) -> StaticString {
        switch metric {
        case .warmLibrarySearch: return "WarmLibrarySearch"
        case .firstThumbnailDecode: return "FirstThumbnailDecode"
        case .timelineFrameExtraction: return "TimelineFrameExtraction"
        case .processCPU: return "ProcessCPU"
        case .residentMemory: return "ResidentMemory"
        }
    }
}

import Foundation
import ScreenlogCore

struct StorageMeasurement: Equatable, Sendable {
    let libraryBytes: Int64
    let availableBytes: Int64?
    let measuredAt: Date
    let growth: StorageGrowthMeasurement?
}

struct StorageGrowthMeasurement: Equatable, Sendable {
    let byteDelta: Int64
    let elapsed: TimeInterval
    let startedAt: Date

    init?(currentBytes: Int64, measuredAt: Date, previousBytes: Int64, previousDate: Date) {
        let elapsed = measuredAt.timeIntervalSince(previousDate)
        guard elapsed.isFinite, elapsed > 0 else { return nil }
        self.byteDelta = currentBytes.subtractingClamped(previousBytes)
        self.elapsed = elapsed
        self.startedAt = previousDate
    }
}

enum StorageMeasurementLoadState: Equatable, Sendable {
    case idle
    case loading(previous: StorageMeasurement?)
    case available(StorageMeasurement)
    case failed(previous: StorageMeasurement?)

    var measurement: StorageMeasurement? {
        switch self {
        case .available(let measurement): return measurement
        case .loading(let previous), .failed(let previous): return previous
        case .idle: return nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct StoragePolicyFingerprint: Equatable, Hashable, Sendable {
    let retentionDays: Int
    let storageCapMB: Int64

    init(retentionDays: Int, storageCapMB: Int64) {
        self.retentionDays = max(1, retentionDays)
        self.storageCapMB = max(0, storageCapMB)
    }

    var policy: RetentionPolicy {
        RetentionPolicy(retentionDays: retentionDays, storageCapMB: storageCapMB)
    }

    func matches(_ report: RetentionPreflightReport) -> Bool {
        report.policy.retentionDays == retentionDays
            && report.policy.storageCapMB == storageCapMB
            && report.policy.deleteOldestWhenOverCap
    }
}

enum StorageCleanupPreflightLoadState: Equatable, Sendable {
    case idle
    case loading(previous: RetentionPreflightReport?)
    case available(RetentionPreflightReport)
    case failed(previous: RetentionPreflightReport?)

    var report: RetentionPreflightReport? {
        switch self {
        case .available(let report): return report
        case .loading(let previous), .failed(let previous): return previous
        case .idle: return nil
        }
    }

    func currentReport(for fingerprint: StoragePolicyFingerprint) -> RetentionPreflightReport? {
        guard let report, fingerprint.matches(report) else { return nil }
        return report
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var refreshFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum StorageLimitForecast: Equatable, Sendable {
    case automaticCleanupOff
    case compressionOnly
    case ageLimitOnly
    case needsGrowthHistory
    case stableOrShrinking
    case atOrAboveLimit(bytes: Int64)
    case estimatedTimeToLimit(TimeInterval)

    static func make(
        mode: StorageManagementMode,
        storageCapMB: Int64,
        measurement: StorageMeasurement?
    ) -> Self {
        switch mode {
        case .off: return .automaticCleanupOff
        case .compress: return .compressionOnly
        case .limit: break
        }
        guard storageCapMB > 0 else { return .ageLimitOnly }
        guard let measurement else { return .needsGrowthHistory }
        let multiplication = storageCapMB.multipliedReportingOverflow(by: 1_000_000)
        let capBytes = multiplication.overflow ? Int64.max : multiplication.partialValue
        if measurement.libraryBytes >= capBytes {
            return .atOrAboveLimit(bytes: measurement.libraryBytes - capBytes)
        }
        guard let growth = measurement.growth,
            growth.elapsed >= 15 * 60,
            growth.elapsed <= 30 * 86_400,
            growth.byteDelta > 0
        else {
            if let growth = measurement.growth,
                growth.elapsed >= 15 * 60,
                growth.elapsed <= 30 * 86_400,
                growth.byteDelta <= 0
            {
                return .stableOrShrinking
            }
            return .needsGrowthHistory
        }
        let bytesPerSecond = Double(growth.byteDelta) / growth.elapsed
        let remaining = Double(capBytes - measurement.libraryBytes)
        let estimate = remaining / bytesPerSecond
        guard estimate.isFinite, estimate > 0 else { return .needsGrowthHistory }
        return .estimatedTimeToLimit(estimate)
    }
}

extension Int64 {
    fileprivate func subtractingClamped(_ other: Int64) -> Int64 {
        let result = subtractingReportingOverflow(other)
        guard result.overflow else { return result.partialValue }
        return self >= 0 && other < 0 ? Int64.max : Int64.min
    }
}

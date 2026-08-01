import Foundation
import ScreenlogCore

/// Read-only Library capacity and cleanup estimates used by Storage Settings.
@MainActor
extension AppModel {
    func refreshLibrarySize() {
        refreshStorageMeasurement()
    }

    func refreshStorageMeasurement() {
        let previousVisible = storageMeasurementState.measurement ?? persistedStorageMeasurement()
        let baseline = previousVisible
        let root = root
        let requestID = UUID()
        storageMeasurementRequestID = requestID
        storageMeasurementTask?.cancel()
        storageMeasurementState = .loading(previous: previousVisible)

        storageMeasurementTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try Self.measureStorage(at: root) }
            }.value
            guard let self, !Task.isCancelled, self.storageMeasurementRequestID == requestID else {
                return
            }
            self.storageMeasurementTask = nil
            switch result {
            case .success(let current):
                let measurement = StorageMeasurement(
                    libraryBytes: current.libraryBytes,
                    availableBytes: current.availableBytes,
                    measuredAt: current.measuredAt,
                    growth: baseline.flatMap {
                        StorageGrowthMeasurement(
                            currentBytes: current.libraryBytes,
                            measuredAt: current.measuredAt,
                            previousBytes: $0.libraryBytes,
                            previousDate: $0.measuredAt
                        )
                    }
                )
                self.librarySizeBytes = current.libraryBytes
                self.storageMeasurementState = .available(measurement)
                self.persistStorageMeasurement(measurement)
            case .failure:
                self.storageMeasurementState = .failed(previous: previousVisible)
            }
        }
    }

    func refreshStorageCleanupPreflight() {
        let fingerprint = StoragePolicyFingerprint(
            retentionDays: retentionDays,
            storageCapMB: storageCapMB
        )
        let previous = storageCleanupPreflightState.currentReport(for: fingerprint)
        guard let store else {
            storageCleanupPreflightState = .failed(previous: previous)
            return
        }
        let requestID = UUID()
        storagePreflightRequestID = requestID
        storagePreflightTask?.cancel()
        storageCleanupPreflightState = .loading(previous: previous)
        storagePreflightTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    try RetentionService(policy: fingerprint.policy).preflight(store: store)
                }
            }.value
            guard let self, !Task.isCancelled, self.storagePreflightRequestID == requestID else {
                return
            }
            self.storagePreflightTask = nil
            switch result {
            case .success(let report):
                self.storageCleanupPreflightState = .available(report)
            case .failure:
                self.storageCleanupPreflightState = .failed(previous: previous)
            }
        }
    }

    static func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func persistedStorageMeasurement() -> StorageMeasurement? {
        guard preferences.object(forKey: Self.storageMeasurementBytesKey) != nil,
            preferences.object(forKey: Self.storageMeasurementDateKey) != nil
        else { return nil }
        let bytes = preferences.object(forKey: Self.storageMeasurementBytesKey) as? NSNumber
        let timestamp = preferences.double(forKey: Self.storageMeasurementDateKey)
        guard let bytes, timestamp.isFinite, timestamp > 0 else { return nil }
        return StorageMeasurement(
            libraryBytes: max(0, bytes.int64Value),
            availableBytes: nil,
            measuredAt: Date(timeIntervalSince1970: timestamp),
            growth: nil
        )
    }

    private func persistStorageMeasurement(_ measurement: StorageMeasurement) {
        preferences.set(measurement.libraryBytes, forKey: Self.storageMeasurementBytesKey)
        preferences.set(
            measurement.measuredAt.timeIntervalSince1970,
            forKey: Self.storageMeasurementDateKey
        )
    }

    nonisolated private static func measureStorage(at root: URL) throws -> StorageRawMeasurement {
        let libraryBytes = try ManagedLibraryStorage.byteSize(root: root)
        let values = try root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let fallback = values.volumeAvailableCapacity.map(Int64.init)
        return StorageRawMeasurement(
            libraryBytes: libraryBytes,
            availableBytes: values.volumeAvailableCapacityForImportantUsage ?? fallback,
            measuredAt: Date()
        )
    }

    private static let storageMeasurementBytesKey = "screenlog.storage.lastMeasurementBytes"
    private static let storageMeasurementDateKey = "screenlog.storage.lastMeasurementDate"
}

private struct StorageRawMeasurement: Sendable {
    let libraryBytes: Int64
    let availableBytes: Int64?
    let measuredAt: Date
}

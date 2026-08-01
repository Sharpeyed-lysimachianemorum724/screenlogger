import XCTest

final class StorageConfidencePresentationTests: XCTestCase {
    func testForecastExplainsModesWithoutInventingDeadline() {
        XCTAssertEqual(
            StorageLimitForecast.make(mode: .off, storageCapMB: 50_000, measurement: nil),
            .automaticCleanupOff
        )
        XCTAssertEqual(
            StorageLimitForecast.make(mode: .compress, storageCapMB: 50_000, measurement: nil),
            .compressionOnly
        )
        XCTAssertEqual(
            StorageLimitForecast.make(mode: .limit, storageCapMB: 0, measurement: nil),
            .ageLimitOnly
        )
        XCTAssertEqual(
            StorageLimitForecast.make(mode: .limit, storageCapMB: 1, measurement: nil),
            .needsGrowthHistory
        )
    }

    func testForecastReportsAtLimitAndStableHistory() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let stableGrowth = try XCTUnwrap(
            StorageGrowthMeasurement(
                currentBytes: 500_000,
                measuredAt: now,
                previousBytes: 600_000,
                previousDate: now.addingTimeInterval(-3_600)
            )
        )
        let stable = StorageMeasurement(
            libraryBytes: 500_000,
            availableBytes: 2_000_000,
            measuredAt: now,
            growth: stableGrowth
        )

        XCTAssertEqual(
            StorageLimitForecast.make(mode: .limit, storageCapMB: 1, measurement: stable),
            .stableOrShrinking
        )
        XCTAssertEqual(
            StorageLimitForecast.make(
                mode: .limit,
                storageCapMB: 1,
                measurement: StorageMeasurement(
                    libraryBytes: 1_250_000,
                    availableBytes: nil,
                    measuredAt: now,
                    growth: nil
                )
            ),
            .atOrAboveLimit(bytes: 250_000)
        )
    }

    func testForecastUsesOnlyGrowthMeasuredOverMeaningfulInterval() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let growth = try XCTUnwrap(
            StorageGrowthMeasurement(
                currentBytes: 500_000,
                measuredAt: now,
                previousBytes: 400_000,
                previousDate: now.addingTimeInterval(-1_000)
            )
        )
        let measurement = StorageMeasurement(
            libraryBytes: 500_000,
            availableBytes: nil,
            measuredAt: now,
            growth: growth
        )

        guard
            case .estimatedTimeToLimit(let interval) = StorageLimitForecast.make(
                mode: .limit,
                storageCapMB: 1,
                measurement: measurement
            )
        else {
            return XCTFail("Expected a time-to-limit estimate")
        }
        XCTAssertEqual(interval, 5_000, accuracy: 0.001)

        let shortGrowth = try XCTUnwrap(
            StorageGrowthMeasurement(
                currentBytes: 500_000,
                measuredAt: now,
                previousBytes: 400_000,
                previousDate: now.addingTimeInterval(-60)
            )
        )
        XCTAssertEqual(
            StorageLimitForecast.make(
                mode: .limit,
                storageCapMB: 1,
                measurement: StorageMeasurement(
                    libraryBytes: 500_000,
                    availableBytes: nil,
                    measuredAt: now,
                    growth: shortGrowth
                )
            ),
            .needsGrowthHistory
        )
    }

    func testMeasurementStateKeepsLastGoodValueDuringRefreshAndFailure() {
        let measurement = StorageMeasurement(
            libraryBytes: 42,
            availableBytes: 100,
            measuredAt: Date(timeIntervalSince1970: 1),
            growth: nil
        )

        XCTAssertEqual(StorageMeasurementLoadState.loading(previous: measurement).measurement, measurement)
        XCTAssertEqual(StorageMeasurementLoadState.failed(previous: measurement).measurement, measurement)
        XCTAssertNil(StorageMeasurementLoadState.idle.measurement)
    }
}

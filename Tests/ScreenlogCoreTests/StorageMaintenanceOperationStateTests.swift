import XCTest

@testable import ScreenlogCore

final class StorageMaintenanceOperationStateTests: XCTestCase {
    func testOnlyRunningStateReportsInProgress() {
        XCTAssertFalse(StorageMaintenanceOperationState.idle.isRunning)
        XCTAssertTrue(StorageMaintenanceOperationState.running(.compaction).isRunning)
        XCTAssertFalse(
            StorageMaintenanceOperationState.success(.nothingToCompact).isRunning
        )
        XCTAssertFalse(
            StorageMaintenanceOperationState.failure(.retentionLimitNotSatisfied).isRunning
        )
    }

    func testRetryOperationIsOwnedByRetryableFailure() {
        XCTAssertEqual(
            StorageMaintenanceOperationState.failure(
                .compactionFailed
            ).retryOperation,
            .compaction
        )
        XCTAssertEqual(
            StorageMaintenanceOperationState.failure(
                .retentionCouldNotRemoveFiles
            ).retryOperation,
            .retention
        )
        XCTAssertEqual(
            StorageMaintenanceOperationState.failure(
                .retentionFailed
            ).retryOperation,
            .retention
        )
    }

    func testTerminalLimitFailureCannotOfferRetry() {
        let state = StorageMaintenanceOperationState.failure(.retentionLimitNotSatisfied)

        XCTAssertNil(state.retryOperation)
    }

    func testOperationalFailuresExposeOnlyStablePrivacySafeCopy() {
        let rawDetail = "/Users/person/Secret Project/private.db: database busy"
        let failures: [StorageMaintenanceFailure] = [.compactionFailed, .retentionFailed]

        for failure in failures {
            XCTAssertFalse(failure.userMessage.contains(rawDetail))
            XCTAssertFalse(String(describing: failure).contains(rawDetail))
        }
        XCTAssertEqual(
            StorageMaintenanceFailure.compactionFailed.userMessage,
            "Couldn't finish compressing older images. Your saved moments remain available. Try again."
        )
        XCTAssertEqual(
            StorageMaintenanceFailure.retentionFailed.userMessage,
            "Couldn't apply storage limits. Screenlogger kept any files it couldn't safely remove. Try again."
        )
    }

    func testNonFailureStatesCannotOfferRetry() {
        XCTAssertNil(StorageMaintenanceOperationState.idle.retryOperation)
        XCTAssertNil(StorageMaintenanceOperationState.running(.retention).retryOperation)
        XCTAssertNil(
            StorageMaintenanceOperationState.success(
                .retentionApplied(removedMediaCount: 4, freedBytes: 1_024)
            ).retryOperation
        )
    }
}

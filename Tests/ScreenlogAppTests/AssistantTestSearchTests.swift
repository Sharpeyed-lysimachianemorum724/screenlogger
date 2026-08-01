import Foundation
import XCTest

final class AssistantTestSearchTests: XCTestCase {
    func testSuccessfulSearchReportsOnlyCountAndLatency() {
        let outcome = AssistantTestSearchService.test(
            executable: URL(fileURLWithPath: "/managed/screenlog")
        ) { executable, arguments, byteLimit in
            XCTAssertEqual(executable.path, "/managed/screenlog")
            XCTAssertEqual(
                arguments,
                ["search", "since:1970-01-01", "--limit", "1", "--json"]
            )
            XCTAssertEqual(byteLimit, 256 * 1_024)
            return .success(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data(
                        #"[{"frameID":123,"snippet":"private content is discarded"}]"#.utf8
                    ),
                    elapsedMilliseconds: 47
                )
            )
        }

        XCTAssertEqual(
            outcome,
            .succeeded(.init(resultCount: 1, latencyMilliseconds: 47))
        )
    }

    func testEmptyLibraryIsStillASuccessfulSearch() {
        XCTAssertEqual(
            AssistantTestSearchService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data("[]".utf8),
                    elapsedMilliseconds: 12
                )
            ),
            .succeeded(.init(resultCount: 0, latencyMilliseconds: 12))
        )
    }

    func testCommandFailureAndMalformedOutputRemainDistinct() {
        XCTAssertEqual(
            AssistantTestSearchService.classify(
                .init(
                    terminationStatus: 1,
                    standardOutput: Data(),
                    elapsedMilliseconds: 2
                )
            ),
            .failed(.commandFailed)
        )
        XCTAssertEqual(
            AssistantTestSearchService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data("not-json".utf8),
                    elapsedMilliseconds: 2
                )
            ),
            .failed(.invalidResponse)
        )
    }

    func testUnexpectedExtraResultsAndOversizedOutputAreRejected() {
        XCTAssertEqual(
            AssistantTestSearchService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data("[{},{}]".utf8),
                    elapsedMilliseconds: 1
                )
            ),
            .failed(.invalidResponse)
        )
        XCTAssertEqual(
            AssistantTestSearchService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data(count: 256 * 1_024 + 1),
                    elapsedMilliseconds: 1
                )
            ),
            .failed(.invalidResponse)
        )
    }

    func testRunnerFailuresMapToStablePrivacySafeStates() {
        let executable = URL(fileURLWithPath: "/managed/screenlog")
        let cases:
            [(
                BoundedLocalCommandRunner.Failure,
                AssistantTestSearchOutcome
            )] = [
                (.unavailable, .failed(.commandUnavailable)),
                (.timedOut, .failed(.timedOut)),
                (.cancelled, .failed(.commandFailed)),
                (.outputLimitExceeded, .failed(.invalidResponse)),
            ]

        for (failure, expected) in cases {
            XCTAssertEqual(
                AssistantTestSearchService.test(executable: executable) { _, _, _ in
                    .failure(failure)
                },
                expected
            )
        }
    }
}

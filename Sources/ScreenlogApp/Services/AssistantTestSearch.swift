import Foundation

struct AssistantTestSearchSuccess: Equatable, Sendable {
    let resultCount: Int
    let latencyMilliseconds: Int
}

enum AssistantTestSearchFailure: Equatable, Sendable {
    case commandUnavailable
    case commandFailed
    case timedOut
    case invalidResponse
}

enum AssistantTestSearchOutcome: Equatable, Sendable {
    case succeeded(AssistantTestSearchSuccess)
    case failed(AssistantTestSearchFailure)
}

/// Proves the managed command can execute a real, read-only Library search.
/// Search result fields are decoded only to validate the response and are
/// immediately discarded; callers receive only a count and elapsed time.
enum AssistantTestSearchService {
    static let arguments = ["search", "since:1970-01-01", "--limit", "1", "--json"]
    static let outputByteLimit = 256 * 1_024

    typealias Runner = (
        _ executable: URL,
        _ arguments: [String],
        _ outputByteLimit: Int
    ) -> Swift.Result<BoundedLocalCommandRunner.Result, BoundedLocalCommandRunner.Failure>

    static func test(
        executable: URL,
        runner: Runner = runCommand
    ) -> AssistantTestSearchOutcome {
        switch runner(executable, arguments, outputByteLimit) {
        case .success(let result):
            return classify(result)
        case .failure(.unavailable):
            return .failed(.commandUnavailable)
        case .failure(.timedOut):
            return .failed(.timedOut)
        case .failure(.cancelled):
            return .failed(.commandFailed)
        case .failure(.outputLimitExceeded):
            return .failed(.invalidResponse)
        }
    }

    static func classify(
        _ result: BoundedLocalCommandRunner.Result
    ) -> AssistantTestSearchOutcome {
        guard result.terminationStatus == 0 else {
            return .failed(.commandFailed)
        }
        guard result.standardOutput.count <= outputByteLimit,
            let results = try? JSONDecoder().decode(
                [DiscardedSearchResult].self,
                from: result.standardOutput
            ), results.count <= 1
        else {
            return .failed(.invalidResponse)
        }
        return .succeeded(
            AssistantTestSearchSuccess(
                resultCount: results.count,
                latencyMilliseconds: max(0, result.elapsedMilliseconds)
            )
        )
    }

    private static func runCommand(
        executable: URL,
        arguments: [String],
        outputByteLimit: Int
    ) -> Swift.Result<BoundedLocalCommandRunner.Result, BoundedLocalCommandRunner.Failure> {
        BoundedLocalCommandRunner.run(
            executable: executable,
            arguments: arguments,
            outputByteLimit: outputByteLimit
        )
    }
}

private struct DiscardedSearchResult: Decodable {
    init(from decoder: Decoder) throws {
        _ = try decoder.container(keyedBy: AnyCodingKey.self)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

import Darwin
import Foundation

/// Runs one local managed command with a private, bounded output file.
///
/// Keeping process lifecycle and output limits here prevents readiness probes
/// from each inventing subtly different timeout and cleanup behavior.
enum BoundedLocalCommandRunner {
    struct Result: Equatable, Sendable {
        let terminationStatus: Int32
        let standardOutput: Data
        let elapsedMilliseconds: Int
    }

    enum Failure: Error, Equatable, Sendable {
        case unavailable
        case timedOut
        case cancelled
        case outputLimitExceeded
    }

    static func run(
        executable: URL,
        arguments: [String],
        outputByteLimit: Int,
        timeout: TimeInterval = 10
    ) -> Swift.Result<Result, Failure> {
        guard outputByteLimit > 0, timeout > 0,
            FileManager.default.isExecutableFile(atPath: executable.path)
        else {
            return .failure(.unavailable)
        }

        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "screenlog-local-command-\(UUID().uuidString)",
            isDirectory: true
        )
        let outputURL = outputDirectory.appendingPathComponent("output.json")
        do {
            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return .failure(.unavailable)
        }
        defer { try? fileManager.removeItem(at: outputDirectory) }

        guard
            fileManager.createFile(
                atPath: outputURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ), let output = try? FileHandle(forWritingTo: outputURL)
        else {
            return .failure(.unavailable)
        }
        defer { try? output.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            try process.run()
        } catch {
            return .failure(.unavailable)
        }

        let checks = max(1, Int((timeout * 10).rounded(.up)))
        var didComplete = false
        for _ in 0..<checks {
            if Task.isCancelled {
                terminate(process, completion: completed)
                return .failure(.cancelled)
            }
            if outputSize(at: outputURL, fileManager: fileManager) > outputByteLimit {
                terminate(process, completion: completed)
                return .failure(.outputLimitExceeded)
            }
            if completed.wait(timeout: .now() + 0.1) == .success {
                didComplete = true
                break
            }
        }
        guard didComplete else {
            terminate(process, completion: completed)
            return .failure(.timedOut)
        }

        try? output.synchronize()
        try? output.close()
        guard outputSize(at: outputURL, fileManager: fileManager) <= outputByteLimit,
            let data = try? Data(contentsOf: outputURL)
        else {
            return .failure(.outputLimitExceeded)
        }

        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        let elapsedMilliseconds = Int(
            min(UInt64(Int.max), elapsedNanoseconds / 1_000_000)
        )
        return .success(
            Result(
                terminationStatus: process.terminationStatus,
                standardOutput: data,
                elapsedMilliseconds: elapsedMilliseconds
            )
        )
    }

    private static func outputSize(at url: URL, fileManager: FileManager) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int ?? 0
    }

    private static func terminate(
        _ process: Process,
        completion: DispatchSemaphore
    ) {
        guard process.isRunning else { return }
        process.terminate()
        if completion.wait(timeout: .now() + 1) != .success, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + 1)
        }
    }
}

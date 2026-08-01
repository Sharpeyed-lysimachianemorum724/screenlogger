import Foundation
import ScreenlogCore

extension ScreenlogCLIMain {
    // MARK: - parsing

    struct Globals {
        var dataDir: String?
        var root: URL {
            if let dataDir { return URL(fileURLWithPath: dataDir, isDirectory: true) }
            return ScreenlogPaths.resolvedRoot()
        }
    }

    static func parseGlobals(_ args: [String]) throws -> (Globals, [String]) {
        var g = Globals()
        var rest: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--data-dir" {
                guard g.dataDir == nil else {
                    throw CLIError.message("--data-dir may only be provided once")
                }
                guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
                    throw CLIError.usage("screenlog --data-dir PATH <command>")
                }
                let value = args[i + 1]
                guard !value.isEmpty, value.utf8.count <= 4_096 else {
                    throw CLIError.message("data directory path is empty or exceeds 4096 bytes")
                }
                g.dataDir = value
                i += 2
            } else {
                rest.append(args[i])
                i += 1
            }
        }
        return (g, rest)
    }

    static func intFlag(
        _ args: [String],
        name: String,
        allowed: ClosedRange<Int>
    ) throws -> Int? {
        guard let idx = args.firstIndex(of: name) else { return nil }
        guard args.lastIndex(of: name) == idx else {
            throw CLIError.message("\(name) may only be provided once")
        }
        guard idx + 1 < args.count, let value = Int(args[idx + 1]) else {
            throw CLIError.message("\(name) requires an integer value")
        }
        guard allowed.contains(value) else {
            throw CLIError.message("\(name) must be between \(allowed.lowerBound) and \(allowed.upperBound)")
        }
        return value
    }

    static func int64Flag(
        _ args: [String],
        name: String,
        allowed: ClosedRange<Int64>
    ) throws -> Int64? {
        guard let idx = args.firstIndex(of: name) else { return nil }
        guard args.lastIndex(of: name) == idx else {
            throw CLIError.message("\(name) may only be provided once")
        }
        guard idx + 1 < args.count, let value = Int64(args[idx + 1]) else {
            throw CLIError.message("\(name) requires an integer value")
        }
        guard allowed.contains(value) else {
            throw CLIError.message("\(name) is outside the supported range")
        }
        return value
    }

    static func stringFlag(
        _ args: [String],
        name: String,
        maximumBytes: Int = 4_096
    ) throws -> String? {
        guard let idx = args.firstIndex(of: name) else { return nil }
        guard args.lastIndex(of: name) == idx else {
            throw CLIError.message("\(name) may only be provided once")
        }
        guard idx + 1 < args.count, !args[idx + 1].hasPrefix("-") else {
            throw CLIError.message("\(name) requires a value")
        }
        let value = args[idx + 1]
        guard !value.isEmpty, value.utf8.count <= maximumBytes else {
            throw CLIError.message("\(name) is empty or exceeds \(maximumBytes) bytes")
        }
        return value
    }

    static func positionalArguments(_ args: [String], valueFlags: Set<String>) -> [String] {
        var values: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(arg) {
                skipNext = true
            } else if !arg.hasPrefix("-") {
                values.append(arg)
            }
        }
        return values
    }

    /// Parse ISO-8601, epoch seconds, or epoch milliseconds into ms since 1970.
    static func parseTimestampMs(_ raw: String) throws -> Int64 {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int64(trimmed) {
            // Heuristic: 10-digit / smaller to seconds; 13-digit to ms.
            if abs(n) < 100_000_000_000 {  // < ~year 5138 in seconds
                return n * 1000
            }
            return n
        }
        // ISO8601 with/without fractional seconds
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) {
            return Int64(d.timeIntervalSince1970 * 1000)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) {
            return Int64(d.timeIntervalSince1970 * 1000)
        }
        // Common local-style without Z
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ] {
            df.dateFormat = format
            if let d = df.date(from: trimmed) {
                return Int64(d.timeIntervalSince1970 * 1000)
            }
        }
        throw CLIError.message("invalid timestamp: \(raw) (use ISO-8601 or epoch seconds/ms)")
    }
}

enum CLIError: Error, CustomStringConvertible {
    case unknown(String)
    case usage(String)
    case message(String)
    var description: String {
        switch self {
        case .unknown(let c): return "unknown command: \(c)"
        case .usage(let u): return "usage: \(u)"
        case .message(let m): return m
        }
    }

    /// Shell-friendly convention: malformed invocation is 2; runtime/verification failure is 1.
    var exitCode: Int32 {
        switch self {
        case .unknown, .usage: return 2
        case .message: return 1
        }
    }
}

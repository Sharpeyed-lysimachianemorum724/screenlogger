import Foundation

/// User-visible refinements that may accompany an authored Library request.
///
/// The narrow shape is intentional: a handoff cannot accidentally accept OCR,
/// captured images, result snippets, URLs discovered during capture, or other
/// internal result metadata.
public struct LibraryAssistantHandoffConstraints: Equatable, Sendable {
    public var application: String?
    public var website: String?
    public var date: String?
    public var time: String?
    public var session: String?

    public init(
        application: String? = nil,
        website: String? = nil,
        date: String? = nil,
        time: String? = nil,
        session: String? = nil
    ) {
        self.application = application
        self.website = website
        self.date = date
        self.time = time
        self.session = session
    }
}

/// The only content eligible for a Library assistant handoff.
public struct LibraryAssistantHandoffRequest: Equatable, Sendable {
    public var authoredText: String
    public var constraints: LibraryAssistantHandoffConstraints

    public init(
        authoredText: String,
        constraints: LibraryAssistantHandoffConstraints = .init()
    ) {
        self.authoredText = authoredText
        self.constraints = constraints
    }
}

public struct LibraryAssistantHandoffPrompt: Equatable, Sendable {
    public let text: String
    public let wasTruncated: Bool

    public init(text: String, wasTruncated: Bool) {
        self.text = text
        self.wasTruncated = wasTruncated
    }

    public var utf8ByteCount: Int { text.utf8.count }
}

public enum LibraryAssistantHandoffPromptError: Error, Equatable, Sendable {
    case missingRequest
}

/// Builds a local-tool request without accepting captured result content.
public enum LibraryAssistantHandoffPromptBuilder {
    public static let maximumUTF8Bytes = 4_096

    private static let maximumConstraintValueBytes = 512
    private static let finalInstruction = "Use screenlog."

    public static func build(
        _ request: LibraryAssistantHandoffRequest
    ) throws -> LibraryAssistantHandoffPrompt {
        let authoredText = normalized(request.authoredText)
        let rawFields: [(label: String, value: String)] = [
            ("Application", normalized(request.constraints.application)),
            ("Website", normalized(request.constraints.website)),
            ("Date", normalized(request.constraints.date)),
            ("Time", normalized(request.constraints.time)),
            ("Session", normalized(request.constraints.session)),
        ].filter { !$0.value.isEmpty }

        guard !authoredText.isEmpty || !rawFields.isEmpty else {
            throw LibraryAssistantHandoffPromptError.missingRequest
        }

        var wasTruncated = false
        let fields = rawFields.map { field in
            let bounded = utf8Prefix(
                field.value,
                maximumBytes: maximumConstraintValueBytes
            )
            wasTruncated = wasTruncated || bounded.wasTruncated
            return (label: field.label, value: bounded.text)
        }

        let includesAuthoredText = !authoredText.isEmpty
        var fixedLines = ["Search my Screenlogger Library."]
        if includesAuthoredText {
            fixedLines.append("Request: ")
        }
        fixedLines.append(contentsOf: fields.map { "\($0.label): \($0.value)" })
        fixedLines.append(finalInstruction)

        // Account for the query-independent text and every separating newline
        // before assigning the remaining byte budget to the authored request.
        let fixedByteCount = fixedLines.joined(separator: "\n").utf8.count
        let queryBudget = max(0, maximumUTF8Bytes - fixedByteCount)
        let boundedQuery = utf8Prefix(authoredText, maximumBytes: queryBudget)
        wasTruncated = wasTruncated || boundedQuery.wasTruncated

        var lines = ["Search my Screenlogger Library."]
        if includesAuthoredText {
            lines.append("Request: \(boundedQuery.text)")
        }
        lines.append(contentsOf: fields.map { "\($0.label): \($0.value)" })
        lines.append(finalInstruction)

        let prompt = lines.joined(separator: "\n")
        precondition(prompt.utf8.count <= maximumUTF8Bytes)
        return LibraryAssistantHandoffPrompt(
            text: prompt,
            wasTruncated: wasTruncated
        )
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        var sanitized = ""
        sanitized.reserveCapacity(min(value.utf8.count, maximumUTF8Bytes))
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                sanitized.append(" ")
            } else {
                sanitized.unicodeScalars.append(scalar)
            }
        }
        return
            sanitized
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func utf8Prefix(
        _ value: String,
        maximumBytes: Int
    ) -> (text: String, wasTruncated: Bool) {
        guard value.utf8.count > maximumBytes else {
            return (value, false)
        }
        guard maximumBytes > 0 else { return ("", true) }

        let ellipsis = "..."
        guard maximumBytes >= ellipsis.utf8.count else { return ("", true) }
        let contentBudget = maximumBytes - ellipsis.utf8.count
        var result = ""
        result.reserveCapacity(contentBudget)
        for character in value {
            let nextByteCount = result.utf8.count + String(character).utf8.count
            guard nextByteCount <= contentBudget else { break }
            result.append(character)
        }
        return (result + ellipsis, true)
    }
}

public enum LibraryAssistantRoutingPreference: Hashable, Sendable {
    case automatic
    case askEveryTime
    case preferred(AssistantIntegrationTarget)

    public init(persistedValue: String) {
        if persistedValue.hasPrefix("preferred:"),
            let target = AssistantIntegrationTarget(
                rawValue: String(persistedValue.dropFirst("preferred:".count))
            )
        {
            self = .preferred(target)
            return
        }

        switch persistedValue {
        case "ask-every-time":
            self = .askEveryTime
        default:
            self = .automatic
        }
    }

    public var persistedValue: String {
        switch self {
        case .automatic: return "automatic"
        case .askEveryTime: return "ask-every-time"
        case .preferred(let target): return "preferred:\(target.rawValue)"
        }
    }
}

public enum LibraryAssistantRoutingDecision: Equatable, Sendable {
    case unavailable
    case route(AssistantIntegrationTarget)
    case choose([AssistantIntegrationTarget])
    case preferredUnavailable(
        preferred: AssistantIntegrationTarget,
        capableTargets: [AssistantIntegrationTarget]
    )
}

/// Resolves only capability and saved user intent. Installation discovery and
/// launch behavior stay outside this pure policy boundary.
public enum LibraryAssistantRoutingPolicy {
    public static func decide(
        capableTargets: [AssistantIntegrationTarget],
        preference: LibraryAssistantRoutingPreference
    ) -> LibraryAssistantRoutingDecision {
        let capable = canonicalTargets(from: capableTargets)

        switch preference {
        case .automatic:
            switch capable.count {
            case 0: return .unavailable
            case 1: return .route(capable[0])
            default: return .choose(capable)
            }
        case .askEveryTime:
            return capable.isEmpty ? .unavailable : .choose(capable)
        case .preferred(let preferred):
            guard capable.contains(preferred) else {
                return .preferredUnavailable(
                    preferred: preferred,
                    capableTargets: capable
                )
            }
            return .route(preferred)
        }
    }

    private static func canonicalTargets(
        from targets: [AssistantIntegrationTarget]
    ) -> [AssistantIntegrationTarget] {
        let requested = Set(targets)
        return AssistantIntegrationTarget.allCases.filter(requested.contains)
    }
}

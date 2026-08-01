import Foundation
import ScreenlogCore

struct AgentSkillSnapshot: Equatable, Sendable {
    let inspection: AssistantIntegrationInspection?
    let inspectionIssue: AssistantIntegrationError?
    let presence: AgentPresence.Result
    let destinationParentExists: Bool
}

enum AgentSkillSnapshotLoadState: Equatable, Sendable {
    case idle
    case loading(previous: AgentSkillSnapshot?)
    case loaded(AgentSkillSnapshot)

    var snapshot: AgentSkillSnapshot? {
        switch self {
        case .idle: return nil
        case .loading(let previous): return previous
        case .loaded(let snapshot): return snapshot
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct AgentSkillMutationResult: Sendable {
    let change: AssistantIntegrationChange
    let snapshot: AgentSkillSnapshot
}

/// App adapter for the shared assistant-integration lifecycle in ScreenlogCore.
/// Source discovery is app-specific; ownership, replacement, and registration
/// behavior are intentionally not duplicated here.
enum AgentSkillInstaller {
    static let skillFolderName = AssistantIntegrationService.skillFolderName

    /// Source verification, directory traversal, configuration parsing, and
    /// product discovery all run on a detached executor. Settings renders only
    /// the resulting in-memory snapshot.
    static func snapshot(target: AssistantIntegrationTarget) async -> AgentSkillSnapshot {
        await Task.detached(priority: .utility) {
            do {
                return makeSnapshot(
                    target: target,
                    inspection: try inspectSynchronously(target: target),
                    issue: nil
                )
            } catch let issue as AssistantIntegrationError {
                return makeSnapshot(target: target, inspection: nil, issue: issue)
            } catch {
                return makeSnapshot(target: target, inspection: nil, issue: nil)
            }
        }.value
    }

    static func install(
        target: AssistantIntegrationTarget,
        reinstall: Bool
    ) async throws -> AgentSkillMutationResult {
        try await Task.detached(priority: .userInitiated) {
            let change = try AssistantIntegrationService().install(
                target: target,
                source: resolveSkillSource(),
                mode: reinstall ? .reinstallOwned : .upgrade
            )
            return AgentSkillMutationResult(
                change: change,
                snapshot: makeSnapshot(
                    target: target,
                    inspection: change.inspection,
                    issue: nil
                )
            )
        }.value
    }

    /// Settings never removes an unrelated file or unauthenticated broken link.
    static func remove(
        target: AssistantIntegrationTarget
    ) async throws -> AgentSkillMutationResult {
        try await Task.detached(priority: .userInitiated) {
            let change = try AssistantIntegrationService().remove(
                target: target,
                source: try resolveSkillSource(),
                allowUnowned: false
            )
            return AgentSkillMutationResult(
                change: change,
                snapshot: makeSnapshot(
                    target: target,
                    inspection: change.inspection,
                    issue: nil
                )
            )
        }.value
    }

    static func resolveSkillSource() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []

        if let res = Bundle.main.resourceURL {
            candidates.append(
                res.appendingPathComponent("skill/\(skillFolderName)", isDirectory: true)
            )
            candidates.append(
                res.appendingPathComponent(skillFolderName, isDirectory: true)
            )
        }

        #if DEBUG
            if let env = ProcessInfo.processInfo.environment["SCREENLOG_SKILL_DIR"],
                !env.isEmpty
            {
                candidates.insert(URL(fileURLWithPath: env, isDirectory: true), at: 0)
            }

            let thisFile = URL(fileURLWithPath: #filePath)
            candidates.append(
                thisFile
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        "Resources/skill/\(skillFolderName)",
                        isDirectory: true
                    )
            )
        #endif

        let service = AssistantIntegrationService()
        for candidate in candidates {
            guard fm.fileExists(atPath: candidate.appendingPathComponent("SKILL.md").path) else {
                continue
            }
            return try service.verifiedSkillSource(candidate)
        }
        throw AssistantIntegrationError.sourceMissing(
            "\(skillFolderName)/SKILL.md"
        )
    }

    private static func inspectSynchronously(
        target: AssistantIntegrationTarget
    ) throws -> AssistantIntegrationInspection {
        try AssistantIntegrationService().inspect(
            target: target,
            source: resolveSkillSource()
        )
    }

    private static func makeSnapshot(
        target: AssistantIntegrationTarget,
        inspection: AssistantIntegrationInspection?,
        issue: AssistantIntegrationError?
    ) -> AgentSkillSnapshot {
        AgentSkillSnapshot(
            inspection: inspection,
            inspectionIssue: issue,
            presence: AgentPresence.detect(target),
            destinationParentExists: inspection.map {
                FileManager.default.fileExists(
                    atPath: $0.destination.deletingLastPathComponent().path
                )
            } ?? false
        )
    }
}

import Foundation

extension AssistantIntegrationService {
    public func destination(
        for target: AssistantIntegrationTarget,
        skillsDirectoryOverride: URL? = nil
    ) throws -> URL {
        if target == .openclaw {
            guard skillsDirectoryOverride == nil else {
                throw AssistantIntegrationError.unsafeDestination(skillsDirectoryOverride!.path)
            }
            return openClawSkillHome()
                .appendingPathComponent(Self.skillFolderName, isDirectory: true)
                .standardizedFileURL
        }

        let skillsDirectory: URL
        if let skillsDirectoryOverride {
            skillsDirectory = skillsDirectoryOverride.standardizedFileURL
        } else if target == .grok {
            guard let grokHomeDirectory else {
                throw AssistantIntegrationError.unsafeDestination("GROK_HOME")
            }
            skillsDirectory =
                grokHomeDirectory
                .appendingPathComponent("skills", isDirectory: true)
                .standardizedFileURL
        } else if let root = target.agentRootName {
            skillsDirectory =
                homeDirectory
                .appendingPathComponent(root, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .standardizedFileURL
        } else {
            throw AssistantIntegrationError.unsafeDestination(target.rawValue)
        }

        guard skillsDirectory.path != "/", !skillsDirectory.path.isEmpty else {
            throw AssistantIntegrationError.unsafeDestination(skillsDirectory.path)
        }
        let result =
            skillsDirectory
            .appendingPathComponent(Self.skillFolderName, isDirectory: true)
            .standardizedFileURL
        guard result.deletingLastPathComponent().path == skillsDirectory.path,
            result.lastPathComponent == Self.skillFolderName
        else {
            throw AssistantIntegrationError.unsafeDestination(result.path)
        }
        return result
    }

    public func inspect(
        target: AssistantIntegrationTarget,
        source: URL,
        skillsDirectoryOverride: URL? = nil
    ) throws -> AssistantIntegrationInspection {
        let source = try verifiedSkillSource(source)
        return try inspectVerified(
            target: target,
            source: source,
            skillsDirectoryOverride: skillsDirectoryOverride
        )
    }

    private func inspectVerified(
        target: AssistantIntegrationTarget,
        source: URL,
        skillsDirectoryOverride: URL?
    ) throws -> AssistantIntegrationInspection {
        let destination = try destination(for: target, skillsDirectoryOverride: skillsDirectoryOverride)
        let state = installationState(at: destination, source: source)
        let registered =
            target == .openclaw
            ? try openClawRegistration(configURL: openClawConfigURL(), skillHome: openClawSkillHome())
            : nil
        return AssistantIntegrationInspection(
            target: target,
            destination: destination,
            state: state,
            isRegistered: registered
        )
    }
}

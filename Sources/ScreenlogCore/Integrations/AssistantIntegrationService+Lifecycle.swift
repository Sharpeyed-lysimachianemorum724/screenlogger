import Foundation

extension AssistantIntegrationService {
    @discardableResult
    public func install(
        target: AssistantIntegrationTarget,
        source: URL,
        mode: AssistantIntegrationInstallMode,
        skillsDirectoryOverride: URL? = nil
    ) throws -> AssistantIntegrationChange {
        let source = try verifiedSkillSource(source)
        let destination = try destination(for: target, skillsDirectoryOverride: skillsDirectoryOverride)
        let state = installationState(at: destination, source: source)

        var openClawConfigurationSnapshot: Data?
        if target == .openclaw {
            let configURL = openClawConfigURL()
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                throw AssistantIntegrationError.configMissing(configURL.path)
            }
            // Validate before changing either the integration or registration.
            _ = try openClawRegistration(configURL: configURL, skillHome: openClawSkillHome())
            openClawConfigurationSnapshot = try Data(
                contentsOf: configURL,
                options: [.mappedIfSafe]
            )
        }

        let shouldPublish = try replacementDecision(state: state, mode: mode, path: destination.path)
        var changedURLs: [URL] = []
        var registrationChanged = false
        if target == .openclaw {
            let configURL = openClawConfigURL()
            if try updateOpenClawRegistration(
                configURL: configURL,
                skillHome: openClawSkillHome(),
                shouldRegister: true
            ) {
                registrationChanged = true
                changedURLs.append(configURL)
            }
        }

        do {
            if shouldPublish {
                try replaceSkill(
                    at: destination,
                    source: source,
                    removeExisting: state != .missing,
                    preferCopy: true,
                    allowUnowned: mode == .force
                )
                changedURLs.append(destination)
            }
        } catch {
            if registrationChanged, let snapshot = openClawConfigurationSnapshot {
                do {
                    try snapshot.write(to: openClawConfigURL(), options: .atomic)
                } catch {
                    throw AssistantIntegrationError.replacementFailed(
                        path: destination.path,
                        reason: "OpenClaw registration rollback failed"
                    )
                }
            }
            throw error
        }

        return AssistantIntegrationChange(
            inspection: try lifecycleInspection(
                target: target,
                source: source,
                skillsDirectoryOverride: skillsDirectoryOverride
            ),
            changedURLs: changedURLs
        )
    }

    @discardableResult
    public func remove(
        target: AssistantIntegrationTarget,
        source: URL?,
        allowUnowned: Bool = false,
        skillsDirectoryOverride: URL? = nil
    ) throws -> AssistantIntegrationChange {
        let unavailableSource = URL(
            fileURLWithPath: "/.screenlogger-integration-source-unavailable",
            isDirectory: true
        )
        let effectiveSource = source ?? unavailableSource
        let destination = try destination(for: target, skillsDirectoryOverride: skillsDirectoryOverride)
        let state = installationState(at: destination, source: effectiveSource)
        let configURL = target == .openclaw ? openClawConfigURL() : nil

        var openClawConfigurationSnapshot: Data?
        if let configURL, FileManager.default.fileExists(atPath: configURL.path) {
            _ = try openClawRegistration(configURL: configURL, skillHome: openClawSkillHome())
            openClawConfigurationSnapshot = try Data(
                contentsOf: configURL,
                options: [.mappedIfSafe]
            )
        }
        if state.requiresForce && !allowUnowned {
            throw AssistantIntegrationError.destinationNotOwned(destination.path)
        }

        var changedURLs: [URL] = []
        var registrationChanged = false
        if let configURL, FileManager.default.fileExists(atPath: configURL.path),
            try updateOpenClawRegistration(
                configURL: configURL,
                skillHome: openClawSkillHome(),
                shouldRegister: false
            )
        {
            registrationChanged = true
            changedURLs.append(configURL)
        }

        do {
            if state != .missing,
                try removeIntegrationNode(
                    at: destination,
                    source: effectiveSource,
                    allowUnowned: allowUnowned
                )
            {
                changedURLs.append(destination)
            }
        } catch {
            if registrationChanged, let snapshot = openClawConfigurationSnapshot {
                do {
                    try snapshot.write(to: openClawConfigURL(), options: .atomic)
                } catch {
                    throw AssistantIntegrationError.replacementFailed(
                        path: destination.path,
                        reason: "OpenClaw registration rollback failed"
                    )
                }
            }
            throw error
        }

        return AssistantIntegrationChange(
            inspection: try lifecycleInspection(
                target: target,
                source: effectiveSource,
                skillsDirectoryOverride: skillsDirectoryOverride
            ),
            changedURLs: changedURLs
        )
    }

    private func replacementDecision(
        state: AssistantIntegrationState,
        mode: AssistantIntegrationInstallMode,
        path: String
    ) throws -> Bool {
        switch state {
        case .missing:
            return true
        case .currentLink, .currentCopy:
            return mode == .reinstallOwned || mode == .force
        case .staleLink, .staleCopy:
            switch mode {
            case .upgrade, .reinstallOwned, .force: return true
            case .install: throw AssistantIntegrationError.destinationNeedsUpgrade(path)
            }
        case .brokenLink, .conflict:
            guard mode == .force else {
                throw AssistantIntegrationError.destinationNotOwned(path)
            }
            return true
        }
    }

    private func lifecycleInspection(
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

    /// Atomically retires the live integration name before recursively
    /// cleaning its contents. Ownership is rechecked immediately before the
    /// move so a conflict that appeared after inspection is preserved.
    private func removeIntegrationNode(
        at destination: URL,
        source: URL,
        allowUnowned: Bool
    ) throws -> Bool {
        let liveState = installationState(at: destination, source: source)
        guard liveState != .missing else { return false }
        if liveState.requiresForce, !allowUnowned {
            throw AssistantIntegrationError.destinationNotOwned(destination.path)
        }

        let retired = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(Self.skillFolderName).removed-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.moveItem(at: destination, to: retired)
        } catch {
            throw AssistantIntegrationError.replacementFailed(
                path: destination.path,
                reason: error.localizedDescription
            )
        }
        // A cleanup failure can leave only an inactive, uniquely named hidden
        // node. It cannot be discovered as the assistant integration.
        try? FileManager.default.removeItem(at: retired)
        return true
    }
}

import Darwin
import Foundation

private enum AssistantIntegrationFilesystemLimits {
    static let maximumManifestBytes = 1_048_576
    static let maximumSourceBytes: Int64 = 16 * 1_048_576
    static let maximumSourceEntries = 256
}

extension AssistantIntegrationService {
    public func installationState(at destination: URL, source: URL) -> AssistantIntegrationState {
        let fm = FileManager.default
        if let linkTarget = try? fm.destinationOfSymbolicLink(atPath: destination.path) {
            let targetURL =
                linkTarget.hasPrefix("/")
                ? URL(fileURLWithPath: linkTarget, isDirectory: true)
                : destination.deletingLastPathComponent()
                    .appendingPathComponent(linkTarget, isDirectory: true)
            let normalizedTarget = canonicalExistingURL(targetURL)
            let normalizedSource = canonicalExistingURL(source)
            guard fm.fileExists(atPath: normalizedTarget.path) else {
                return .brokenLink(linkTarget)
            }
            if normalizedTarget.path == normalizedSource.path { return .currentLink }
            return sourceTreeIsSafe(normalizedTarget)
                ? .staleLink(linkTarget)
                : .conflict
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue else { return .conflict }
        if directoriesMatch(source, destination) { return .currentCopy }
        return sourceTreeIsSafe(destination) ? .staleCopy : .conflict
    }

    public func replaceSkill(
        at destination: URL,
        source: URL,
        removeExisting: Bool,
        preferCopy: Bool = false,
        allowUnowned: Bool = false
    ) throws {
        let source = try verifiedSkillSource(source)
        let normalizedParent = canonicalURLPreservingMissingTail(
            destination.deletingLastPathComponent()
        )
        let normalizedDestination = normalizedParent.appendingPathComponent(
            destination.lastPathComponent,
            isDirectory: true
        )
        let normalizedSource = canonicalExistingURL(source)
        guard normalizedDestination.path != normalizedSource.path,
            !path(normalizedDestination, contains: normalizedSource),
            !path(normalizedSource, contains: normalizedDestination)
        else {
            throw AssistantIntegrationError.unsafeDestination(destination.path)
        }

        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(
            ".\(Self.skillFolderName).stage-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { if nodeExists(staged) { try? fm.removeItem(at: staged) } }

        if preferCopy {
            try fm.copyItem(at: source, to: staged)
        } else {
            do {
                try fm.createSymbolicLink(at: staged, withDestinationURL: source)
            } catch {
                try fm.copyItem(at: source, to: staged)
            }
        }

        // Verify the fixed staged tree rather than trusting a source that may
        // have changed during the copy. Durable-copy mode never publishes
        // nested symlinks or unsupported filesystem nodes. The explicit
        // legacy symlink mode remains available to API callers.
        let verifiedStage = try verifiedSkillSource(staged)
        if preferCopy, !directoriesMatch(source, verifiedStage) {
            throw AssistantIntegrationError.sourceMissing(source.path)
        }

        if !removeExisting {
            guard installationState(at: destination, source: source) == .missing else {
                throw AssistantIntegrationError.destinationNotOwned(destination.path)
            }
            do {
                try fm.moveItem(at: staged, to: destination)
            } catch {
                throw AssistantIntegrationError.replacementFailed(
                    path: destination.path,
                    reason: error.localizedDescription
                )
            }
            return
        }

        let liveState = installationState(at: destination, source: source)
        guard liveState != .missing else {
            throw AssistantIntegrationError.replacementFailed(
                path: destination.path,
                reason: "the destination changed before publication"
            )
        }
        if liveState.requiresForce, !allowUnowned {
            throw AssistantIntegrationError.destinationNotOwned(destination.path)
        }

        let result = staged.path.withCString { stagedPath in
            destination.path.withCString { destinationPath in
                renamex_np(stagedPath, destinationPath, UInt32(RENAME_SWAP))
            }
        }
        if result != 0 {
            let reason = String(cString: strerror(errno))
            throw AssistantIntegrationError.replacementFailed(
                path: destination.path,
                reason: reason
            )
        }
    }

    /// Resolves and validates a skill source before it can influence
    /// inspection or publication. The bounded tree may contain only regular
    /// files and directories; symlinks and special nodes are rejected.
    public func verifiedSkillSource(_ source: URL) throws -> URL {
        let resolved = canonicalExistingURL(source)
        guard isDirectoryNode(resolved), sourceTreeIsSafe(resolved) else {
            throw AssistantIntegrationError.sourceMissing(source.path)
        }
        return resolved
    }

    private func directoryLooksLikeScreenloggerSkill(_ directory: URL) -> Bool {
        let manifest = directory.appendingPathComponent("SKILL.md")
        guard isRegularNode(manifest),
            let size = try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > 0,
            size <= AssistantIntegrationFilesystemLimits.maximumManifestBytes,
            let data = try? Data(contentsOf: manifest, options: [.mappedIfSafe]),
            let text = String(data: data, encoding: .utf8)
        else { return false }
        let header = text.split(whereSeparator: \.isNewline).prefix(12)
        guard header.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return false
        }
        return header.dropFirst().contains {
            $0.trimmingCharacters(in: .whitespaces) == "name: \(Self.skillFolderName)"
        }
    }

    private func directoriesMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let leftFiles = recursiveFiles(in: lhs),
            let rightFiles = recursiveFiles(in: rhs),
            leftFiles == rightFiles
        else { return false }
        for relativePath in leftFiles {
            guard let left = try? Data(contentsOf: lhs.appendingPathComponent(relativePath)),
                let right = try? Data(contentsOf: rhs.appendingPathComponent(relativePath)),
                left == right
            else { return false }
        }
        return true
    }

    private func recursiveFiles(in root: URL) -> [String]? {
        let fm = FileManager.default
        let root = canonicalExistingURL(root)
        guard isDirectoryNode(root) else { return nil }
        var enumerationError: Error?
        guard
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ],
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else { return nil }
        var files: [String] = []
        var totalBytes: Int64 = 0
        var entryCount = 0
        for case let entry as URL in enumerator {
            entryCount += 1
            guard entryCount <= AssistantIntegrationFilesystemLimits.maximumSourceEntries,
                let values = try? entry.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]),
                values.isSymbolicLink != true
            else { return nil }
            if values.isRegularFile == true {
                totalBytes += Int64(values.fileSize ?? 0)
                guard totalBytes <= AssistantIntegrationFilesystemLimits.maximumSourceBytes else {
                    return nil
                }
                let relativePath = String(entry.path.dropFirst(root.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !relativePath.isEmpty else { return nil }
                files.append(relativePath)
            } else if values.isDirectory != true {
                return nil
            }
        }
        if enumerationError != nil { return nil }
        return files.sorted()
    }

    private func sourceTreeIsSafe(_ source: URL) -> Bool {
        guard directoryLooksLikeScreenloggerSkill(source), recursiveFiles(in: source) != nil else {
            return false
        }
        return true
    }

    private func isRegularNode(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func isDirectoryNode(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func canonicalExistingURL(_ url: URL) -> URL {
        guard let resolvedPath = realpath(url.path, nil) else {
            return url.standardizedFileURL
        }
        defer { free(resolvedPath) }
        return URL(fileURLWithPath: String(cString: resolvedPath), isDirectory: true)
    }

    private func canonicalURLPreservingMissingTail(_ url: URL) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while !nodeExists(existingAncestor), existingAncestor.path != "/" {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            existingAncestor = parent
        }
        return missingComponents.reduce(canonicalExistingURL(existingAncestor)) {
            partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func path(_ parent: URL, contains child: URL) -> Bool {
        let prefix = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        return child.path.hasPrefix(prefix)
    }

    private func nodeExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

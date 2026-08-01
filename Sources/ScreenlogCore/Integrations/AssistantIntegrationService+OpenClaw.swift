import Foundation

private enum AssistantIntegrationConfigurationLimits {
    static let maximumBytes = 4 * 1_048_576
}

extension AssistantIntegrationService {
    public func openClawSkillHome() -> URL {
        homeDirectory
            .appendingPathComponent(
                "Library/Application Support/dev.screenlog/skill",
                isDirectory: true
            )
            .standardizedFileURL
    }

    public func openClawConfigURL() -> URL {
        homeDirectory
            .appendingPathComponent(".openclaw/openclaw.json")
            .standardizedFileURL
    }

    public func openClawRegistration(configURL: URL, skillHome: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return false }
        let root = try readOpenClawConfig(configURL)
        guard let skillsValue = root["skills"] else { return false }
        guard let skills = skillsValue as? [String: Any] else {
            throw AssistantIntegrationError.malformedConfiguration("`skills` must be an object")
        }
        guard let loadValue = skills["load"] else { return false }
        guard let load = loadValue as? [String: Any] else {
            throw AssistantIntegrationError.malformedConfiguration("`skills.load` must be an object")
        }
        guard let dirsValue = load["extraDirs"] else { return false }
        guard let directories = dirsValue as? [String] else {
            throw AssistantIntegrationError.malformedConfiguration(
                "`skills.load.extraDirs` must be an array of strings"
            )
        }
        let wanted = normalizedPath(skillHome.path)
        return directories.contains { normalizedPath($0) == wanted }
    }

    @discardableResult
    public func updateOpenClawRegistration(
        configURL: URL,
        skillHome: URL,
        shouldRegister: Bool
    ) throws -> Bool {
        var root = try readOpenClawConfig(configURL)
        var skills = try object(root["skills"], key: "skills")
        var load = try object(skills["load"], key: "skills.load")
        var directories = try stringArray(
            load["extraDirs"],
            key: "skills.load.extraDirs"
        )

        let wanted = normalizedPath(skillHome.path)
        let filtered = directories.filter { normalizedPath($0) != wanted }
        directories = shouldRegister ? filtered + [skillHome.path] : filtered
        guard directories != (load["extraDirs"] as? [String] ?? []) else { return false }

        load["extraDirs"] = directories
        skills["load"] = load
        root["skills"] = skills
        let output = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard output.count <= AssistantIntegrationConfigurationLimits.maximumBytes else {
            throw AssistantIntegrationError.malformedConfiguration(
                "the updated configuration would exceed the supported size"
            )
        }
        try output.write(to: configURL, options: .atomic)
        return true
    }

    private func readOpenClawConfig(_ url: URL) throws -> [String: Any] {
        do {
            guard isRegularOpenClawConfigurationNode(url),
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size > 0,
                size <= AssistantIntegrationConfigurationLimits.maximumBytes
            else {
                throw AssistantIntegrationError.malformedConfiguration(
                    "the file is not a bounded regular file"
                )
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AssistantIntegrationError.malformedConfiguration(
                    "top-level JSON must be an object"
                )
            }
            return root
        } catch let error as AssistantIntegrationError {
            throw error
        } catch {
            throw AssistantIntegrationError.malformedConfiguration(
                "the file could not be read or parsed"
            )
        }
    }

    private func object(_ value: Any?, key: String) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let object = value as? [String: Any] else {
            throw AssistantIntegrationError.malformedConfiguration("`\(key)` must be an object")
        }
        return object
    }

    private func stringArray(_ value: Any?, key: String) throws -> [String] {
        guard let value else { return [] }
        guard let strings = value as? [String] else {
            throw AssistantIntegrationError.malformedConfiguration(
                "`\(key)` must be an array of strings"
            )
        }
        return strings
    }

    private func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func isRegularOpenClawConfigurationNode(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

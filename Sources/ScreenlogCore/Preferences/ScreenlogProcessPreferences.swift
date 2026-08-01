import Foundation

/// The preference domain owned by the current Screenlogger process.
///
/// Product builds always use the standard application domain. Debug routed UI tests
/// may use a dedicated suite only after every isolation boundary agrees: mode or
/// fixture, UUID token, suite name, data root, and fixed home directory.
/// Keeping this decision in ScreenlogCore prevents individual features from
/// accidentally falling back to a user's live preferences during UI tests.
public enum ScreenlogProcessPreferences {
    public static let current: UserDefaults = {
        #if DEBUG
            if let fixtureDefaults = routedUITestDefaults() {
                return fixtureDefaults
            }
        #endif
        return .standard
    }()

    #if DEBUG
        private static func routedUITestDefaults() -> UserDefaults? {
            let process = ProcessInfo.processInfo
            let environment = process.environment
            guard
                let suite = routedUITestSuiteName(
                    environment: environment,
                    arguments: process.arguments,
                    temporaryDirectory: FileManager.default.temporaryDirectory
                )
            else { return nil }

            return UserDefaults(suiteName: suite)
        }

        public static func routedUITestSuiteName(
            environment: [String: String],
            arguments: [String],
            temporaryDirectory: URL
        ) -> String? {
            let isRoutedTest = environment["SCREENLOG_UI_TEST_PREFERENCES_MODE"] == "isolated-v1"
            let isDeterministicFixture =
                environment["SCREENLOG_UI_TEST_FIXTURE"] == "deterministic-navigation-v1"
            guard isRoutedTest || isDeterministicFixture,
                let suite = environment["SCREENLOG_UI_TEST_PREFERENCES_SUITE"],
                let rootPath = environment["SCREENLOG_DATA_DIR"],
                let homePath = environment["CFFIXED_USER_HOME"],
                let tokenFlag = arguments.firstIndex(of: "--screenlogger-ui-test-token"),
                arguments.indices.contains(tokenFlag + 1)
            else { return nil }

            let token = arguments[tokenFlag + 1]
            guard UUID(uuidString: token) != nil,
                suite == "dev.screenlog.ui-tests.\(token)"
            else { return nil }

            let fixtureParent =
                temporaryDirectory
                .appendingPathComponent("screenlogger-ui-tests", isDirectory: true)
                .standardizedFileURL
            let expectedRoot =
                fixtureParent
                .appendingPathComponent(token, isDirectory: true)
                .standardizedFileURL
            let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            let expectedHome = root.appendingPathComponent("home", isDirectory: true).standardizedFileURL
            let home = URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL
            guard isAllowedRoutedTestRoot(root, expectedRoot: expectedRoot, token: token),
                home == expectedHome
            else { return nil }

            return suite
        }

        /// A macOS UI test runner and the launched app have different
        /// `temporaryDirectory` values. Accept the runner-owned container only
        /// at its fixed bundle-specific `Data/tmp` location; arbitrary app
        /// containers and lookalike directory names remain invalid.
        private static func isAllowedRoutedTestRoot(
            _ root: URL,
            expectedRoot: URL,
            token: String
        ) -> Bool {
            if root == expectedRoot { return true }

            let runnerSuffix =
                "/Library/Containers/dev.screenlog.ui-tests.xctrunner/Data/tmp/"
                + "screenlogger-ui-tests/\(token)"
            return root.path.hasSuffix(runnerSuffix)
        }
    #endif
}

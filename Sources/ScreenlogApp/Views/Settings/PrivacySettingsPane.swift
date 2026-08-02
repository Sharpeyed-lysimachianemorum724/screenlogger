import SwiftUI

/// Plain-language privacy status first, followed by permissions, protections,
/// network access, and local-data controls. Detailed implementation facts stay
/// behind disclosure controls so the default path remains easy to scan.
struct PrivacySettingsPane: View {
    @EnvironmentObject private var model: AppModel

    let openExclusions: () -> Void
    let openStorage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.cardSpacing) {
            if let issue = model.captureIssue {
                SLCaptureIssueBanner(issue: issue, context: "privacy")
            }

            PrivacyPermissionsSettingsSection()
                .settingsDestinationAnchor(.privacyPermissions)
            PrivacyProtectionSettingsSection(openExclusions: openExclusions)
                .settingsDestinationAnchor(.privacyProtection)
            PrivacyNetworkSettingsSection()
                .settingsDestinationAnchor(.privacyNetwork)
            PrivacyLocalDataSettingsSection(openStorage: openStorage)
                .settingsDestinationAnchor(.privacyLocalData)
        }
    }
}

import SwiftUI

/// Plain-language privacy status first, followed by permissions, protections,
/// network access, and local-data controls. Detailed implementation facts stay
/// behind disclosure controls so the default path remains easy to scan.
struct PrivacySettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    let openCapture: () -> Void
    let openExclusions: () -> Void
    let openStorage: () -> Void

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.cardSpacing) {
            PrivacyOverviewSettingsSection(
                isRefreshing: isRefreshing,
                openCapture: openCapture,
                openExclusions: openExclusions,
                openStorage: openStorage,
                refresh: refresh
            )

            if let issue = model.captureIssue {
                SLCaptureIssueBanner(issue: issue, context: "privacy")
            }

            PrivacyPermissionsSettingsSection(openCapture: openCapture)
                .settingsDestinationAnchor(.privacyPermissions)
            PrivacyProtectionSettingsSection(openExclusions: openExclusions)
                .settingsDestinationAnchor(.privacyProtection)
            PrivacyNetworkSettingsSection()
                .settingsDestinationAnchor(.privacyNetwork)
            PrivacyLocalDataSettingsSection(openStorage: openStorage)
                .settingsDestinationAnchor(.privacyLocalData)
        }
        .task { await refreshStatus(forcePermissions: false) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStatus(forcePermissions: true) }
        }
    }

    private func refresh() {
        Task { await refreshStatus(forcePermissions: true) }
    }

    private func refreshStatus(forcePermissions: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await model.refreshPermissions(force: forcePermissions)
        guard !Task.isCancelled else { return }
        await model.refreshData(light: true)
        guard !Task.isCancelled else { return }
        model.refreshLibrarySize()
    }
}

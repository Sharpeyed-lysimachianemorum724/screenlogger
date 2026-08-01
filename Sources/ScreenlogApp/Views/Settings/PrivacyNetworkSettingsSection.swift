import SwiftUI

struct PrivacyNetworkSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PrivacySettingsGroup("Network", systemImage: "network") {
            PrivacySettingsRow(
                icon: model.airgapMode ? "network.slash" : "network",
                iconColor: model.airgapMode ? SLDesign.success : .secondary,
                title: "Keep Screenlogger Offline",
                detail: model.airgapMode
                    ? "On. Optional network requests are blocked; capture, text recognition, and search keep working."
                    : "Off. Optional network access is available. Screenlogger fetches website icons only if you separately opt in below."
            ) {
                Toggle("Keep Screenlogger Offline", isOn: $model.airgapMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Keep Screenlogger Offline")
                    .accessibilityValue(SettingsAccessibilityValue.onOff(model.airgapMode))
                    .accessibilityHint("When on, Screenlogger does not make optional network requests")
                    .accessibilityIdentifier("privacy.network.offline.toggle")
            }
            .padding(14)

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: "photo.badge.arrow.down",
                title: "Fetch Website Icons",
                detail: websiteIconDetail
            ) {
                Toggle("Fetch Website Icons", isOn: $model.remoteFaviconsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.airgapMode)
                    .accessibilityLabel("Fetch Website Icons")
                    .accessibilityValue(
                        SettingsAccessibilityValue.onOff(model.remoteFaviconsEnabled)
                    )
                    .accessibilityHint(websiteIconToggleHint)
                    .accessibilityIdentifier("privacy.network.website-icons.toggle")
            }
            .padding(14)
        }
        .accessibilityIdentifier("privacy.network")
    }

    private var websiteIconDetail: String {
        if model.airgapMode {
            return "Blocked while offline mode is on. No website domain names are sent for icons."
        }
        if model.remoteFaviconsEnabled {
            return
                "On. Domains shown in Screenlogger are sent to DuckDuckGo's public icon service. Captures, recognized text, and full page addresses are not sent."
        }
        return "Off by default. Screenlogger uses only icons already cached on this Mac."
    }

    private var websiteIconToggleHint: String {
        if model.airgapMode {
            return "Unavailable while Keep Screenlogger Offline is on"
        }
        return "When on, website domain names are sent to DuckDuckGo's public icon service"
    }
}

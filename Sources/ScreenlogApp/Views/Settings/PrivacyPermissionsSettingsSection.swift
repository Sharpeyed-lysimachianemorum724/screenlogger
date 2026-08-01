import ScreenlogCore
import SwiftUI

struct PrivacyPermissionsSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsCaptureDetails = false

    let openCapture: () -> Void

    var body: some View {
        PrivacySettingsGroup("Permissions", systemImage: "checkmark.shield") {
            PrivacySettingsRow(
                icon: model.permissions.screenRecording ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                iconColor: model.permissions.screenRecording ? SLDesign.success : SLDesign.warning,
                title: "Screen Recording",
                detail: model.permissions.screenRecording
                    ? "Allowed. Screenlogger can capture the visible contents of one display."
                    : "Required before Screenlogger can save any screen captures."
            ) {
                if model.permissions.screenRecording {
                    PrivacyStatusLabel(text: "Allowed", systemImage: "checkmark")
                } else {
                    Button("Review Setup...") {
                        model.showPermissions(
                            origin: .settings,
                            preferredPermission: .screenRecording
                        )
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Review Screen Recording setup")
                    .accessibilityHint("Shows permission steps and a link to System Settings")
                }
            }
            .padding(14)
            .accessibilityIdentifier("privacy.permission.screen-recording")

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: model.permissions.accessibility
                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                iconColor: model.permissions.accessibility ? SLDesign.success : SLDesign.warning,
                title: "Accessibility",
                detail: accessibilityDetail
            ) {
                if model.permissions.accessibility {
                    PrivacyStatusLabel(text: "Allowed", systemImage: "checkmark")
                } else {
                    Button("Review Setup...") {
                        model.showPermissions(
                            origin: .settings,
                            preferredPermission: .accessibility
                        )
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Review Accessibility setup")
                    .accessibilityHint("Shows permission steps and a link to System Settings")
                }
            }
            .padding(14)
            .accessibilityIdentifier("privacy.permission.accessibility")

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: "display",
                title: "What Gets Captured",
                detail: "One display at a time, plus recognized text and available app context."
            ) {
                Button("Capture Settings...", action: openCapture)
                    .controlSize(.small)
                    .accessibilityHint("Shows capture quality, timing, and text recognition settings")
                    .accessibilityIdentifier("privacy.capture-settings")
            }
            .padding(14)

            DisclosureGroup("Capture details and limits", isExpanded: $showsCaptureDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "The display containing the frontmost window, including visible content and the pointer.",
                        systemImage: "display"
                    )
                    Label(
                        "Recognized text, window titles, and available browser addresses stay on this Mac.",
                        systemImage: "text.viewfinder"
                    )
                    Text(
                        "Accessibility access lets Screenlogger apply app and website exclusions and collect the window, control, browser, and private-window context used by capture."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .padding(.top, 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityIdentifier("privacy.capture-details")
        }
        .accessibilityIdentifier("privacy.permissions")
    }

    private var accessibilityDetail: String {
        if model.permissions.accessibility {
            return "Allowed for window titles, browser addresses, and focused-control text."
        }
        return "Required before capture starts so exclusions and app context are applied completely."
    }
}

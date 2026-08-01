import AppKit
import ScreenlogCore
import SwiftUI

/// A compact map for the temporary setup detour.
///
/// macOS permission changes happen in another app, so keeping both stages
/// visible prevents the System Settings trip from feeling like an unexplained
/// dead end. The final stage remains a choice: allowing permission never turns
/// capture on by itself.
struct PermissionsSetupProgress: View {
    let screenRecordingAllowed: Bool
    let accessibilityAllowed: Bool
    let currentPermission: ScreenlogPermission?
    let isRecording: Bool

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                stage(
                    title: "Screen Recording",
                    symbol: screenRecordingAllowed ? "checkmark.circle.fill" : "1.circle.fill",
                    state: permissionStageState(.screenRecording),
                    identifier: "setup.progress.permission"
                )

                Capsule()
                    .fill(screenRecordingAllowed ? SLDesign.success : Color.secondary.opacity(0.22))
                    .frame(maxWidth: 32)
                    .frame(height: 2)
                    .accessibilityHidden(true)

                stage(
                    title: "Accessibility",
                    symbol: accessibilityAllowed ? "checkmark.circle.fill" : "2.circle.fill",
                    state: permissionStageState(.accessibility),
                    identifier: "setup.progress.accessibility"
                )

                Capsule()
                    .fill(accessibilityAllowed ? SLDesign.success : Color.secondary.opacity(0.22))
                    .frame(maxWidth: 32)
                    .frame(height: 2)
                    .accessibilityHidden(true)

                stage(
                    title: "Capture Choice",
                    symbol: isRecording ? "checkmark.circle.fill" : "3.circle.fill",
                    state: isRecording
                        ? .complete
                        : (screenRecordingAllowed && accessibilityAllowed ? .current : .upcoming),
                    identifier: "setup.progress.capture"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(progressTitle, systemImage: progressSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(progressTitle)
        .accessibilityIdentifier("setup.progress")
    }

    private enum StageState {
        case current
        case complete
        case upcoming
    }

    private var progressTitle: String {
        if isRecording { return "Setup complete" }
        if screenRecordingAllowed, accessibilityAllowed { return "Step 3 of 3" }
        if screenRecordingAllowed { return "Step 2 of 3" }
        return "Step 1 of 3"
    }

    private var progressSymbol: String {
        isRecording ? "checkmark.circle.fill" : "list.number"
    }

    private func permissionStageState(_ permission: ScreenlogPermission) -> StageState {
        let allowed =
            switch permission {
            case .screenRecording: screenRecordingAllowed
            case .accessibility: accessibilityAllowed
            }
        if allowed { return .complete }
        return currentPermission == permission ? .current : .upcoming
    }

    private func stage(
        title: String,
        symbol: String,
        state: StageState,
        identifier: String
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(state == .current ? .semibold : .regular))
            .foregroundStyle(stageColor(state))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(stageAccessibilityValue(state))
            .accessibilityIdentifier(identifier)
    }

    private func stageColor(_ state: StageState) -> Color {
        switch state {
        case .current: return .accentColor
        case .complete: return SLDesign.success
        case .upcoming: return .secondary
        }
    }

    private func stageAccessibilityValue(_ state: StageState) -> String {
        switch state {
        case .current: return "Current step"
        case .complete: return "Complete"
        case .upcoming: return "Not started"
        }
    }
}

struct PermissionsPrivacySummary: View {
    private struct Fact {
        let title: String
        let symbol: String
        let identifier: String
    }

    private let facts = [
        Fact(title: "Saved on this Mac", symbol: "internaldrive", identifier: "setup.privacy.local"),
        Fact(
            title: "No camera or microphone",
            symbol: "mic.slash",
            identifier: "setup.privacy.no-sensors"
        ),
        Fact(
            title: "Pause or turn off anytime",
            symbol: "pause.circle",
            identifier: "setup.privacy.control"
        ),
    ]
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy on This Mac", systemImage: "lock.shield")
                .font(.headline)

            DisclosureGroup(isExpanded: $showingDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Screen Recording saves occasional still images. Accessibility applies exclusions and captures useful app context while capture is on."
                    )
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(facts, id: \.identifier) { fact in
                            Label(fact.title, systemImage: fact.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier(fact.identifier)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How Screenlogger uses these permissions")
                        .font(.callout.weight(.medium))
                    Text("Saved on this Mac, no camera or microphone, and controls you can change anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityHint("Show details about capture and privacy controls")
            .accessibilityIdentifier("setup.privacy-summary")
        }
        .padding(.horizontal, 4)
    }
}

struct PermissionsStatusCard: View {
    let screenRecordingAllowed: Bool
    let accessibilityAllowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("macOS Permissions", systemImage: "switch.2")
                .font(.headline)

            VStack(spacing: 0) {
                permissionRow(
                    title: "Screen Recording",
                    detail: "Required to save still images and recognize visible text.",
                    granted: screenRecordingAllowed,
                    required: true,
                    identifier: "setup.permission.screen-recording"
                )
                Divider()
                    .padding(.leading, 34)
                permissionRow(
                    title: "Accessibility",
                    detail: "Required so exclusions and app context are applied completely.",
                    granted: accessibilityAllowed,
                    required: true,
                    identifier: "setup.permission.accessibility"
                )
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 4)
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        required: Bool,
        identifier: String
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? SLDesign.success : (required ? SLDesign.warning : .secondary))
                .font(.body)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if granted {
                permissionStatus("Allowed", symbol: "checkmark", tint: SLDesign.success)
            } else {
                permissionStatus(
                    "Required",
                    symbol: "exclamationmark",
                    tint: SLDesign.warning
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func permissionStatus(
        _ title: String,
        symbol: String,
        tint: Color
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
    }
}

struct PermissionsNextActionCard: View {
    let screenRecordingAllowed: Bool
    let accessibilityAllowed: Bool
    let preferredPermission: ScreenlogPermission?
    let journeyState: PermissionJourneyState?
    let isRecording: Bool
    let timedPauseActive: Bool
    let captureStartFailed: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if targetPermission == .screenRecording {
                    instructionRow(1, screenRecordingFirstInstruction)
                    instructionRow(2, "Turn on Screenlogger in the list.")
                    instructionRow(3, "Return here. If macOS asks, choose Quit & Reopen.")
                } else if targetPermission == .accessibility {
                    instructionRow(1, accessibilityFirstInstruction)
                    instructionRow(2, "Turn on Screenlogger in the list.")
                    instructionRow(3, "Return here. Screenlogger checks automatically.")
                } else {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.next-action")
    }

    private var targetPermission: ScreenlogPermission? {
        if let preferredPermission {
            let preferredIsAllowed =
                switch preferredPermission {
                case .screenRecording: screenRecordingAllowed
                case .accessibility: accessibilityAllowed
                }
            if !preferredIsAllowed { return preferredPermission }
        }
        if !screenRecordingAllowed { return .screenRecording }
        if !accessibilityAllowed { return .accessibility }
        return nil
    }

    private var title: String {
        if let targetPermission { return "Allow \(targetPermission.title)" }
        if isRecording { return "Finish Setup" }
        if timedPauseActive { return "Resume or Keep Capture Off" }
        return captureStartFailed
            ? "Try Starting Capture Again"
            : "Choose Whether Capture Starts"
    }

    private var screenRecordingFirstInstruction: String {
        switch journeyState {
        case .awaitingSystemSettings, .restartRequired, .requesting, .verificationFailed:
            return "Choose Open Screen Recording Settings below."
        case .needsRequest, .ready, .none:
            return "Choose Allow Screen Recording below."
        }
    }

    private var accessibilityFirstInstruction: String {
        switch journeyState {
        case .awaitingSystemSettings, .restartRequired, .requesting, .verificationFailed:
            return "Choose Open Accessibility Settings below."
        case .needsRequest, .ready, .none:
            return "Choose Allow Accessibility below."
        }
    }

    private var symbol: String {
        if targetPermission == .screenRecording { return "arrow.up.forward.app" }
        if targetPermission == .accessibility { return "accessibility" }
        if isRecording { return "checkmark" }
        return "cursorarrow.click.2"
    }

    private var detail: String {
        if isRecording {
            return "Capture is already on. Choose Done to close setup."
        }
        if timedPauseActive {
            return "Resume now, or keep capture off. Your saved Library remains available either way."
        }
        if captureStartFailed {
            return "Choose Start Capture to try again. Capture remains off unless Screenlogger confirms it started."
        }
        return "Choose Start Capture to begin saving moments, or Keep Capture Off."
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PermissionsMissingAppHelp: View {
    @Binding var isExpanded: Bool
    let appURL: URL
    let appName: String
    let permission: ScreenlogPermission
    let settingsResult: PermissionSettingsOpenResult?
    let onRetry: () -> Void

    var body: some View {
        DisclosureGroup(
            "Screenlogger isn't listed in System Settings?",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(settingsResult?.instructions ?? manualInstructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PermissionDragDirection(permission: permission)
                AppBundleDragChip(
                    url: appURL,
                    displayName: appName,
                    permission: permission
                )

                HStack(spacing: 10) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("setup.reveal-app")

                    Button("Open \(permission.title) Again", action: onRetry)
                        .controlSize(.small)
                        .accessibilityIdentifier("setup.retry-settings")
                }
            }
            .padding(.top, 6)
        }
        .font(.caption.weight(.medium))
        .accessibilityHint("Shows help for adding Screenlogger to a macOS privacy list")
        .accessibilityIdentifier("setup.missing-app-help")
    }

    private var manualInstructions: String {
        "In System Settings, open \(permission.settingsPaneName). Use the Add button or drag Screenlogger into the list."
    }
}

private struct AppBundleDragChip: View {
    let url: URL
    let displayName: String
    let permission: ScreenlogPermission

    var body: some View {
        HStack(spacing: 10) {
            Image(
                nsImage: {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 32, height: 32)
                    return icon
                }()
            )
            .resizable()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("Drag into the \(permission.title) list")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onDrag {
            AppBundleDragProvider.make(for: url)
        }
        .contentShape(Rectangle())
        .help("Drag \(displayName) into the System Settings privacy list")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName) app")
        .accessibilityHint("Drag this app into the open System Settings privacy list")
        .accessibilityIdentifier("setup.drag-app.\(permission.rawValue)")
    }
}

private struct PermissionDragDirection: View {
    let permission: ScreenlogPermission

    var body: some View {
        HStack(spacing: 8) {
            Label("Drag from here", systemImage: "app.dashed")
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Label("Drop into \(permission.title)", systemImage: "list.bullet.rectangle")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drag Screenlogger from below into the \(permission.title) list in System Settings"
        )
        .accessibilityIdentifier("setup.drag-direction.\(permission.rawValue)")
    }
}

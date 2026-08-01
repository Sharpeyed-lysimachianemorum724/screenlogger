import ScreenlogCore
import SwiftUI

struct PrivacyOverviewSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    let isRefreshing: Bool
    let openCapture: () -> Void
    let openExclusions: () -> Void
    let openStorage: () -> Void
    let refresh: () -> Void

    var body: some View {
        PrivacySettingsGroup("Privacy at a Glance", systemImage: "hand.raised.fill") {
            PrivacySettingsRow(
                icon: "lock.shield.fill",
                iconColor: SLDesign.success,
                title: "Your Library stays on this Mac",
                detail: "Captures, recognized text, and search data stay on this Mac. Screenlogger has no cloud Library."
            ) {
                PrivacyStatusLabel(text: "On This Mac", systemImage: "checkmark")
            }
            .padding(14)
            .accessibilityIdentifier("privacy.overview.local")

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: status.symbolName,
                iconColor: status.tone.swiftUIColor,
                title: healthTitle,
                detail: healthDetail
            ) {
                healthAction
            }
            .padding(14)
            .accessibilityIdentifier("privacy.capture.status")

            if let stats = model.stats, stats.unfinalizedFrames > 0 {
                PrivacySettingsDivider()
                PrivacySettingsRow(
                    icon: "hourglass",
                    title: "Processing",
                    detail:
                        "\(stats.unfinalizedFrames) \(stats.unfinalizedFrames == 1 ? "capture is" : "captures are") waiting for compression. Your history remains available."
                ) {
                    PrivacyWorkingStatus()
                }
                .padding(14)
                .accessibilityIdentifier("privacy.capture.processing")
            }
        }
        .accessibilityIdentifier("privacy.overview")
    }

    @ViewBuilder
    private var healthAction: some View {
        switch status.primaryAction {
        case .retryLibrary:
            Button {
                performStatusAction(.retryLibrary)
            } label: {
                Text(status.actionLabel ?? "Try Again")
            }
            .controlSize(.small)
            .accessibilityLabel("Try opening the Library again")
            .accessibilityIdentifier("privacy.capture.library.retry")

        case .setupCapture(let permission):
            Button(status.actionLabel ?? "Review Setup...") {
                performStatusAction(.setupCapture(permission))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(status.actionHint ?? "Open \(permission.title) permission guidance")
            .accessibilityIdentifier("privacy.capture.setup")

        case .manageStorage:
            Button(status.actionLabel ?? "Storage Settings...", action: openStorage)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Review storage use and cleanup options")
                .accessibilityIdentifier("privacy.capture.storage")

        case .reviewWebsiteExclusions:
            Button(status.actionLabel ?? "Review Exclusions...", action: openExclusions)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Review strict website protection or allow Accessibility access")
                .accessibilityIdentifier("privacy.capture.exclusions")

        case .resumeCapture:
            Button(status.actionLabel ?? "Resume Capture") {
                performStatusAction(.resumeCapture)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(status.actionHint ?? "Resume automatic capture now")
            .accessibilityIdentifier("privacy.capture.resume")

        case .startCapture:
            Button(status.actionLabel ?? "Start Capture") {
                performStatusAction(.startCapture)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Start saving searchable captures")
            .accessibilityIdentifier("privacy.capture.start")

        case .retryCapture(let issue):
            Button(status.actionLabel ?? "Try Again") {
                performStatusAction(.retryCapture(issue))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(status.actionHint ?? "Try the failed capture action again")
            .accessibilityIdentifier("privacy.capture.retry")

        case nil:
            if status.tone == .working {
                PrivacyWorkingStatus()
            } else if case .automaticPause = status.phase {
                PrivacyStatusLabel(text: "Automatic", systemImage: "arrow.clockwise")
                    .accessibilityHint(
                        "Capture will resume automatically when protected or inactive activity ends"
                    )
            } else {
                Menu {
                    Button("Refresh Status", action: refresh)
                        .disabled(isRefreshing)
                    Button("Capture Settings...", action: openCapture)
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .slCompactControlTarget()
                .help("Privacy status options")
                .accessibilityLabel(
                    isRefreshing ? "Refreshing privacy status" : "Privacy status options"
                )
                .accessibilityIdentifier("privacy.capture.options")
            }
        }
    }

    private var healthTitle: String {
        status.headline
    }

    private var healthDetail: String {
        status.phase == .on ? newestCaptureDetail : status.detail
    }

    private var newestCaptureDetail: String {
        guard let timestamp = model.stats?.maxTimestampMs else {
            return "Capture is running. There are no saved moments in this Library yet."
        }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1_000)
        return "Capture is running. The newest saved moment is from \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    private var status: CaptureStatusPresentation {
        model.captureStatusPresentation()
    }

    private func performStatusAction(_ action: CaptureStatusPrimaryAction) {
        model.performCaptureStatusPrimaryAction(action, setupOrigin: .settings)
    }
}

private struct PrivacyWorkingStatus: View {
    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text("Working")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working")
    }
}

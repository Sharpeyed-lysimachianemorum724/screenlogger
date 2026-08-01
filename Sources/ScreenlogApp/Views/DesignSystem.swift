import ScreenlogCore
import SwiftUI

/// Small semantic tokens shared by Screenlogger's live macOS surfaces.
///
/// Prefer native controls and system materials first. These values exist to
/// keep spacing and status colors consistent, not to create custom web chrome.
enum SLDesign {
    /// Library and Timeline share one tested workspace floor so moving between
    /// primary surfaces never makes the window unexpectedly grow.
    static let workspaceMinimumWidth: CGFloat = 820
    static let workspaceMinimumHeight: CGFloat = 540
    static let workspaceMinimumSize = CGSize(
        width: workspaceMinimumWidth,
        height: workspaceMinimumHeight
    )

    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24

    /// Minimum pointer target for compact toolbar and icon-only controls.
    /// The symbol may remain visually smaller while the full target is easy
    /// to acquire with a mouse, trackpad, Switch Control, or Voice Control.
    static let compactControlTarget: CGFloat = 28

    static let radius: CGFloat = 10
    static let cardRadius: CGFloat = 10
    static let pillRadius: CGFloat = 14
    static let panelRadius: CGFloat = 12
    static let thumbRadius: CGFloat = 8

    static let success = Color(red: 0.20, green: 0.68, blue: 0.38)
    static let warning = Color(red: 0.94, green: 0.55, blue: 0.12)
    static let accentBlue = Color.accentColor
}

/// The three user-facing places someone can move between while Screenlogger
/// remains a menu-bar app. Keeping these routes in one control gives every
/// window the same names, symbols, accessibility identifiers, and behavior.
enum SLPrimarySurface: String, CaseIterable, Identifiable {
    case timeline
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "clock"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }

    var shortcutAction: KeyboardShortcutActionID {
        switch self {
        case .timeline: return .showTimeline
        case .library: return .showLibrary
        case .settings: return .showSettings
        }
    }
}

/// Compact, native buttons for moving between Screenlogger's primary windows.
/// Labels remain visible whenever space allows and fall back to icon-only
/// controls with the same accessible names in narrower layouts.
struct SLPrimaryNavigation: View {
    @EnvironmentObject private var model: AppModel

    let current: SLPrimarySurface

    private var destinations: [SLPrimarySurface] {
        switch current {
        case .timeline: return [.library, .settings]
        case .library: return [.timeline, .settings]
        case .settings: return [.library, .timeline]
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(labelStyle: .titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
            controls(labelStyle: .iconOnly)
                .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenlogger navigation")
        .accessibilityValue("Current location: \(current.title)")
        .accessibilityIdentifier("navigation.\(current.rawValue)")
    }

    private func controls(labelStyle: NavigationLabelStyle) -> some View {
        HStack(spacing: 10) {
            ForEach(destinations) { destination in
                navigationButton(destination, labelStyle: labelStyle)
            }
        }
    }

    private func navigationButton(
        _ destination: SLPrimarySurface,
        labelStyle: NavigationLabelStyle
    ) -> some View {
        let displayShortcut = model.keyboardShortcutDisplayLabel(for: destination.shortcutAction)
        let accessibilityShortcut = model.keyboardShortcutAccessibilityLabel(
            for: destination.shortcutAction
        )

        return Button {
            open(destination)
        } label: {
            if labelStyle == .titleAndIcon {
                Label(destination.title, systemImage: destination.systemImage)
            } else {
                Label(destination.title, systemImage: destination.systemImage)
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
        .slCompactControlTarget()
        .help("Show \(destination.title) (\(displayShortcut))")
        .accessibilityLabel("Show \(destination.title)")
        .accessibilityInputLabels([destination.title, "Show \(destination.title)"])
        .accessibilityHint("Shortcut: \(accessibilityShortcut)")
        .accessibilityIdentifier(
            "navigation.\(current.rawValue).\(destination.rawValue)"
        )
    }

    private func open(_ destination: SLPrimarySurface) {
        switch destination {
        case .timeline: model.openMainShell(origin: .direct)
        case .library:
            if model.timelineNavigationOrigin == .libraryResult {
                model.returnToLibrary()
            } else {
                model.openSearchWindow()
            }
        case .settings: model.openProductSettings()
        }
    }

    private enum NavigationLabelStyle: Equatable {
        case titleAndIcon
        case iconOnly
    }
}

/// Feature-owned capture recovery shared by surfaces that can start or resume
/// automatic capture. Expected privacy and disk pauses use their dedicated
/// status controls instead of appearing here as failures.
struct SLCaptureIssueBanner: View {
    @EnvironmentObject private var model: AppModel

    let issue: CaptureIssue
    let context: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SLDesign.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if issue.canRetry {
                Button("Retry") { model.retryCaptureIssue() }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("capture.issue.\(context).retry")
            }
            Button("Dismiss") { model.dismissCaptureIssue() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("capture.issue.\(context).dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SLDesign.warning.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.issue.\(context)")
    }
}

/// Compact product-wide capture status for native window toolbars.
/// The resolver owns state priority and copy; this view only maps its typed
/// semantics to SwiftUI controls and the initiating Setup return path.
struct SLCaptureStatusToolbarView: View {
    @EnvironmentObject private var model: AppModel

    let setupOrigin: CaptureSetupOrigin
    let accessibilityIdentifier: String

    var body: some View {
        let status = model.captureStatusPresentation()
        let toolbar = CaptureStatusToolbarResolver.resolve(status)
        Group {
            if let action = toolbar.action {
                Button {
                    perform(action)
                } label: {
                    Label(toolbar.title, systemImage: toolbar.symbolName)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(toolbar.title)
                .accessibilityValue(status.compactLabel)
                .accessibilityHint(toolbar.actionHint ?? status.detail)
            } else {
                Label(toolbar.title, systemImage: toolbar.symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(toolbar.title)
                    .accessibilityValue(status.compactLabel)
                    .accessibilityHint(status.detail)
            }
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(toolbar.actionHint ?? status.detail)
    }

    private func perform(_ action: CaptureStatusToolbarAction) {
        switch action {
        case .perform(let primaryAction):
            model.performCaptureStatusPrimaryAction(primaryAction, setupOrigin: setupOrigin)
        case .stopCapture:
            model.performKeyboardShortcutCaptureToggle()
        }
    }
}

extension CaptureStatusTone {
    var swiftUIColor: Color {
        switch self {
        case .success: return SLDesign.success
        case .warning: return SLDesign.warning
        case .working: return .accentColor
        case .neutral: return .secondary
        }
    }
}

extension View {
    /// Keeps compact controls native-looking without shrinking their hit area.
    func slCompactControlTarget() -> some View {
        frame(
            minWidth: SLDesign.compactControlTarget,
            minHeight: SLDesign.compactControlTarget
        )
        .contentShape(Rectangle())
    }

    /// A restrained adaptive surface for the few places that need grouping.
    func slElevatedPanel(radius: CGFloat = SLDesign.panelRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    /// Search presentation retained for compact floating search surfaces.
    func slSearchPill() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }

    /// A compact token for active refinements, with text remaining primary.
    func slQuietChip(selected: Bool) -> some View {
        font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
    }
}

import ScreenlogCore
import SwiftUI

/// A restrained, stage-appropriate presentation shared by Timeline states.
/// State views provide the outcome and actions while this shell keeps their
/// hierarchy, readable width, and contrast consistent.
struct TimelineStatePanel<Actions: View>: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let symbol: String
    let symbolColor: Color
    let title: String
    let detail: String
    @ViewBuilder let actions: Actions

    init(
        symbol: String,
        symbolColor: Color,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(symbolColor)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(secondaryTextOpacity))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            actions
        }
        .padding(28)
        .frame(maxWidth: 520)
        .foregroundStyle(.white.opacity(0.92))
        .accessibilityElement(children: .contain)
    }

    private var secondaryTextOpacity: Double {
        colorSchemeContrast == .increased ? 0.94 : 0.74
    }
}

/// Primary Timeline state surfaces used only when there is no usable moment to
/// keep on stage. Refresh failures with existing content stay compact banners.
struct TimelineLoadingStateView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                Text("Loading Timeline...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Opening your most recent captured moments.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(secondaryTextOpacity))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading Timeline")
            .accessibilityIdentifier("timeline.state.loading")
        }
    }

    private var secondaryTextOpacity: Double {
        colorSchemeContrast == .increased ? 0.92 : 0.72
    }
}

struct TimelineFailureStateView: View {
    let issue: TimelineIssue
    let onRetry: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        ZStack {
            Color.black
            TimelineStatePanel(
                symbol: "exclamationmark.triangle",
                symbolColor: SLDesign.warning,
                title: issue.title,
                detail: issue.message
            ) {
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("timeline.state.failure.retry")

                    Button(action: onOpenLibrary) {
                        Label("Open Library", systemImage: "books.vertical")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("timeline.state.failure.library")
                }
            }
            .accessibilityIdentifier("timeline.state.failure")
        }
    }
}

struct TimelineNavigationEmptyStateView: View {
    enum Context {
        case libraryResultUnavailable
        case selectedSessionUnavailable
    }

    @EnvironmentObject private var model: AppModel
    let context: Context
    let onReturnToLibrary: () -> Void
    let onShowRecent: () -> Void

    var body: some View {
        ZStack {
            Color.black
            TimelineStatePanel(
                symbol: symbol,
                symbolColor: model.accentSwiftUIColor,
                title: title,
                detail: detail
            ) {
                HStack(spacing: 12) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySymbol)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("timeline.empty.primary-action")

                    if context == .libraryResultUnavailable {
                        Button("Show Recent Timeline", action: onShowRecent)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("timeline.empty.show-recent")
                    }
                }
            }
            .accessibilityIdentifier("timeline.state.empty.navigation")
        }
    }

    private var title: String {
        switch context {
        case .libraryResultUnavailable: "This Moment Is No Longer Available"
        case .selectedSessionUnavailable: "No Moments in This Session"
        }
    }

    private var detail: String {
        switch context {
        case .libraryResultUnavailable:
            "It may have been removed by your storage settings. Your Library search and filters are still waiting for you."
        case .selectedSessionUnavailable:
            "This recorded session no longer contains moments. You can return to your recent Timeline."
        }
    }

    private var symbol: String {
        switch context {
        case .libraryResultUnavailable: "clock.badge.exclamationmark"
        case .selectedSessionUnavailable: "clock.badge.questionmark"
        }
    }

    private var primaryTitle: String {
        switch context {
        case .libraryResultUnavailable: "Back to Library"
        case .selectedSessionUnavailable: "Show Recent Timeline"
        }
    }

    private var primarySymbol: String {
        switch context {
        case .libraryResultUnavailable: "chevron.left"
        case .selectedSessionUnavailable: "clock.arrow.circlepath"
        }
    }

    private var primaryAction: () -> Void {
        context == .libraryResultUnavailable ? onReturnToLibrary : onShowRecent
    }
}

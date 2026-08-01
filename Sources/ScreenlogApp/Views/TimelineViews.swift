import AppKit
import ScreenlogCore
import SwiftUI

struct HistoryPane: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @State var showDayPicker = false
    @State var dayPickerSelection = Date()
    @State var timelineScaleStep = 0
    @State var timelineScrubWindow: TimelineRibbonMapping.Window?
    @State var hoveredTimelineFrameID: Int64?
    @State var stagePanOffset = CGSize.zero
    @State var stagePanGestureStart: CGSize?

    var body: some View {
        Group {
            if let issue = model.libraryStartupIssue {
                ZStack {
                    Color.black
                    LibraryStartupRecoveryView(issue: issue, surface: .timeline)
                }
            } else {
                timelineSurface
            }
        }
        .tint(model.accentSwiftUIColor)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .sheet(
            item: timelineDeletionReview,
            onDismiss: {
                model.cancelLibraryDeletionReview()
            }
        ) { review in
            LibraryDeletionReviewSheet(
                review: review,
                isDeleting: model.libraryDeletionInProgress,
                issue: reviewDeletionIssue,
                onDelete: { Task { await model.confirmLibraryDeletion() } },
                onCancel: { model.cancelLibraryDeletionReview() }
            )
        }
    }

    @ViewBuilder
    private var timelineSurface: some View {
        switch model.timelineContentState {
        case .loading:
            TimelineLoadingStateView()
        case .failed:
            TimelineFailureStateView(
                issue: model.timelineIssue ?? .refreshTimeline,
                onRetry: { Task { await model.retryTimelineLoad() } },
                onOpenLibrary: openLibraryFromFailure
            )
        case .empty(.captureState):
            timelineEmptyView
        case .empty(.libraryResultUnavailable):
            TimelineNavigationEmptyStateView(
                context: .libraryResultUnavailable,
                onReturnToLibrary: { model.returnToLibrary() },
                onShowRecent: showRecentTimeline
            )
        case .empty(.selectedSessionUnavailable):
            TimelineNavigationEmptyStateView(
                context: .selectedSessionUnavailable,
                onReturnToLibrary: { model.returnToLibrary() },
                onShowRecent: showRecentTimeline
            )
        case .content:
            timelineContentView
        }
    }

    private var timelineEmptyView: some View {
        ZStack {
            Color.black
            TimelineStatePanel(
                symbol: model.permissions.isCaptureReady
                    ? "rectangle.stack.badge.plus"
                    : "checkmark.shield",
                symbolColor: model.accentSwiftUIColor,
                title: timelineEmptyTitle,
                detail: timelineEmptyDetail
            ) {
                HStack(spacing: 12) {
                    Button {
                        if model.isRecording {
                            Task { await model.refreshData(light: false) }
                        } else if model.permissions.isCaptureReady {
                            model.toggleRecording()
                        } else {
                            model.showPermissions(
                                origin: .timeline,
                                preferredPermission: missingCapturePermission
                            )
                        }
                    } label: {
                        Label(
                            !model.permissions.isCaptureReady
                                ? "Allow \(missingCapturePermission?.title ?? "Required Permission")"
                                : model.isRecording ? "Refresh Timeline" : "Start Capture",
                            systemImage: !model.permissions.isCaptureReady
                                ? "checkmark.shield"
                                : model.isRecording ? "arrow.clockwise" : "record.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("timeline.empty.primary-action")

                    Button(model.permissions.isCaptureReady ? "Capture Settings" : "Privacy & Capture Settings") {
                        model.openProductSettings(
                            model.permissions.isCaptureReady
                                ? .captureStatus : .privacyPermissions
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("timeline.empty.settings")
                }
            }
            .accessibilityIdentifier("timeline.state.empty")
        }
    }

    private var timelineEmptyTitle: String {
        if let missingCapturePermission { return "Allow \(missingCapturePermission.title)" }
        return model.isRecording ? "Building Your Timeline" : "Your Timeline Starts Here"
    }

    private var timelineEmptyDetail: String {
        if !model.permissions.screenRecording {
            return "Screenlogger needs Screen Recording access before it can save your first moment."
        }
        if !model.permissions.accessibility {
            return "Screenlogger needs Accessibility access to apply exclusions and capture useful app context."
        }
        if model.isRecording {
            return "Capture is active. Your first searchable moment will appear shortly."
        }
        return "Start capture to build a private, searchable history on this Mac."
    }

    private var missingCapturePermission: ScreenlogPermission? {
        model.permissions.primaryMissingRequiredPermission
    }

    private var timelineContentView: some View {
        VStack(spacing: 0) {
            ZStack {
                memoryStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let issue = model.selectedFramePreviewIssue {
                    previewIssueView(issue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomChrome
                .frame(maxWidth: .infinity)
        }
    }

    private func showRecentTimeline() {
        Task { await model.showRecentTimeline() }
    }

    private func openLibraryFromFailure() {
        if model.timelineNavigationOrigin == .libraryResult {
            model.returnToLibrary()
        } else {
            model.openSearchWindow()
        }
    }

    private var reviewDeletionIssue: LibraryDeletionIssue? {
        guard let issue = model.libraryDeletionIssue,
            issue.origin == .timeline,
            case .deletionFailed = issue
        else { return nil }
        return issue
    }

    private var timelineDeletionReview: Binding<LibraryDeletionReview?> {
        Binding(
            get: {
                guard model.libraryDeletionReview?.origin == .timeline else { return nil }
                return model.libraryDeletionReview
            },
            set: { review in
                if review == nil { model.cancelLibraryDeletionReview() }
            }
        )
    }
}

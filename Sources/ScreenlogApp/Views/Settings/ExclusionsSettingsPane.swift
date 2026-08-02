import ScreenlogCore
import SwiftUI

/// Manages content that Screenlogger skips before saving a new moment.
///
/// Navigation and input state live here. The application and website flows are
/// separate views so each can stay focused and testable as those flows evolve.
struct ExclusionsSettingsPane: View {
    private enum Selection: Hashable {
        case applications
        case websites
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.settingsDestinationFocusRequest) private var destinationFocusRequest
    @State private var selection: Selection = .applications
    @State private var applicationQuery = ""
    @State private var websiteFilter = ""
    @State private var showingRestoreConfirmation = false
    @State private var applicationSearchFocusRequested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionControl
            scopeFootnote

            switch selection {
            case .applications:
                VStack(alignment: .leading, spacing: 20) {
                    applicationSearch
                    ExcludedApplicationsSettingsContent(
                        query: applicationQuery,
                        restoreDefaults: { showingRestoreConfirmation = true }
                    )
                }
                .settingsDestinationAnchor(
                    .exclusionsApplications,
                    focusesGroup: false
                )
            case .websites:
                ExcludedWebsitesSettingsContent(filterQuery: $websiteFilter)
                    .settingsDestinationAnchor(.exclusionsWebsites)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            async let applicationRefresh: Void = model.refreshDiscoveredApplications()
            await model.refreshRecordedDomains()
            await applicationRefresh
        }
        .onAppear {
            selectDestination(destinationFocusRequest?.anchor)
        }
        .onChange(of: destinationFocusRequest) { _, request in
            selectDestination(request?.anchor)
        }
        .confirmationDialog(
            "Restore default exclusions?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                model.restoreExclusionDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your custom app and website exclusions with Screenlogger's privacy defaults.")
        }
    }

    private func selectDestination(_ anchor: SettingsAnchor?) {
        switch anchor {
        case .exclusionsApplications:
            selection = .applications
            applicationSearchFocusRequested = false
            DispatchQueue.main.async {
                applicationSearchFocusRequested = true
            }
        case .exclusionsWebsites:
            selection = .websites
        default:
            break
        }
    }

    private var scopeFootnote: some View {
        Label(
            "Exclusions apply before a new moment is saved. Existing Library moments are unchanged.",
            systemImage: "hand.raised.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How exclusions work")
        .accessibilityHint("Excluded content is skipped before a new moment is saved. Existing Library moments are unchanged.")
        .accessibilityIdentifier("exclusions.scope-summary")
    }

    private var selectionControl: some View {
        Picker("Exclusion type", selection: $selection) {
            Label("Applications", systemImage: "app").tag(Selection.applications)
            Label("Websites", systemImage: "globe").tag(Selection.websites)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHint("Choose whether to manage application or website exclusions")
        .accessibilityIdentifier("exclusions.type")
    }

    private var applicationSearch: some View {
        NativeFilterSearchField(
            text: $applicationQuery,
            placeholder: "Find an application",
            accessibilityIdentifier: "exclusions.applications.search",
            accessibilityHelp: "Filters excluded and available applications.",
            focusRequested: $applicationSearchFocusRequested
        )
        .frame(height: 24)
    }
}

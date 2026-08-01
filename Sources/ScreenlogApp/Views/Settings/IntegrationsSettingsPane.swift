import ScreenlogCore
import SwiftUI

// MARK: - Integrations

/// Coordinates the Integrations settings journey while focused child views own
/// the presentation of connection, assistant, and recovery state.
struct IntegrationsSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingCLIRemoval = false
    @State private var pendingRemoval: AssistantIntegrationTarget?
    @State private var pendingResolution: AssistantIntegrationResolutionRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.cardSpacing) {
            LocalToolAccessSettingsSection(
                refresh: { model.refreshIntegrationSettings(automatic: false) },
                onRemove: { isConfirmingCLIRemoval = true }
            )
            .settingsDestinationAnchor(.integrationsLocalTools)

            AssistantIntegrationsSettingsSection(
                onRemove: { pendingRemoval = $0 },
                onResolve: { target, inspection in
                    pendingResolution = AssistantIntegrationResolutionRequest(
                        target: target,
                        inspection: inspection
                    )
                }
            )
            .settingsDestinationAnchor(.integrationsAssistantConnections)

        }
        .confirmationDialog(
            "Remove Terminal command?",
            isPresented: $isConfirmingCLIRemoval
        ) {
            Button("Remove Command", role: .destructive) {
                model.removeCLIFromLocalBin()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Screenlogger will remove the managed screenlog command and its runtime from ~/.local/bin. Your Library and captured history will remain unchanged. Terminal and assistant connections cannot search Screenlogger again until you reinstall the command."
            )
        }
        .confirmationDialog(
            "Remove assistant integration?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { target in
            Button("Remove from \(target.label)", role: .destructive) {
                model.removeAgentSkill(target)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { target in
            Text(
                "Screenlogger will remove only the connection files it manages for \(target.label). Your Library, captured history, Terminal command, and Command Access will remain unchanged."
            )
        }
        .sheet(item: $pendingResolution) { request in
            AssistantIntegrationResolutionSheet(
                target: request.target,
                initialInspection: request.inspection
            )
            .environmentObject(model)
        }
        .task {
            model.refreshIntegrationSettings(automatic: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refreshIntegrationSettings(automatic: true)
        }
    }
}

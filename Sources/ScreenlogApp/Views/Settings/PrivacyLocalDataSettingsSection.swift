import ScreenlogCore
import SwiftUI

struct PrivacyLocalDataSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsLibraryLocation = false

    let openStorage: () -> Void

    var body: some View {
        PrivacySettingsGroup("Library Data", systemImage: "internaldrive") {
            PrivacySettingsRow(
                icon: "folder",
                title: "Screenlogger Library",
                detail: "Captures, recognized text, and search data are stored in this folder."
            ) {
                Button("Show in Finder") { model.openDataFolder() }
                    .controlSize(.small)
                    .accessibilityHint("Opens the Screenlogger Library folder in Finder")
                    .accessibilityIdentifier("privacy.library.reveal")
            }
            .padding(14)

            DisclosureGroup("Show Library location", isExpanded: $showsLibraryLocation) {
                Text(model.libraryRootPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityLabel("Library location, \(model.libraryRootPath)")
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .accessibilityIdentifier("privacy.library.location")

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: "externaldrive.badge.timemachine",
                title: "Retention and Disk Use",
                detail: storageSummary
            ) {
                Button("Storage Settings...", action: openStorage)
                    .controlSize(.small)
                    .accessibilityHint("Shows Library size and retention settings")
                    .accessibilityIdentifier("privacy.storage.open")
            }
            .padding(14)
        }
        .accessibilityIdentifier("privacy.local-data")
    }

    private var storageSummary: String {
        let size = AppModel.formatByteSize(model.librarySizeBytes)
        switch model.storageMode {
        case .off:
            return "Using about \(size). History is kept until you remove it."
        case .compress:
            return "Using about \(size). Older captures are compressed automatically."
        case .limit:
            let sizeLimit =
                model.storageCapMB > 0
                ? " or when the Library approaches \(AppModel.formatByteSize(model.storageCapMB * 1_000_000))"
                : ""
            return
                "Using about \(size). Older capture media is removed after \(model.retentionDays) days\(sizeLimit); searchable text remains."
        }
    }
}

import ScreenlogCore
import SwiftUI

struct PrivacyProtectionSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    let openExclusions: () -> Void

    var body: some View {
        PrivacySettingsGroup("Protected Activity", systemImage: "eye.slash") {
            PrivacySettingsRow(
                icon: "app.badge.checkmark",
                title: "Excluded apps and websites",
                detail: exclusionSummary
            ) {
                Button("Manage Exclusions...", action: openExclusions)
                    .controlSize(.small)
                    .accessibilityHint("Shows the apps and detectable websites Screenlogger will not capture")
                    .accessibilityIdentifier("privacy.exclusions.manage")
            }
            .padding(14)

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: model.pauseWhenBrowserAddressUnavailable
                    ? "checkmark.shield.fill"
                    : "shield.lefthalf.filled",
                iconColor: model.pauseWhenBrowserAddressUnavailable ? SLDesign.success : .secondary,
                title: "When a website cannot be identified",
                detail: model.pauseWhenBrowserAddressUnavailable
                    ? "Supported browsers are skipped until their active website can be identified."
                    : "The browser may still be saved, so website exclusions cannot be guaranteed for that moment."
            ) {
                Button("Review...", action: openExclusions)
                    .controlSize(.small)
                    .accessibilityHint("Opens website exclusion protection settings")
                    .accessibilityIdentifier("privacy.exclusions.website-protection")
            }
            .padding(14)

            PrivacySettingsDivider()

            PrivacySettingsRow(
                icon: model.excludePrivateTabs ? "hand.raised.fill" : "hand.raised.slash",
                iconColor: model.excludePrivateTabs ? SLDesign.success : .secondary,
                title: "Private browsing windows",
                detail: model.excludePrivateTabs
                    ? "Skipped when a supported browser exposes a recognizable Private, Incognito, or InPrivate window."
                    : "Not skipped. Turn this protection on in Exclusions to omit detectable private windows."
            ) {
                PrivacyStatusLabel(
                    text: model.excludePrivateTabs ? "Skipped" : "Not skipped",
                    systemImage: model.excludePrivateTabs ? "checkmark" : "minus"
                )
            }
            .padding(14)

            Text(
                "Exclusions are checked before a frame is stored. Website and private-window protection can only act on information the active app and macOS make available."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .accessibilityLabel("About exclusion limits")
        }
        .accessibilityIdentifier("privacy.protection")
    }

    private var exclusionSummary: String {
        var protections: [String] = []
        if model.isExclusionCategoryEnabled(.passwordManagers) {
            protections.append("password managers")
        }
        if model.isExclusionCategoryEnabled(.banks) {
            protections.append("bank websites")
        }

        let systemIDs = Set(SystemExclusionApp.allCases.map { $0.rawValue.lowercased() })
        let passwordManagerIDs =
            model.isExclusionCategoryEnabled(.passwordManagers)
            ? Set(ExclusionCatalog.passwordManagerBundleIDs)
            : Set<String>()
        let appCount = model.excludedBundles.filter {
            !systemIDs.contains($0.lowercased())
                && !passwordManagerIDs.contains($0.lowercased())
        }.count
        let bankDomains =
            model.isExclusionCategoryEnabled(.banks)
            ? Set(ExclusionCatalog.bankDomains)
            : Set<String>()
        let siteCount = model.excludedDomains.filter { !bankDomains.contains($0) }.count

        var parts: [String] = []
        if !protections.isEmpty {
            parts.append("Built-in protection is on for \(Self.joinedList(protections))")
        }
        if appCount > 0 {
            parts.append("\(appCount) additional \(appCount == 1 ? "app is" : "apps are") excluded")
        }
        if siteCount > 0 {
            parts.append("\(siteCount) additional \(siteCount == 1 ? "website is" : "websites are") excluded")
        }
        return parts.isEmpty
            ? "No app or website exclusions are enabled."
            : parts.joined(separator: ". ") + "."
    }

    private static func joinedList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        if items.count == 1 { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}

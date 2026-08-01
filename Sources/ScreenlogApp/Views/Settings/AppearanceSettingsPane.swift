import ScreenlogCore
import SwiftUI

// MARK: - Appearance

struct AppearanceSettingsPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.cardSpacing) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCardRow(
                        icon: "circle.lefthalf.filled",
                        title: "Theme",
                        subtitle: themeSubtitle
                    ) {
                        Picker("Theme", selection: $model.appearancePreference) {
                            ForEach(AppearancePreference.allCases) { pref in
                                Text(pref.label).tag(pref)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        .accessibilityHint("Choose whether Screenlogger follows macOS or uses a light or dark theme")
                        .accessibilityIdentifier("settings.appearance.theme")
                    }

                    SettingsCardRow(
                        icon: "paintpalette",
                        title: "Accent Color",
                        subtitle: "\(model.accentColorPreference.label) highlights are used throughout Screenlogger."
                    ) {
                        Picker("Accent Color", selection: $model.accentColorPreference) {
                            ForEach(AccentColorPreference.allCases) { c in
                                Label {
                                    Text(c.label)
                                } icon: {
                                    AccentColorSwatch(preference: c)
                                }
                                .tag(c)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 140)
                        .accessibilityValue(model.accentColorPreference.label)
                        .accessibilityHint("Choose the highlight color used by Screenlogger")
                        .accessibilityIdentifier("settings.appearance.accent")
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Timeline Display")
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text("\(enabledTimelineOptionCount) of 4 on")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                "\(enabledTimelineOptionCount) of 4 Timeline options on"
                            )
                    }

                    Text(
                        "Choose which commands, highlights, and buttons appear in Timeline. Assigned Zoom and activity-navigation shortcuts keep working when their buttons are hidden."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    timelineToggle(
                        icon: "arrow.up.right.square",
                        title: "Open Source command",
                        subtitle: "Show Open Source in the Timeline's moment action menus.",
                        identifier: "open-source",
                        isOn: $model.showOpenExternally
                    )
                    timelineToggle(
                        icon: "text.viewfinder",
                        title: "Detected text highlights",
                        subtitle: "Show recognized-text highlights over the captured moment when available.",
                        identifier: "detected-text",
                        isOn: $model.showLiveText
                    )
                    timelineToggle(
                        icon: "plus.magnifyingglass",
                        title: "Zoom buttons",
                        subtitle: "Show zoom buttons. "
                            + hiddenControlsShortcutGuidance(
                                actionIDs: [
                                    .timelineZoomIn,
                                    .timelineZoomOut,
                                    .timelineResetZoom,
                                ]
                            ),
                        identifier: "zoom",
                        isOn: $model.showZoomControls
                    )
                    timelineToggle(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Activity navigation buttons",
                        subtitle: "Show buttons for jumping to the previous or next activity. "
                            + hiddenControlsShortcutGuidance(
                                actionIDs: [
                                    .timelinePreviousActivity,
                                    .timelineNextActivity,
                                ]
                            ),
                        identifier: "segment-navigation",
                        isOn: $model.showSegmentNavigation
                    )
                }
            }
            .accessibilityIdentifier("settings.appearance.timeline-controls")
        }
    }

    private var themeSubtitle: String {
        switch model.appearancePreference {
        case .system:
            return "Following this Mac's current appearance."
        case .light:
            return "Always using the Light appearance."
        case .dark:
            return "Always using the Dark appearance."
        }
    }

    private var enabledTimelineOptionCount: Int {
        [
            model.showOpenExternally,
            model.showLiveText,
            model.showZoomControls,
            model.showSegmentNavigation,
        ].filter { $0 }.count
    }

    private func hiddenControlsShortcutGuidance(
        actionIDs: [KeyboardShortcutActionID]
    ) -> String {
        let labels = actionIDs.compactMap {
            model.keyboardShortcutBinding(for: $0)?.displayLabel
        }
        guard !labels.isEmpty else {
            return "Assign shortcuts in Keyboard Shortcuts to use them while hidden."
        }

        let joined: String
        if labels.count == 1 {
            joined = labels[0]
        } else if labels.count == 2 {
            joined = labels.joined(separator: " and ")
        } else {
            let finalLabel = labels.last ?? ""
            joined = labels.dropLast().joined(separator: ", ") + ", and " + finalLabel
        }
        return "\(joined) still \(labels.count == 1 ? "works" : "work") when hidden."
    }

    private func timelineToggle(
        icon: String,
        title: String,
        subtitle: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsCardRow(icon: icon, title: title, subtitle: subtitle) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityHint(subtitle)
                .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
                .accessibilityIdentifier("settings.appearance.timeline.\(identifier)")
        }
    }
}

private struct AccentColorSwatch: View {
    let preference: AccentColorPreference

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 11, height: 11)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if preference == .system {
            return AnyShapeStyle(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center
                )
            )
        }
        return AnyShapeStyle(preference.swiftUIColor)
    }
}

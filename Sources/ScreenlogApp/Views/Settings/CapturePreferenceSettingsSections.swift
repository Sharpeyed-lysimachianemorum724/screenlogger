import AppKit
import ScreenlogCore
import SwiftUI

struct CaptureDisplaySettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var connectedDisplayCount = max(1, NSScreen.screens.count)

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCardRow(
                    icon: "rectangle.on.rectangle",
                    title: "Displays",
                    subtitle: CaptureDisplaySettingsCopy.summary(model.captureDisplayMode)
                ) {
                    EmptyView()
                }

                Picker("Displays to capture", selection: $model.captureDisplayMode) {
                    ForEach(CaptureDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Displays to capture")
                .accessibilityValue(model.captureDisplayMode.label)
                .accessibilityHint("Choose whether Screenlogger follows your active display or saves every connected display")
                .accessibilityIdentifier("capture.displays.picker")

                Label(
                    CaptureDisplaySettingsCopy.connectionNote(
                        model.captureDisplayMode,
                        count: connectedDisplayCount
                    ),
                    systemImage: connectedDisplayCount > 1 ? "display.2" : "display"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.captureDisplayMode == .all {
                    Divider()

                    Label(
                        "Excluded apps are removed from every display. If the active app, website, or private browser is protected, the entire moment is skipped.",
                        systemImage: "hand.raised"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture.displays.privacy-note")
                }
            }
        }
        .accessibilityIdentifier("capture.displays")
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            connectedDisplayCount = max(1, NSScreen.screens.count)
        }
    }
}

struct CaptureTimingSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsCard(padding: 0) {
            VStack(spacing: 0) {
                SettingsCardRow(
                    icon: "timer",
                    title: "Capture Interval",
                    subtitle: "How often Screenlogger saves a still while capture is on."
                ) {
                    Text(CaptureSettingsCopy.interval(model.intervalSeconds))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .padding(14)

                HStack(spacing: 10) {
                    Text("More often")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.intervalSeconds, in: 0.5...10, step: 0.5)
                        .accessibilityLabel("Capture interval")
                        .accessibilityValue(CaptureSettingsCopy.interval(model.intervalSeconds))
                        .accessibilityHint("Choose how often Screenlogger saves a still")
                        .accessibilityIdentifier("capture.interval.slider")
                    Text("Less often")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

                Divider().padding(.leading, SettingsChrome.rowSeparatorInset)

                SettingsCardRow(
                    icon: "moon.zzz",
                    title: "Pause When Inactive",
                    subtitle: model.pauseOnInactivity
                        ? "Stops saving after 5 minutes without keyboard or pointer activity, then resumes when you return."
                        : "Continues saving while this Mac is idle."
                ) {
                    Toggle("Pause When Inactive", isOn: $model.pauseOnInactivity)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Pause When Inactive")
                        .accessibilityValue(
                            SettingsAccessibilityValue.onOff(model.pauseOnInactivity)
                        )
                        .accessibilityHint("Pause after five minutes without keyboard or pointer activity")
                        .accessibilityIdentifier("capture.pause-on-inactivity.toggle")
                }
                .padding(14)
            }
        }
        .accessibilityIdentifier("capture.timing")
    }
}

struct CaptureImageSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAdvancedOptions = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCardRow(
                    icon: "camera.aperture",
                    title: "Image Quality",
                    subtitle: qualityHelp
                ) {
                    EmptyView()
                }

                Picker(
                    "Image quality",
                    selection: Binding(
                        get: { model.quality },
                        set: { model.setQuality($0) }
                    )
                ) {
                    ForEach(CaptureQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityHint("Higher quality uses more storage")
                .accessibilityIdentifier("capture.quality.picker")

                DisclosureGroup("Advanced image options", isExpanded: $showsAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Maximum image edge") {
                            Text(maximumImageEdgeLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("File format") {
                            Picker("File format", selection: $model.stillEncoding) {
                                ForEach(StillEncodingPreference.allCases) { encoding in
                                    Text(encoding.label).tag(encoding)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            .accessibilityHint("HEIC uses less storage; JPEG is easier to use outside Apple apps")
                            .accessibilityIdentifier("capture.encoding.picker")
                        }

                        Text("HEIC usually uses less storage. Choose JPEG if you often use exported stills outside Apple apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
                .accessibilityIdentifier("capture.image.advanced")
            }
        }
        .accessibilityIdentifier("capture.image")
    }

    private var qualityHelp: String {
        switch model.quality {
        case .standard: return "Standard keeps clear text while using less storage."
        case .high: return "High preserves Retina detail with moderate storage use."
        case .ultra: return "Ultra saves the display at native resolution with minimal compression."
        }
    }

    private var maximumImageEdgeLabel: String {
        if model.maxDimension == CaptureQuality.nativeResolutionMaxDimension {
            return "Native display resolution"
        }
        return "\(model.maxDimension) pixels"
    }
}

struct CaptureTextRecognitionSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAdvancedOptions = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardRow(
                    icon: "text.viewfinder",
                    title: "Text Recognition",
                    subtitle: "Makes captures searchable. Recognition runs on this Mac."
                ) {
                    Label("On", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Language and performance", isExpanded: $showsAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Recognition languages")
                                .font(.callout.weight(.medium))
                            TextField("Use system languages", text: $model.ocrLanguagesCSV)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Text recognition languages")
                                .accessibilityHint("Enter comma-separated language codes, or leave empty to use system languages")
                                .accessibilityIdentifier("capture.ocr.languages")
                            Text("Leave empty to use system languages. Advanced: enter language codes such as en-US or en-US, fr-FR.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SettingsCardRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Reuse Text From Similar Captures",
                            subtitle: model.differentialOCREnabled
                                ? "Reduces processing and battery use when very little on screen changed."
                                : "Recognizes all visible text again for every capture."
                        ) {
                            Toggle(
                                "Reuse Text From Similar Captures",
                                isOn: $model.differentialOCREnabled
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Reuse Text From Similar Captures")
                            .accessibilityValue(
                                SettingsAccessibilityValue.onOff(model.differentialOCREnabled)
                            )
                            .accessibilityHint("Reuse recognized text when consecutive captures are visually similar")
                            .accessibilityIdentifier("capture.ocr.differential.toggle")
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
                .accessibilityIdentifier("capture.ocr.advanced")
            }
        }
        .accessibilityIdentifier("capture.text-recognition")
    }
}

enum CaptureSettingsCopy {
    static func interval(_ seconds: Double) -> String {
        if seconds == floor(seconds) {
            return "Every \(Int(seconds)) \(Int(seconds) == 1 ? "second" : "seconds")"
        }
        return String(format: "Every %.1f seconds", seconds)
    }
}

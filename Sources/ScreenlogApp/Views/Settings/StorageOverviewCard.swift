import ScreenlogCore
import SwiftUI

/// A plain-language snapshot of what is stored and what automatic policy is active.
struct StorageOverviewCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardRow(
                    icon: "internaldrive",
                    title: "Library",
                    subtitle: "Current size, disk headroom, and growth at a glance."
                ) {
                    if model.storageMeasurementState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing storage information")
                    } else {
                        Button {
                            model.refreshLibrarySize()
                        } label: {
                            Label("Refresh storage information", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .slCompactControlTarget()
                        .help("Refresh storage information")
                        .accessibilityIdentifier("settings.storage.refresh-size")
                        .accessibilityHint("Recalculate Library size and available disk space")
                    }
                }
                .padding(14)

                Divider().padding(.leading, 58)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        metrics
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        metrics
                    }
                }
                .padding(14)

                Divider().padding(.leading, 58)

                VStack(alignment: .leading, spacing: 7) {
                    Label(forecastSummary, systemImage: forecastSystemImage)
                    Label(lastRefreshSummary, systemImage: "clock")
                    if case .failed = model.storageMeasurementState {
                        Label(
                            "Storage information could not be refreshed. The previous measurement is still shown.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                    Label(storagePolicySummary, systemImage: policySystemImage)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.storage.summary")
    }

    @ViewBuilder
    private var metrics: some View {
        StorageMetricView(
            value: measurement.map { AppModel.formatByteSize($0.libraryBytes) } ?? "-",
            label: "Space used"
        )
        StorageMetricView(
            value: measurement.flatMap(\.availableBytes).map { AppModel.formatByteSize($0) } ?? "-",
            label: "Available on Mac"
        )
        StorageMetricView(
            value: growthValue,
            label: "Recent change"
        )
        StorageMetricView(
            value: savedMomentsValue,
            label: "Saved moments"
        )
        if let stats = model.stats, stats.unfinalizedFrames > 0 {
            StorageMetricView(
                value: stats.unfinalizedFrames.formatted(),
                label: "Finishing compression"
            )
        }
    }

    private var savedMomentsValue: String {
        guard let stats = model.stats else { return "-" }
        return stats.totalFrames.formatted()
    }

    private var measurement: StorageMeasurement? {
        model.storageMeasurementState.measurement
    }

    private var growthValue: String {
        guard let delta = measurement?.growth?.byteDelta else { return "-" }
        if delta == 0 { return "No change" }
        let magnitude = delta == Int64.min ? Int64.max : abs(delta)
        return (delta > 0 ? "+" : "-") + AppModel.formatByteSize(magnitude)
    }

    private var lastRefreshSummary: String {
        guard let measuredAt = measurement?.measuredAt else {
            return model.storageMeasurementState.isLoading
                ? "Measuring storage..."
                : "Storage has not been measured yet"
        }
        return "Last refreshed " + measuredAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var forecast: StorageLimitForecast {
        StorageLimitForecast.make(
            mode: model.storageMode,
            storageCapMB: model.storageCapMB,
            measurement: measurement
        )
    }

    private var forecastSummary: String {
        switch forecast {
        case .automaticCleanupOff:
            return "No automatic storage limit is active"
        case .compressionOnly:
            return "Compression reduces growth without a fixed size target"
        case .ageLimitOnly:
            return "The age limit is active; no Library size limit is set"
        case .needsGrowthHistory:
            return "Size forecast needs measurements at least 15 minutes apart"
        case .stableOrShrinking:
            return "No approach to the size limit is forecast from recent change"
        case .atOrAboveLimit(let bytes):
            if bytes == 0 { return "The Library is at its current size limit" }
            return "The Library is " + AppModel.formatByteSize(bytes) + " over its current size limit"
        case .estimatedTimeToLimit(let interval):
            return "Estimated " + Self.forecastDuration(interval) + " until the current size limit"
        }
    }

    private var forecastSystemImage: String {
        switch forecast {
        case .atOrAboveLimit: return "exclamationmark.circle"
        case .estimatedTimeToLimit: return "chart.line.uptrend.xyaxis"
        case .stableOrShrinking: return "checkmark.circle"
        default: return "gauge.with.dots.needle.50percent"
        }
    }

    private static func forecastDuration(_ interval: TimeInterval) -> String {
        let rawDays = interval / 86_400
        guard rawDays < Double(Int.max) else { return "many years" }
        let days = max(0, Int(rawDays))
        if days < 1 { return "less than a day" }
        if days < 14 { return "about \(days) days" }
        if days < 60 { return "about \(max(2, days / 7)) weeks" }
        return "about \(max(2, days / 30)) months"
    }

    private var storagePolicySummary: String {
        switch model.storageMode {
        case .off:
            return "Automatic cleanup is off. Screenlogger keeps your history until you remove it."
        case .compress:
            return "Older capture images are compressed automatically without deleting searchable history."
        case .limit:
            if model.storageCapMB > 0 {
                return
                    "Capture media is removed after \(model.retentionDays) days or when the Library exceeds "
                    + "\(StorageSizeInput.formattedCap(model.storageCapMB)). Searchable history remains."
            }
            return "Capture media is removed after \(model.retentionDays) days. Searchable history remains."
        }
    }

    private var policySystemImage: String {
        switch model.storageMode {
        case .off: return "archivebox"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .limit: return "gauge.with.dots.needle.50percent"
        }
    }
}

private struct StorageMetricView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

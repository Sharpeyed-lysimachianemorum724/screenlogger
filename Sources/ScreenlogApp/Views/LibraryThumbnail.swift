import AppKit
import ImageIO
import ScreenlogCore
import SwiftUI

/// A display-sized still for Library cards and the inspector.
///
/// `NSImage(contentsOfFile:)` leaves full-resolution captures available for decoding, which
/// can briefly multiply memory use while a grid is scrolling. ImageIO instead creates a
/// thumbnail close to the view's backing-pixel size. SwiftUI cancels the task when a lazy-grid
/// cell leaves the viewport; the cancellation handler also cancels the detached decode worker.
struct LibraryThumbnail: View {
    let path: String?
    var isCompacted = false
    var contentMode: ContentMode = .fill
    var showsStatusDetail = false
    var statusAccessibilityIdentifier = ""

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    @ViewBuilder
    var body: some View {
        if showsStatusDetail {
            VStack(alignment: .leading, spacing: 9) {
                thumbnailViewport
                    .aspectRatio(16 / 10, contentMode: .fit)

                if let previewStatus {
                    statusDetail(previewStatus)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHidden(previewStatus == nil)
            .accessibilityLabel(previewStatus?.accessibilityLabel ?? "")
            .accessibilityIdentifier(statusAccessibilityIdentifier)
        } else {
            thumbnailViewport
                .accessibilityElement(children: .combine)
                .accessibilityHidden(previewStatus == nil)
                .accessibilityLabel(previewStatus?.accessibilityLabel ?? "")
                .accessibilityIdentifier(statusAccessibilityIdentifier)
        }
    }

    private var thumbnailViewport: some View {
        GeometryReader { geometry in
            thumbnailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .task(id: requestKey(for: geometry.size)) {
                    await loadImage(for: geometry.size)
                }
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let loadedImage {
            Image(nsImage: loadedImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
        } else if let previewStatus {
            placeholder(previewStatus)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private func placeholder(_ status: PreviewStatus) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            VStack(spacing: 5) {
                Image(systemName: status.systemImage)
                    .font(.system(size: showsStatusDetail ? 24 : 17, weight: .regular))
                if !showsStatusDetail {
                    Text(status.title)
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.secondary)
            .padding(12)
        }
    }

    private func statusDetail(_ status: PreviewStatus) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(.secondary)
        }
    }

    private var previewStatus: PreviewStatus? {
        if isCompacted {
            return .availableInTimeline
        }
        if path == nil || path?.isEmpty == true {
            return .noLongerStored
        }
        return loadFailed ? .unavailable : nil
    }

    private func requestKey(for size: CGSize) -> String {
        "\(path ?? "")|\(targetMaxPixelSize(for: size))|\(isCompacted)"
    }

    private func targetMaxPixelSize(for size: CGSize) -> Int {
        let exactPixels = max(size.width, size.height) * max(displayScale, 1)
        guard exactPixels.isFinite, exactPixels > 0 else { return 0 }
        // Small resize changes should reuse the same decoded thumbnail.
        return Int(ceil(exactPixels / 32)) * 32
    }

    @MainActor
    private func loadImage(for size: CGSize) async {
        loadedImage = nil
        loadFailed = false

        guard !isCompacted,
            let path,
            !path.isEmpty
        else { return }

        let maxPixelSize = targetMaxPixelSize(for: size)
        guard maxPixelSize > 0 else { return }

        let scale = max(displayScale, 1)
        let worker = Task.detached(priority: .utility) {
            try LibraryThumbnailRenderer.image(
                at: path,
                maxPixelSize: maxPixelSize,
                displayScale: scale
            )
        }

        var image: NSImage?
        do {
            image = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            image = nil
        }

        guard !Task.isCancelled else { return }
        loadedImage = image
        loadFailed = image == nil
    }
}

private enum PreviewStatus {
    case availableInTimeline
    case noLongerStored
    case unavailable

    var systemImage: String {
        switch self {
        case .availableInTimeline: "film.stack"
        case .noLongerStored: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .unavailable: "photo.badge.exclamationmark"
        }
    }

    var title: String {
        switch self {
        case .availableInTimeline: "Preview available in Timeline"
        case .noLongerStored: "Preview no longer stored"
        case .unavailable: "Preview unavailable"
        }
    }

    var detail: String {
        switch self {
        case .availableInTimeline: "Opening this moment requests its preview."
        case .noLongerStored: "Searchable text and details are still available."
        case .unavailable: "The captured image could not be loaded."
        }
    }

    var accessibilityLabel: String {
        "\(title). \(detail)"
    }
}

private enum LibraryThumbnailRenderer {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(
        at path: String,
        maxPixelSize: Int,
        displayScale: CGFloat
    ) throws -> NSImage? {
        try Task.checkCancellation()

        let cacheKey = "\(path)|\(maxPixelSize)" as NSString
        if let image = cache.object(forKey: cacheKey) {
            return image
        }

        let cgImage = try ScreenlogPerformanceSignposts.measure(.firstThumbnailDecode) {
            let url = URL(fileURLWithPath: path)
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                return nil as CGImage?
            }

            try Task.checkCancellation()
            let thumbnailOptions =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
        }
        guard let cgImage else { return nil }

        try Task.checkCancellation()
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / displayScale,
                height: CGFloat(cgImage.height) / displayScale
            )
        )
        let byteCost = min(Int.max, cgImage.bytesPerRow * cgImage.height)
        cache.setObject(image, forKey: cacheKey, cost: byteCost)
        return image
    }
}

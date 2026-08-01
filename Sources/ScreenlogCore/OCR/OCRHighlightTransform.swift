import CoreGraphics
import Foundation

/// Projects top-left-origin OCR pixel rectangles into a centered, aspect-fit preview.
///
/// Persisted `OCRBox` values already convert Vision's bottom-left normalized coordinates into
/// original-image pixels. Timeline previews are downsampled independently, so callers must pass
/// the original capture size rather than the preview bitmap size. Zoom matches SwiftUI's default
/// centered `scaleEffect`. `contentOffset` follows a subsequently applied SwiftUI `offset`, and
/// returned rectangles are clipped to both source and viewport bounds.
public struct OCRHighlightTransform: Sendable {
    public let sourceSize: CGSize
    public let viewportSize: CGSize
    public let zoom: CGFloat
    public let contentOffset: CGSize

    public init(
        sourceSize: CGSize,
        viewportSize: CGSize,
        zoom: CGFloat = 1,
        contentOffset: CGSize = .zero
    ) {
        self.sourceSize = sourceSize
        self.viewportSize = viewportSize
        self.zoom = zoom
        self.contentOffset = contentOffset
    }

    /// The image's rendered rectangle before viewport clipping. At zoom > 1 it can extend beyond
    /// the viewport; at zoom < 1 it remains centered with additional letterboxing.
    public var renderedContentRect: CGRect? {
        guard Self.isValid(sourceSize),
            Self.isValid(viewportSize),
            zoom.isFinite,
            zoom > 0,
            Self.isFinite(contentOffset)
        else {
            return nil
        }

        let fitScale = min(
            viewportSize.width / sourceSize.width,
            viewportSize.height / sourceSize.height
        )
        let scale = fitScale * zoom
        guard scale.isFinite, scale > 0 else { return nil }
        let renderedSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        guard Self.isValid(renderedSize) else { return nil }
        return CGRect(
            x: (viewportSize.width - renderedSize.width) / 2 + contentOffset.width,
            y: (viewportSize.height - renderedSize.height) / 2 + contentOffset.height,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    public func project(_ box: OCRBox) -> CGRect? {
        guard box.width > 0, box.height > 0 else { return nil }
        return project(
            CGRect(
                x: box.x,
                y: box.y,
                width: box.width,
                height: box.height
            )
        )
    }

    public func project(_ sourceRect: CGRect) -> CGRect? {
        guard let renderedContentRect,
            Self.isFinite(sourceRect),
            sourceRect.size.width > 0,
            sourceRect.size.height > 0
        else {
            return nil
        }

        let sourceBounds = CGRect(origin: .zero, size: sourceSize)
        let sourceClipped = sourceRect.intersection(sourceBounds)
        guard !sourceClipped.isNull,
            sourceClipped.width > 0,
            sourceClipped.height > 0
        else {
            return nil
        }

        let scale = renderedContentRect.width / sourceSize.width
        let projected = CGRect(
            x: renderedContentRect.minX + sourceClipped.minX * scale,
            y: renderedContentRect.minY + sourceClipped.minY * scale,
            width: sourceClipped.width * scale,
            height: sourceClipped.height * scale
        )
        guard Self.isFinite(projected) else { return nil }
        let viewportBounds = CGRect(origin: .zero, size: viewportSize)
        let visible = projected.intersection(viewportBounds)
        guard !visible.isNull,
            visible.width > 0,
            visible.height > 0
        else {
            return nil
        }
        return visible
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
    }

    private static func isFinite(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
    }
}

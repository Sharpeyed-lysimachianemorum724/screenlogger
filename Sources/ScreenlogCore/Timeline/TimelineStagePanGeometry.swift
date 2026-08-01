import Foundation

/// Pure geometry for panning a centered, aspect-fit Timeline capture after zooming.
public enum TimelineStagePanGeometry {
    /// Maximum absolute x/y offsets that keep the rendered capture touching the viewport edge.
    public static func offsetBounds(
        sourceSize: CGSize,
        viewportSize: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        guard isValid(sourceSize), isValid(viewportSize), zoom.isFinite, zoom > 1 else {
            return .zero
        }

        let fitScale = min(
            viewportSize.width / sourceSize.width,
            viewportSize.height / sourceSize.height
        )
        let renderedWidth = sourceSize.width * fitScale * zoom
        let renderedHeight = sourceSize.height * fitScale * zoom
        guard renderedWidth.isFinite, renderedHeight.isFinite else { return .zero }

        return CGSize(
            width: max(0, (renderedWidth - viewportSize.width) / 2),
            height: max(0, (renderedHeight - viewportSize.height) / 2)
        )
    }

    public static func clampedOffset(
        _ proposedOffset: CGSize,
        sourceSize: CGSize,
        viewportSize: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        guard proposedOffset.width.isFinite, proposedOffset.height.isFinite else { return .zero }
        let bounds = offsetBounds(
            sourceSize: sourceSize,
            viewportSize: viewportSize,
            zoom: zoom
        )
        return CGSize(
            width: min(bounds.width, max(-bounds.width, proposedOffset.width)),
            height: min(bounds.height, max(-bounds.height, proposedOffset.height))
        )
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

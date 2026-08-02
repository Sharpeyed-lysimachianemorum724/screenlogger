import Foundation

/// One size contract for the app-owned Settings workspace.
///
/// Settings can be opened from much larger Library and Timeline windows, but
/// it should remain a compact preference workspace. Keeping this policy pure
/// makes legacy frame restoration deterministic and independently testable.
enum SettingsWindowLayout {
    static let minimumContentSize = CGSize(width: 820, height: 540)
    static let defaultContentSize = CGSize(width: 860, height: 600)
    static let maximumContentWidth: CGFloat = 980

    static func constrainedContentSize(_ proposed: CGSize) -> CGSize {
        CGSize(
            width: min(
                max(proposed.width, minimumContentSize.width),
                maximumContentWidth
            ),
            height: max(proposed.height, minimumContentSize.height)
        )
    }

    static func centeredOriginX(
        originalFrame: CGRect,
        constrainedFrameWidth: CGFloat
    ) -> CGFloat {
        originalFrame.midX - constrainedFrameWidth / 2
    }
}

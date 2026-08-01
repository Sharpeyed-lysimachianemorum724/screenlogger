import Foundation
import ScreenlogCore

struct LibraryRestoreReview: Identifiable, Equatable, Sendable {
    let archive: URL
    let manifest: LibraryExportManifest

    var id: URL { archive }
}

enum LibraryRestoreOperationState: Equatable, Sendable {
    case idle
    case validating
    case ready
    case restoring
    case completed
    case failed(LibraryRestoreError)

    var isBusy: Bool { self == .validating || self == .restoring }
}

import Foundation
import ScreenlogCore

enum LibraryDeletionOrigin: Sendable, Equatable {
    case timeline
    case storage
}

struct LibraryDeletionRequest: Sendable {
    let selection: LibraryDeletionSelection
    let origin: LibraryDeletionOrigin
    let title: String
    let detail: String
}

struct LibraryDeletionReview: Identifiable, Sendable {
    let origin: LibraryDeletionOrigin
    let title: String
    let detail: String
    let plan: LibraryDeletionPlan
    let captureWasPaused: Bool

    var id: UUID { plan.reviewID }
}

struct LibraryDeletionSuccess: Equatable, Sendable {
    let deletedFrameCount: Int
    let freedBytes: Int64
    let cleanupPending: Bool
}

enum LibraryDeletionIssue: Sendable {
    case preparationFailed(LibraryDeletionRequest)
    case nothingToDelete(LibraryDeletionRequest)
    case reviewExpired(LibraryDeletionRequest)
    case deletionFailed(LibraryDeletionReview)
    case captureCouldNotPause(LibraryDeletionRequest)

    var origin: LibraryDeletionOrigin {
        switch self {
        case .preparationFailed(let request),
            .nothingToDelete(let request),
            .reviewExpired(let request),
            .captureCouldNotPause(let request):
            return request.origin
        case .deletionFailed(let review):
            return review.origin
        }
    }

    var title: String {
        switch self {
        case .preparationFailed: return "Deletion Review Couldn't Open"
        case .nothingToDelete: return "Nothing to Delete"
        case .reviewExpired: return "Review This Deletion Again"
        case .deletionFailed: return "History Wasn't Deleted"
        case .captureCouldNotPause: return "Capture Couldn't Pause"
        }
    }

    var message: String {
        switch self {
        case .preparationFailed:
            return "Screenlogger couldn't safely inspect that selection. Your history was not changed."
        case .nothingToDelete:
            return "There are no saved moments in that selection."
        case .reviewExpired:
            return "The Library changed after you reviewed it. Review the current selection before deleting anything."
        case .deletionFailed:
            return "Screenlogger kept your history because the reviewed deletion couldn't finish safely. You can try again or cancel."
        case .captureCouldNotPause:
            return "Screenlogger didn't start the review because capture must pause before the affected moments can be counted."
        }
    }

    var canRetry: Bool {
        if case .nothingToDelete = self { return false }
        return true
    }
}

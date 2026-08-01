import ScreenlogCore

/// Feature-owned presentation for failures that prevent the local Library from
/// opening. Detailed SQLite errors stay in `bootstrap.log`; UI copy remains
/// stable, actionable, and safe for nontechnical users.
enum LibraryStartupIssue: Equatable, Sendable {
    case databaseUnavailable
    case integrityCheckFailed
    case schemaMigrationFailed
    case schemaValidationFailed
    case recoveryFailed
    case unavailable

    init(error: Error) {
        if let startupError = error as? StoreStartupError {
            switch startupError {
            case .databaseUnavailable:
                self = .databaseUnavailable
            case .integrityCheckFailed:
                self = .integrityCheckFailed
            case .schemaMigrationFailed:
                self = .schemaMigrationFailed
            case .schemaValidationFailed:
                self = .schemaValidationFailed
            case .orphanRecoveryFailed:
                self = .recoveryFailed
            }
        } else if error is LibraryDeletionError {
            self = .recoveryFailed
        } else if error is LibraryRestoreError {
            self = .recoveryFailed
        } else {
            self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .integrityCheckFailed, .schemaValidationFailed:
            return "Your Library Needs Attention"
        case .schemaMigrationFailed:
            return "Your Library Couldn't Be Updated"
        case .recoveryFailed:
            return "Library Recovery Didn't Finish"
        case .databaseUnavailable, .unavailable:
            return "Your Library Couldn't Open"
        }
    }

    var message: String {
        switch self {
        case .databaseUnavailable:
            return "Screenlogger couldn't open the Library database. Capture is off to protect your saved history."
        case .integrityCheckFailed:
            return
                "Screenlogger found a problem with the Library and stopped before making changes. Your saved files remain on this Mac."
        case .schemaMigrationFailed:
            return "Screenlogger couldn't safely update the Library. Capture is off, and your saved files haven't been replaced."
        case .schemaValidationFailed:
            return "The Library has inconsistent data. Capture is off to avoid making the problem worse."
        case .recoveryFailed:
            return "Screenlogger couldn't finish recovering the Library after an interrupted operation. Capture is off for now."
        case .unavailable:
            return "Screenlogger couldn't prepare the Library. Capture is off, and details were saved for troubleshooting."
        }
    }

    var statusTitle: String { "Library Unavailable" }
}

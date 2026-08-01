import ScreenlogCore

enum ApplicationDiscoveryLoadState: Equatable, Sendable {
    case loading
    case loaded([DiscoveredApplication])
    case failed(ApplicationDiscoveryError)
}

struct ExcludedApplicationChange: Equatable, Sendable {
    let bundleID: String
    let displayName: String
}

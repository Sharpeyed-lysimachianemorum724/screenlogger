import Foundation

enum AppInstallLocation {
    /// Permission setup from a mounted installer creates a disposable,
    /// path-sensitive TCC identity. Require the installed app first.
    static func requiresInstallationBeforePermissionSetup(bundleURL: URL) -> Bool {
        bundleURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix("/Volumes/")
    }
}

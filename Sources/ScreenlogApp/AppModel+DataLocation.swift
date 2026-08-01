import AppKit

@MainActor
extension AppModel {
    func openDataFolder() {
        NSWorkspace.shared.open(root)
    }

    /// Absolute path of the on-disk library (Settings / Advanced).
    var libraryRootPath: String { root.path }
}

import Combine
import Foundation
import Sparkle

/// Owns Screenlogger's standard macOS update experience.
///
/// Sparkle remains the installation and verification authority. This wrapper
/// adds only product policy: update traffic is opt-in and every check is
/// suspended while Keep Screenlogger Offline is enabled.
@MainActor
final class AppUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdateController()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var networkAccessAllowed = true

    private lazy var standardController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var updaterCanCheckForUpdates = false
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
    }

    func start(networkAccessAllowed: Bool) {
        setNetworkAccessAllowed(networkAccessAllowed)
        guard !hasStarted else { return }

        hasStarted = true
        let updater = standardController.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] available in
                guard let self else { return }
                updaterCanCheckForUpdates = available
                refreshCanCheckForUpdates()
            }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.automaticallyChecksForUpdates = enabled
            }
            .store(in: &cancellables)
        standardController.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        standardController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        standardController.updater.automaticallyChecksForUpdates = enabled
    }

    func setNetworkAccessAllowed(_ allowed: Bool) {
        networkAccessAllowed = allowed
        refreshCanCheckForUpdates()
    }

    func updater(
        _ updater: SPUUpdater,
        mayPerform updateCheck: SPUUpdateCheck
    ) throws {
        guard networkAccessAllowed else {
            throw NSError(
                domain: "dev.screenlog.update",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Update checks are paused while Keep Screenlogger Offline is enabled."
                ]
            )
        }
    }

    private func refreshCanCheckForUpdates() {
        canCheckForUpdates = networkAccessAllowed && updaterCanCheckForUpdates
    }
}

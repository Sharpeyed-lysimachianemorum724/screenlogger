import AppKit
import Foundation
import ScreenlogCore
import ServiceManagement

/// Applies macOS appearance, launch, and Settings-window behavior.
@MainActor
extension AppModel {
    func applyAppearancePreference() {
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch appearancePreference {
        case .system: NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(
                named: increasedContrast ? .accessibilityHighContrastAqua : .aqua
            )
        case .dark:
            NSApp.appearance = NSAppearance(
                named: increasedContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
            )
        }
    }

    func applyDockIconPreference() {
        // Accessory keeps the app menu-bar-only without closing its windows.
        // Apply the preference immediately even when Timeline is visible.
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !launchAtLoginState.isBusy else { return }

        let operation: LaunchAtLoginOperation = enabled ? .enable : .disable
        let wasEnabled = launchAtLoginState.isEnabled
        launchAtLoginState =
            enabled
            ? .enabling(previouslyEnabled: wasEnabled)
            : .disabling(previouslyEnabled: wasEnabled)

        #if DEBUG
            if let simulation = AppUITestFixture.launchAtLoginSimulation {
                switch simulation {
                case .registrationFailure:
                    finishLaunchAtLogin(
                        .failed(
                            operation: operation,
                            isEnabled: wasEnabled,
                            issue: enabled ? .registrationFailed : .removalFailed
                        )
                    )
                case .approvalRequired:
                    finishLaunchAtLogin(enabled ? .approvalRequired : .ready(isEnabled: false))
                }
                return
            }
        #endif

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            resolveLaunchAtLoginStatus(SMAppService.mainApp.status, after: operation)
        } catch {
            // Keep account, signing, and system details in the local log. The
            // Settings UI gets stable recovery copy and the last live status.
            writeBootstrapLog("launchAtLogin \(operation.rawValue) failed: \(error)")
            let status = SMAppService.mainApp.status
            if status == .requiresApproval, operation == .enable {
                finishLaunchAtLogin(.approvalRequired)
            } else {
                finishLaunchAtLogin(
                    .failed(
                        operation: operation,
                        isEnabled: status == .enabled,
                        issue: operation == .enable ? .registrationFailed : .removalFailed
                    )
                )
            }
        }
    }

    func refreshLaunchAtLoginState() {
        guard !launchAtLoginState.isBusy else { return }

        #if DEBUG
            if let simulation = AppUITestFixture.launchAtLoginSimulation {
                finishLaunchAtLogin(
                    simulation == .approvalRequired
                        ? .approvalRequired
                        : .ready(isEnabled: false)
                )
                return
            }
        #endif

        resolveLaunchAtLoginStatus(SMAppService.mainApp.status, after: nil)
    }

    func retryLaunchAtLogin() {
        guard let operation = launchAtLoginState.retryOperation else { return }
        switch operation {
        case .enable:
            setLaunchAtLogin(true)
        case .disable:
            setLaunchAtLogin(false)
        case .refresh:
            refreshLaunchAtLoginState()
        }
    }

    func openLoginItemsSettings() {
        let workspace = NSWorkspace.shared
        if let loginItemsURL = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ), workspace.open(loginItemsURL) {
            return
        }

        // The pane URL is not a public API. Opening the containing app is a
        // safe fallback if a future macOS release stops recognizing it.
        _ = workspace.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        )
    }

    private func resolveLaunchAtLoginStatus(
        _ status: SMAppService.Status,
        after operation: LaunchAtLoginOperation?
    ) {
        switch status {
        case .enabled:
            if operation == .disable {
                finishLaunchAtLogin(
                    .failed(operation: .disable, isEnabled: true, issue: .removalFailed)
                )
            } else {
                finishLaunchAtLogin(.ready(isEnabled: true))
            }
        case .notRegistered:
            if operation == .enable {
                finishLaunchAtLogin(
                    .failed(operation: .enable, isEnabled: false, issue: .registrationFailed)
                )
            } else {
                finishLaunchAtLogin(.ready(isEnabled: false))
            }
        case .requiresApproval:
            if operation == .disable {
                finishLaunchAtLogin(
                    .failed(operation: .disable, isEnabled: false, issue: .removalFailed)
                )
            } else {
                finishLaunchAtLogin(.approvalRequired)
            }
        case .notFound:
            if let operation {
                finishLaunchAtLogin(
                    .failed(
                        operation: operation,
                        isEnabled: false,
                        issue: .serviceUnavailable
                    )
                )
            } else if case .failed(let previousOperation, _, _) = launchAtLoginState {
                finishLaunchAtLogin(
                    .failed(
                        operation: previousOperation,
                        isEnabled: false,
                        issue: .serviceUnavailable
                    )
                )
            } else {
                finishLaunchAtLogin(.ready(isEnabled: false))
            }
        @unknown default:
            finishLaunchAtLogin(
                .failed(
                    operation: operation ?? .refresh,
                    isEnabled: false,
                    issue: .serviceUnavailable
                )
            )
        }
    }

    private func finishLaunchAtLogin(_ state: LaunchAtLoginState) {
        launchAtLoginState = state
        preferences.set(
            state.isEnabled,
            forKey: ProductPreferenceKey.launchAtLogin
        )
    }

    func openProductSettings(_ destination: SettingsDestination? = nil) {
        SettingsWindowController.shared.show(model: self, destination: destination)
    }

    /// Open the built-in guide directly from the standard macOS Help command.
    func openProductGuide() {
        requestUserGuidePresentation()
        openProductSettings(.supportGuide)
    }

}

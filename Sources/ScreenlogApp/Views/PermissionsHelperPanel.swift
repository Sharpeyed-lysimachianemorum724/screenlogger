import AppKit
import ScreenlogCore
import SwiftUI

/// The product surface that initiated the temporary capture setup flow.
///
/// Setup is a detour, not a new workspace. Keeping its origin explicit lets
/// the controller restore a retained window without losing its navigation
/// state, search, filters, or selection.
enum CaptureSetupOrigin: Equatable {
    case library
    case timeline
    case settings
    case direct
    case directFirstRun

    var returnSurfaceName: String {
        switch self {
        case .library: return "Library"
        case .timeline, .direct: return "Timeline"
        case .directFirstRun: return "Library"
        case .settings: return "Settings"
        }
    }

    var returnsToInitiatingSurface: Bool {
        switch self {
        case .library, .timeline, .settings: return true
        case .direct, .directFirstRun: return false
        }
    }

}

private enum CaptureSetupOutcome: Equatable {
    case completed
    case cancelled
}

private enum CaptureSetupDestination: Equatable {
    case library
    case timeline(TimelineNavigationOrigin)
    case settings
    case none
}

/// The exact retained surface state to restore after the temporary Setup detour.
///
/// `CaptureSetupOrigin.timeline` identifies the visible surface, while
/// `TimelineNavigationOrigin` carries its navigation history. Keeping both
/// prevents Setup from turning a Timeline opened from a Library result into a
/// direct Timeline and silently removing Back/Escape to the preserved query.
private enum CaptureSetupReturnPath: Equatable {
    case library
    case timeline(TimelineNavigationOrigin)
    case settings
    case direct
    case firstRun

    init(origin: CaptureSetupOrigin, timelineOrigin: TimelineNavigationOrigin) {
        switch origin {
        case .library:
            self = .library
        case .timeline:
            self = .timeline(timelineOrigin)
        case .settings:
            self = .settings
        case .direct:
            self = .direct
        case .directFirstRun:
            self = .firstRun
        }
    }

    func destination(after outcome: CaptureSetupOutcome) -> CaptureSetupDestination {
        switch self {
        case .library:
            return .library
        case .timeline(let origin):
            return .timeline(origin)
        case .settings:
            return .settings
        case .direct:
            return outcome == .completed ? .timeline(.direct) : .none
        case .firstRun:
            return .library
        }
    }
}

/// Owns the temporary setup window and its macOS permission refresh lifecycle.
@MainActor
final class PermissionsHelperController: NSObject, NSWindowDelegate {
    static let shared = PermissionsHelperController()

    private var window: NSWindow?
    private weak var model: AppModel?
    private var returnPath: CaptureSetupReturnPath?
    private var activeOrigin: CaptureSetupOrigin?
    private var preferredPermission: ScreenlogPermission?
    private var refreshTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func show(
        model: AppModel,
        origin: CaptureSetupOrigin,
        preferredPermission: ScreenlogPermission? = nil
    ) {
        #if DEBUG
            AppUITestFixture.installIfRequested(on: model)
        #endif
        let requestedReturnPath = CaptureSetupReturnPath(
            origin: origin,
            timelineOrigin: model.timelineNavigationOrigin
        )
        let requestedPermission =
            preferredPermission.flatMap { model.permissions.isGranted($0) ? nil : $0 }
            ?? model.permissions.primaryMissingRequiredPermission
        if let window {
            // A visible helper is an active detour whose buttons and guidance
            // must keep their original meaning. A minimized or ordered-out
            // retained helper is no longer an active flow; an explicit reopen
            // may safely adopt the new surface and its exact Timeline history.
            var shouldReplaceContent = false
            if !window.isVisible || window.isMiniaturized,
                returnPath != requestedReturnPath
            {
                self.model = model
                returnPath = requestedReturnPath
                activeOrigin = origin
                shouldReplaceContent = true
            }
            if self.preferredPermission != requestedPermission {
                self.preferredPermission = requestedPermission
                shouldReplaceContent = true
            }
            if shouldReplaceContent {
                window.contentViewController = makeContentController(
                    model: model,
                    origin: activeOrigin ?? origin,
                    preferredPermission: requestedPermission
                )
            }
            NSApp.activate(ignoringOtherApps: true)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            startRefreshLoop()
            return
        }

        // The initiating surface owns a visible Setup flow. If it is later
        // retained out of sight, `show` can intentionally replace this context.
        self.model = model
        returnPath = requestedReturnPath
        activeOrigin = origin
        self.preferredPermission = requestedPermission
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Permissions & Privacy"
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .normal
        window.minSize = NSSize(width: 460, height: 460)
        window.delegate = self
        window.contentViewController = makeContentController(
            model: model,
            origin: origin,
            preferredPermission: requestedPermission
        )
        window.setContentSize(NSSize(width: 620, height: 600))

        self.window = window
        positionOnVisibleScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startRefreshLoop()

        // During early launch `NSScreen.main` may not be established yet. A
        // second pass on the next run-loop turn also handles a just-changed
        // active display without delaying initial presentation on bootstrap.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionOnVisibleScreen(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        refreshTask?.cancel()
        refreshTask = nil
        stopActivationObserver()
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil
        returnPath = nil
        activeOrigin = nil
        preferredPermission = nil
    }

    func windowWillClose(_ notification: Notification) {
        // The window's close button and Command-W mean the same thing as the
        // visible cancel action only while first-launch intent is undecided.
        // Never overwrite an established capture choice when Setup was opened
        // later for a revoked permission or a status check.
        let returningModel = model
        let destination = returnPath?.destination(after: .cancelled) ?? .none
        if let model = returningModel, model.captureIntent == nil {
            _ = model.keepCaptureOff()
        }
        if activeOrigin == .directFirstRun {
            returningModel?.resetFirstRunValueProgress()
        }
        refreshTask?.cancel()
        refreshTask = nil
        stopActivationObserver()
        window = nil
        model = nil
        returnPath = nil
        activeOrigin = nil
        preferredPermission = nil
        restore(destination, model: returningModel)
    }

    private func finish(_ outcome: CaptureSetupOutcome) {
        guard let returningModel = model else { return }
        let destination = returnPath?.destination(after: outcome) ?? .none
        if activeOrigin == .directFirstRun {
            returningModel.resetFirstRunValueProgress()
        }
        hide()
        restore(destination, model: returningModel)
    }

    private func makeContentController(
        model: AppModel,
        origin: CaptureSetupOrigin,
        preferredPermission: ScreenlogPermission?
    ) -> NSViewController {
        let content = PermissionsHelperView(
            origin: origin,
            preferredPermission: preferredPermission,
            onDismiss: { [weak self] in
                if model.keepCaptureOff() {
                    self?.finish(.cancelled)
                }
            },
            onStart: { [weak self] in
                if origin == .directFirstRun {
                    _ = model.startFirstRunCapture()
                    return
                }
                let started = model.isRecording || model.startCapture()
                if started {
                    self?.finish(.completed)
                }
            },
            onDone: { [weak self] in
                self?.finish(.completed)
            },
            onOpenScreen: {
                #if DEBUG
                    if AppUITestFixture.simulateSetupPermissionGrantIfRequested(on: model) {
                        return
                    }
                #endif
                model.requestScreenRecordingPermission()
            },
            onOpenAccessibility: { model.requestAccessibilityPermission() },
            onRefresh: {
                Task { await model.refreshPermissions(force: true) }
            }
        )
        .environmentObject(model)
        return NSHostingController(rootView: content)
    }

    private func restore(_ destination: CaptureSetupDestination, model: AppModel?) {
        guard let model else { return }
        switch destination {
        case .library:
            model.openSearchWindow()
        case .timeline(let origin):
            model.openMainShell(origin: origin)
        case .settings:
            model.openProductSettings()
        case .none:
            break
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        startActivationObserver()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let model = self.model else { break }
                // Appearance must never trigger a permission request. The
                // prompt-free preflight is sufficient for setup status.
                await model.refreshPermissions(force: false)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let model = self?.model else { return }
                await model.refreshPermissions(force: false)
            }
        }
    }

    private func stopActivationObserver() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func positionOnVisibleScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            // AppKit can briefly report no screens while an accessory app is
            // still finishing Launch Services activation. Core Graphics has a
            // usable main-display geometry at this point, so avoid leaving the
            // default frame at (0, 0), which is off-screen in AppKit space.
            let display = CGDisplayBounds(CGMainDisplayID())
            let size = window.frame.size
            window.setFrameOrigin(
                NSPoint(
                    x: display.maxX - size.width - 24,
                    y: display.height - size.height - 40
                ))
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        guard visible.width >= size.width, visible.height >= size.height else {
            let display = CGDisplayBounds(CGMainDisplayID())
            window.setFrameOrigin(
                NSPoint(
                    x: display.maxX - size.width - 24,
                    y: display.height - size.height - 40
                ))
            return
        }
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 40
        )
        // The origin is already derived from visibleFrame. Calling
        // constrainFrameRect during applicationDidFinishLaunching can return
        // the default zero origin before AppKit finishes screen activation.
        window.setFrameOrigin(origin)
    }
}

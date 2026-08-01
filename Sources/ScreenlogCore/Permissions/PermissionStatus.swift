import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Small synchronous cache used by permission checks from both UI and background tasks.
/// Scoped locking keeps it safe to call from async contexts under Swift 6.
final class ScreenRecordingPermissionCache: Sendable {
    private struct Entry: Sendable {
        let value: Bool
        let storedAt: Date
    }

    private let ttl: TimeInterval
    private let entry = OSAllocatedUnfairLock<Entry?>(initialState: nil)

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func value(at now: Date = Date()) -> Bool? {
        entry.withLock { entry in
            guard let entry, now.timeIntervalSince(entry.storedAt) < ttl else {
                return nil
            }
            return entry.value
        }
    }

    func store(_ value: Bool, at now: Date = Date()) {
        entry.withLock { $0 = Entry(value: value, storedAt: now) }
    }

    func invalidate() {
        entry.withLock { $0 = nil }
    }
}

public enum ScreenRecordingPermission {
    /// Cached result so the menu bar refresh loop never hammers ScreenCaptureKit.
    private static let cache = ScreenRecordingPermissionCache(ttl: 8)

    /// Fast path: CoreGraphics preflight (no SCShareableContent round-trip).
    public static func preflightGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// May display the supported macOS consent prompt. Call only in direct
    /// response to a user action; status refreshes must use `preflightGranted`.
    @discardableResult
    public static func requestAccess() -> Bool {
        invalidateCache()
        return CGRequestScreenCaptureAccess()
    }

    /// Prompt-free status check with a short cache for non-UI callers.
    ///
    /// Do not use `SCShareableContent` as a permission probe. Although it can
    /// reveal a grant, it performs real capture access and may make macOS show
    /// repeated privacy notifications when a setup view polls for status.
    public static func isGranted(force: Bool = false) async -> Bool {
        if !force, let cached = cache.value() {
            return cached
        }
        let result = preflightGranted()
        storeCache(result)
        return result
    }

    public static func invalidateCache() {
        cache.invalidate()
    }

    private static func storeCache(_ value: Bool) {
        cache.store(value)
    }

}

public enum AccessibilityPermission {
    public static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// May display the supported macOS consent prompt. Call only in direct
    /// response to a user action; status refreshes must pass `prompt: false`.
    @discardableResult
    public static func requestAccess() -> Bool {
        isTrusted(prompt: true)
    }
}

public struct PermissionsSnapshot: Sendable, Equatable {
    public var screenRecording: Bool
    public var accessibility: Bool

    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }

    public var isCaptureReady: Bool {
        screenRecording && accessibility
    }

    public func isGranted(_ permission: ScreenlogPermission) -> Bool {
        switch permission {
        case .screenRecording: screenRecording
        case .accessibility: accessibility
        }
    }

    public var missingRequiredPermissions: [ScreenlogPermission] {
        ScreenlogPermission.allCases.filter { !isGranted($0) }
    }

    /// The permission a generic capture action should recover first. Setup
    /// may still target another missing permission when the user selected its
    /// specific row in Settings.
    public var primaryMissingRequiredPermission: ScreenlogPermission? {
        missingRequiredPermissions.first
    }

    /// Lightweight snapshot (CG preflight + AX). Safe for periodic menu-bar refresh.
    public static func currentFast() -> PermissionsSnapshot {
        PermissionsSnapshot(
            screenRecording: ScreenRecordingPermission.preflightGranted(),
            accessibility: AccessibilityPermission.isTrusted(prompt: false)
        )
    }

    /// Prompt-free cached check. `force` bypasses only the in-process cache.
    public static func current(force: Bool = false) async -> PermissionsSnapshot {
        let screen = await ScreenRecordingPermission.isGranted(force: force)
        let ax = AccessibilityPermission.isTrusted(prompt: false)
        return PermissionsSnapshot(screenRecording: screen, accessibility: ax)
    }
}

import Foundation
import ScreenlogCore

@MainActor
extension AppModel {
    var keyboardShortcutDefinitions: [KeyboardShortcutDefinition] {
        keyboardShortcutStore.registry.definitions
    }

    func keyboardShortcutBinding(
        for actionID: KeyboardShortcutActionID
    ) -> KeyboardShortcutBinding? {
        _ = keyboardShortcutRevision
        return keyboardShortcutStore.binding(for: actionID)
    }

    func keyboardShortcutConflicts(
        for binding: KeyboardShortcutBinding,
        assignedTo actionID: KeyboardShortcutActionID
    ) -> [KeyboardShortcutConflict] {
        keyboardShortcutStore.conflicts(for: binding, assignedTo: actionID)
    }

    func keyboardShortcutValidationResult(
        for binding: KeyboardShortcutBinding,
        assignedTo actionID: KeyboardShortcutActionID
    ) -> KeyboardShortcutValidationResult {
        keyboardShortcutStore.validationResult(for: binding, assignedTo: actionID)
    }

    func setKeyboardShortcut(
        _ binding: KeyboardShortcutBinding?,
        for actionID: KeyboardShortcutActionID
    ) throws {
        try keyboardShortcutStore.setBinding(binding, for: actionID)
        keyboardShortcutRevision &+= 1
    }

    func resetKeyboardShortcut(for actionID: KeyboardShortcutActionID) throws {
        try keyboardShortcutStore.resetToDefault(for: actionID)
        keyboardShortcutRevision &+= 1
    }

    func resetAllKeyboardShortcuts() {
        keyboardShortcutStore.resetToDefaults()
        keyboardShortcutRevision &+= 1
    }

    func keyboardShortcutDisplayLabel(
        for actionID: KeyboardShortcutActionID,
        fallback: String = "Not Set"
    ) -> String {
        keyboardShortcutBinding(for: actionID)?.displayLabel ?? fallback
    }

    func keyboardShortcutAccessibilityLabel(
        for actionID: KeyboardShortcutActionID,
        fallback: String = "No shortcut assigned"
    ) -> String {
        keyboardShortcutBinding(for: actionID)?.accessibilityLabel ?? fallback
    }

    func performKeyboardShortcutCaptureToggle() {
        if isRecording {
            _ = stopCapture()
        } else if !permissions.isCaptureReady
            || capturePauseReason == .permissionRequired
        {
            showPermissions(origin: .direct)
        } else {
            _ = startCapture()
        }
    }
}

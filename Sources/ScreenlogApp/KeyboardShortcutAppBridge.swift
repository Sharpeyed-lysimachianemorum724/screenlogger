import AppKit
import ScreenlogCore
import SwiftUI

enum KeyboardShortcutEventAdapter {
    /// Converts one physical key-down event into the same portable binding the
    /// command menus and window monitors consume. Modifier-only and control
    /// events return nil so the recorder can keep waiting for a complete chord.
    static func binding(from event: NSEvent) -> KeyboardShortcutBinding? {
        let modifiers = KeyboardShortcutBinding.shortcutModifiers(
            from: event.modifierFlags
        )

        if let specialKey = KeyboardShortcutSpecialKey(appKitKeyCode: event.keyCode) {
            return KeyboardShortcutBinding(
                key: .special(specialKey),
                modifiers: modifiers
            )
        }

        guard let ignoring = event.charactersIgnoringModifiers?.first,
            Self.isRecordable(ignoring)
        else { return nil }

        var recordedKey = ignoring
        var recordedModifiers = modifiers
        if modifiers.contains(.shift),
            let produced = event.characters?.first,
            Self.isRecordable(produced),
            KeyboardShortcutBinding.normalized(produced)
                != KeyboardShortcutBinding.normalized(ignoring)
        {
            // Symbols such as + and ? conventionally include their layout's
            // producing Shift in the key glyph, not as a separate modifier.
            recordedKey = produced
            recordedModifiers = KeyboardShortcutModifiers(
                Set(modifiers.ordered.filter { $0 != .shift })
            )
        }

        return KeyboardShortcutBinding(
            key: .character(recordedKey),
            modifiers: recordedModifiers
        )
    }

    private static func isRecordable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

extension KeyboardShortcutBinding {
    var swiftUIKeyEquivalent: KeyEquivalent? {
        if let character = key.character {
            return KeyEquivalent(character)
        }
        switch key.specialKey {
        case .returnKey: return .return
        case .space: return .space
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .tab: return .tab
        case .delete: return .delete
        case .forwardDelete: return .deleteForward
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .none: return nil
        }
    }

    var swiftUIModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    var appKitKeyEquivalent: String {
        if let character = key.character { return String(character) }
        switch key.specialKey {
        case .returnKey: return "\r"
        case .space: return " "
        case .leftArrow: return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .rightArrow: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case .upArrow: return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .downArrow: return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case .tab: return "\t"
        case .delete: return "\u{8}"
        case .forwardDelete: return String(Character(UnicodeScalar(NSDeleteFunctionKey)!))
        case .home: return String(Character(UnicodeScalar(NSHomeFunctionKey)!))
        case .end: return String(Character(UnicodeScalar(NSEndFunctionKey)!))
        case .pageUp: return String(Character(UnicodeScalar(NSPageUpFunctionKey)!))
        case .pageDown: return String(Character(UnicodeScalar(NSPageDownFunctionKey)!))
        case .none: return ""
        }
    }

    var appKitModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = Self.shortcutModifiers(from: event.modifierFlags)

        if let character = key.character {
            let expected = Self.normalized(character)
            let ignoringModifiers = event.charactersIgnoringModifiers?.first.map(Self.normalized)
            if ignoringModifiers == expected, eventModifiers == modifiers {
                return true
            }

            // Printable symbols such as '+' require Shift on common keyboard
            // layouts even though the conventional shortcut is displayed as
            // Command-Plus. Treat only that layout-producing Shift as implicit.
            let produced = event.characters?.first.map(Self.normalized)
            let shiftedModifiers = KeyboardShortcutModifiers(
                Set(modifiers.ordered + [.shift])
            )
            return !modifiers.contains(.shift)
                && ignoringModifiers != expected
                && produced == expected
                && eventModifiers == shiftedModifiers
        }

        return eventModifiers == modifiers
            && event.keyCode == key.specialKey?.appKitKeyCode
    }

    func matches(_ keyPress: KeyPress) -> Bool {
        guard swiftUIKeyEquivalent == keyPress.key else { return false }
        let eventModifiers = keyPress.modifiers.intersection([
            .command, .control, .option, .shift,
        ])
        if eventModifiers == swiftUIModifiers { return true }

        guard let character = key.character,
            !modifiers.contains(.shift),
            !character.isLetter,
            !character.isNumber
        else { return false }
        return eventModifiers == swiftUIModifiers.union(.shift)
    }

    fileprivate static func normalized(_ character: Character) -> Character {
        let lowered = String(character).lowercased()
        return lowered.count == 1 ? lowered.first! : character
    }

    fileprivate static func shortcutModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> KeyboardShortcutModifiers {
        var values = Set<KeyboardShortcutModifier>()
        let deviceIndependent = flags.intersection(.deviceIndependentFlagsMask)
        if deviceIndependent.contains(.control) { values.insert(.control) }
        if deviceIndependent.contains(.option) { values.insert(.option) }
        if deviceIndependent.contains(.shift) { values.insert(.shift) }
        if deviceIndependent.contains(.command) { values.insert(.command) }
        return KeyboardShortcutModifiers(values)
    }
}

extension KeyboardShortcutSpecialKey {
    fileprivate init?(appKitKeyCode: UInt16) {
        switch appKitKeyCode {
        case 36, 76: self = .returnKey
        case 49: self = .space
        case 123: self = .leftArrow
        case 124: self = .rightArrow
        case 126: self = .upArrow
        case 125: self = .downArrow
        case 48: self = .tab
        case 51: self = .delete
        case 117: self = .forwardDelete
        case 115: self = .home
        case 119: self = .end
        case 116: self = .pageUp
        case 121: self = .pageDown
        default: return nil
        }
    }

    fileprivate var appKitKeyCode: UInt16 {
        switch self {
        case .returnKey: return 36
        case .space: return 49
        case .leftArrow: return 123
        case .rightArrow: return 124
        case .upArrow: return 126
        case .downArrow: return 125
        case .tab: return 48
        case .delete: return 51
        case .forwardDelete: return 117
        case .home: return 115
        case .end: return 119
        case .pageUp: return 116
        case .pageDown: return 121
        }
    }
}

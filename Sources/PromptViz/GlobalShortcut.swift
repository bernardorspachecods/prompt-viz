import AppKit
import Foundation

struct GlobalShortcut: Codable, Equatable {
    static let defaultShortcut = GlobalShortcut(keyCode: 14, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let keyCode: UInt16
    let modifierFlags: UInt

    var displayName: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var name = ""
        if modifiers.contains(.control) { name += "⌃" }
        if modifiers.contains(.option) { name += "⌥" }
        if modifiers.contains(.shift) { name += "⇧" }
        if modifiers.contains(.command) { name += "⌘" }
        return name + Self.keyName(for: keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        return event.keyCode == keyCode && eventModifiers.rawValue == modifierFlags
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "Space",
            51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum GlobalShortcutPersistence {
    private static let key = "prompt-viz.open-composer-shortcut"

    static func load(defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            let data = defaults.data(forKey: key),
            let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        else { return .defaultShortcut }

        return shortcut
    }

    static func save(_ shortcut: GlobalShortcut, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }
}

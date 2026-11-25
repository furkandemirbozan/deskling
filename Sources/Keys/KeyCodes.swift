import Foundation

/// macOS tuş kodları ile ses paketlerinin kullandığı web tuş adları (KeyboardEvent.code) arasındaki eşleme.
enum KeyCodes {
    static let mac: [UInt16: String] = [
        0: "KeyA", 1: "KeyS", 2: "KeyD", 3: "KeyF", 4: "KeyH", 5: "KeyG", 6: "KeyZ", 7: "KeyX", 8: "KeyC", 9: "KeyV",
        10: "IntlBackslash", 11: "KeyB", 12: "KeyQ", 13: "KeyW", 14: "KeyE", 15: "KeyR", 16: "KeyY", 17: "KeyT",
        18: "Digit1", 19: "Digit2", 20: "Digit3", 21: "Digit4", 22: "Digit6", 23: "Digit5", 24: "Equal", 25: "Digit9",
        26: "Digit7", 27: "Minus", 28: "Digit8", 29: "Digit0", 30: "BracketRight", 31: "KeyO", 32: "KeyU",
        33: "BracketLeft", 34: "KeyI", 35: "KeyP", 36: "Enter", 37: "KeyL", 38: "KeyJ", 39: "Quote", 40: "KeyK",
        41: "Semicolon", 42: "Backslash", 43: "Comma", 44: "Slash", 45: "KeyN", 46: "KeyM", 47: "Period", 48: "Tab",
        49: "Space", 50: "Backquote", 51: "Backspace", 53: "Escape", 54: "MetaRight", 55: "MetaLeft", 56: "ShiftLeft",
        57: "CapsLock", 58: "AltLeft", 59: "ControlLeft", 60: "ShiftRight", 61: "AltRight", 62: "ControlRight",
        65: "NumpadDecimal", 67: "NumpadMultiply", 69: "NumpadAdd", 71: "NumLock", 75: "NumpadDivide", 76: "NumpadEnter",
        78: "NumpadSubtract", 81: "NumpadEqual", 82: "Numpad0", 83: "Numpad1", 84: "Numpad2", 85: "Numpad3", 86: "Numpad4",
        87: "Numpad5", 88: "Numpad6", 89: "Numpad7", 91: "Numpad8", 92: "Numpad9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "PrintScreen", 107: "ScrollLock",
        109: "F10", 111: "F12", 113: "Pause", 114: "Insert", 115: "Home", 116: "PageUp", 117: "Delete", 118: "F4",
        119: "End", 120: "F2", 121: "PageDown", 122: "F1", 123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
    ]

    /// Eski (v1) paketlerin kullandığı tuş numaraları.
    static let legacy: [Int: String] = {
        var m: [Int: String] = [1: "Escape", 14: "Backspace", 15: "Tab", 28: "Enter", 29: "ControlLeft", 42: "ShiftLeft",
                                43: "Backslash", 54: "ShiftRight", 55: "NumpadMultiply", 56: "AltLeft", 57: "Space", 58: "CapsLock",
                                12: "Minus", 13: "Equal", 26: "BracketLeft", 27: "BracketRight", 39: "Semicolon", 40: "Quote",
                                41: "Backquote", 51: "Comma", 52: "Period", 53: "Slash", 87: "F11", 88: "F12",
                                3675: "MetaLeft", 3676: "MetaRight", 3640: "AltRight", 3613: "ControlRight", 3612: "NumpadEnter",
                                57416: "ArrowUp", 57424: "ArrowDown", 57419: "ArrowLeft", 57421: "ArrowRight",
                                3655: "Home", 3663: "End", 3657: "PageUp", 3665: "PageDown", 3666: "Insert", 3667: "Delete"]
        for (i, d) in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].enumerated() { m[2 + i] = "Digit" + d }
        for (i, c) in "QWERTYUIOP".enumerated() { m[16 + i] = "Key\(c)" }
        for (i, c) in "ASDFGHJKL".enumerated() { m[30 + i] = "Key\(c)" }
        for (i, c) in "ZXCVBNM".enumerated() { m[44 + i] = "Key\(c)" }
        for i in 0..<10 { m[59 + i] = "F\(i + 1)" }
        return m
    }()

    static let modifierCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Tuşun klavyedeki yatay yeri (0 sol, 1 sağ): ses o yandan gelir.
    static func position(_ code: String) -> Float {
        if let p = rowPosition[code] { return p }
        if code.hasPrefix("Numpad") || code == "NumLock" { return 1 }
        if code.hasPrefix("Arrow") || ["Home", "End", "PageUp", "PageDown", "Insert", "Delete", "PrintScreen", "ScrollLock", "Pause"].contains(code) { return 0.9 }
        if code.hasSuffix("Left") { return 0.08 }
        if code.hasSuffix("Right") { return 0.8 }
        if code == "Space" { return 0.45 }
        if code.hasPrefix("F"), let n = Int(code.dropFirst()) { return Float(n) / 13 }
        return 0.5
    }

    private static let rowPosition: [String: Float] = {
        let rows: [[String]] = [
            ["Escape"],
            ["Backquote", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9", "Digit0", "Minus", "Equal", "Backspace"],
            ["Tab", "KeyQ", "KeyW", "KeyE", "KeyR", "KeyT", "KeyY", "KeyU", "KeyI", "KeyO", "KeyP", "BracketLeft", "BracketRight", "Backslash"],
            ["CapsLock", "KeyA", "KeyS", "KeyD", "KeyF", "KeyG", "KeyH", "KeyJ", "KeyK", "KeyL", "Semicolon", "Quote", "Enter"],
            ["IntlBackslash", "KeyZ", "KeyX", "KeyC", "KeyV", "KeyB", "KeyN", "KeyM", "Comma", "Period", "Slash"],
        ]
        var m: [String: Float] = ["Escape": 0]
        for r in rows.dropFirst() {
            for (i, c) in r.enumerated() { m[c] = 0.78 * Float(i) / Float(max(1, r.count - 1)) }
        }
        return m
    }()

    /// Sentezlenen paketlerde tuşun sınıfı.
    enum Kind { case normal, space, enter, backspace, modifier }
    static func kind(_ code: String) -> Kind {
        switch code {
        case "Space": return .space
        case "Enter", "NumpadEnter": return .enter
        case "Backspace", "Delete": return .backspace
        default:
            return code.hasPrefix("Shift") || code.hasPrefix("Control") || code.hasPrefix("Alt") || code.hasPrefix("Meta")
                || code == "CapsLock" || code == "Tab" ? .modifier : .normal
        }
    }
}

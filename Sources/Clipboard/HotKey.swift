import AppKit
import ApplicationServices
import Carbon

/// Kullanıcının seçtiği genel kısayol.
struct ClipShortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var key: String

    static let standard = ClipShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift], key: "V")

    var label: String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + key
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Kısayolun ⌘, ⌃ ya da ⌥ içermesi gerekir; yoksa her yazışta tetiklenirdi.
    static func from(_ e: NSEvent) -> ClipShortcut? {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        let names: [Int: String] = [kVK_Space: "Boşluk", kVK_Return: "↩", kVK_Tab: "⇥", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3",
                                    kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9",
                                    kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        let key = names[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        return ClipShortcut(keyCode: e.keyCode, modifiers: mods, key: key)
    }

    static func load(_ d: UserDefaults = .standard) -> ClipShortcut {
        guard d.object(forKey: "clipKeyCode") != nil, let key = d.string(forKey: "clipKeyLabel") else { return .standard }
        return ClipShortcut(keyCode: UInt16(d.integer(forKey: "clipKeyCode")),
                            modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "clipKeyMods"))), key: key)
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(Int(keyCode), forKey: "clipKeyCode")
        d.set(Int(modifiers.rawValue), forKey: "clipKeyMods")
        d.set(key, forKey: "clipKeyLabel")
    }
}

/// Carbon ile genel kısayol: uygulama arka plandayken de çalışır, erişilebilirlik izni gerektirmez.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(_ shortcut: ClipShortcut, handler: @escaping () -> Void) {
        Self.install()
        id = Self.nextID
        Self.nextID += 1
        let hotID = EventHotKeyID(signature: OSType(0x5242_5350), id: id)   // "RBSP"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hot = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hot)
            let id = hot.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Seçilen kaydı öndeki uygulamaya yapıştırır. Erişilebilirlik izni yoksa yalnızca panoya kopyalar.
enum Paster {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Klavye düzeninde "v" harfini üreten tuş; Türkçe F klavyede bile ⌘V doğru gider.
    static var vKey: CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return CGKeyCode(kVK_ANSI_V) }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buf -> CGKeyCode in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return CGKeyCode(kVK_ANSI_V) }
            for code in 0..<UInt16(64) {
                var dead: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let s = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                       OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
                if s == noErr, length == 1, chars[0] == UniChar(UInt8(ascii: "v")) { return CGKeyCode(code) }
            }
            return CGKeyCode(kVK_ANSI_V)
        }
    }

    static func pasteToFrontApp() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key = vKey
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

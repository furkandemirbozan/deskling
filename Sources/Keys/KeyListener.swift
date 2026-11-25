import AppKit
import CoreAudio

/// Tuşlara basılıp bırakıldığını duyar. Yalnızca tuşun kodunu alır; yazılan metni okumaz, saklamaz.
/// macOS "Giriş İzleme" izni ister. Parola alanlarında macOS tuşları zaten göstermez.
final class KeyListener {
    var onKey: (UInt16, Bool) -> Void = { _, _ in }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var heldModifiers = Set<UInt16>()

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestListenEventAccess() }
    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(u) }
    }

    var running: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            if let refcon { Unmanaged<KeyListener>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        heldModifiers = []
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        case .keyDown:
            // Basılı tutunca gelen tekrarlar ses çıkarmaz; gerçek klavyede de tek tık duyulur.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            onKey(UInt16(event.getIntegerValueField(.keyboardEventKeycode)), true)
        case .keyUp:
            onKey(UInt16(event.getIntegerValueField(.keyboardEventKeycode)), false)
        case .flagsChanged:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            for (c, down) in Self.modifierChange(code: code, held: &heldModifiers, flags: event.flags) { onKey(c, down) }
        default: break
        }
    }

    /// Değişen değiştirici tuşun basıldığını mı bırakıldığını mı söyler. Caps Lock tek seferde ikisini birden üretir.
    static func modifierChange(code: UInt16, held: inout Set<UInt16>, flags: CGEventFlags) -> [(UInt16, Bool)] {
        guard KeyCodes.modifierCodes.contains(code), code != 63 else { return [] }
        if code == 57 { return [(57, true), (57, false)] }
        let flag: CGEventFlags
        switch code {
        case 56, 60: flag = .maskShift
        case 59, 62: flag = .maskControl
        case 58, 61: flag = .maskAlternate
        default: flag = .maskCommand
        }
        if held.contains(code) || !flags.contains(flag) {
            held.remove(code)
            return [(code, false)]
        }
        held.insert(code)
        return [(code, true)]
    }
}

/// Varsayılan mikrofon şu an bir uygulama tarafından kullanılıyor mu? (toplantı, kayıt)
enum MicWatch {
    static func inUse() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return false }
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

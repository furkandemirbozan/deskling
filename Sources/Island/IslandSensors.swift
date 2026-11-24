import AppKit
import CoreAudio
import IOKit.ps

// MARK: - Pil

struct PowerState: Equatable {
    var percent: Int
    var charging: Bool
    var plugged: Bool
}

enum PowerEvent: Equatable {
    case plugged, unplugged, low, full
}

/// Pil durumunu IOKit'ten okur ve fişe takma, çıkarma, azalma ve dolma anlarını bildirir.
final class PowerWatch {
    var onChange: (PowerState, [PowerEvent]) -> Void = { _, _ in }
    private(set) var state: PowerState?
    private var source: CFRunLoopSource?

    /// Önceki ve yeni durumdan olayları çıkarır; ilk okumada olay yoktur.
    static func events(old: PowerState?, new: PowerState) -> [PowerEvent] {
        guard let old else { return [] }
        var out: [PowerEvent] = []
        if new.plugged != old.plugged { out.append(new.plugged ? .plugged : .unplugged) }
        if !new.plugged {
            for limit in [20, 10] where old.percent > limit && new.percent <= limit { out.append(.low); break }
        }
        if new.plugged, old.percent < 100, new.percent >= 100 { out.append(.full) }
        return out
    }

    static func read() -> PowerState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return PowerState(percent: Int((Double(cur) / Double(Swift.max(1, max)) * 100).rounded()),
                              charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                              plugged: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }

    func start() {
        state = Self.read()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerWatch>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    }

    func stop() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        source = nil
    }

    private func refresh() {
        guard let new = Self.read(), new != state else { return }
        let ev = Self.events(old: state, new: new)
        state = new
        onChange(new, ev)
    }
}

// MARK: - Ses

struct AudioOutput: Equatable {
    enum Kind: Equatable { case airpods, airpodsPro, airpodsMax, headphones, builtIn, display, airplay, speaker }
    var name: String
    var kind: Kind

    var symbol: String {
        switch kind {
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .builtIn: return "laptopcomputer"
        case .display: return "tv"
        case .airplay: return "airplayaudio"
        case .speaker: return "hifispeaker.fill"
        }
    }

    static func guess(name: String, transport: UInt32) -> Kind {
        let n = name.lowercased()
        if n.contains("airpods max") { return .airpodsMax }
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods") { return .airpods }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airplay
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return n.contains("speaker") || n.contains("hoparlör") ? .speaker : .headphones
        default:
            return n.contains("headphone") || n.contains("kulaklık") || n.contains("buds") ? .headphones : .speaker
        }
    }
}

/// Varsayılan çıkış aygıtını ve ses düzeyini CoreAudio üzerinden izler; izin gerektirmez.
final class AudioWatch {
    var onVolume: (Float, Bool) -> Void = { _, _ in }
    var onDevice: (AudioOutput) -> Void = { _ in }
    private(set) var device: AudioDeviceID = 0
    private(set) var output: AudioOutput?
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var levelBlock: AudioObjectPropertyListenerBlock?
    private var watched: [AudioObjectPropertyAddress] = []
    private var quietUntil = Date.distantPast
    private var deviceWork: DispatchWorkItem?

    func start() {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceChanged() }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        attach(Self.defaultOutput())
        output = Self.describe(device)
        quietUntil = Date().addingTimeInterval(1.5)
    }

    func stop() {
        if let b = deviceBlock {
            var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, b)
        }
        deviceBlock = nil
        detach()
    }

    var volume: Float { Self.volume(device) ?? 0 }
    var muted: Bool { Self.isMuted(device) }
    func setVolume(_ v: Float) { Self.setVolume(device, v) }

    private func deviceChanged() {
        // Aygıt değişirken birkaç bildirim art arda gelir; sonuncusu yeter.
        deviceWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let id = Self.defaultOutput()
            guard id != self.device else { return }
            self.attach(id)
            self.quietUntil = Date().addingTimeInterval(1)
            if let out = Self.describe(id), out != self.output {
                self.output = out
                self.onDevice(out)
            }
        }
        deviceWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
    }

    private func attach(_ id: AudioDeviceID) {
        detach()
        device = id
        guard id != 0 else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, Date() > self.quietUntil else { return }
            self.onVolume(self.volume, self.muted)
        }
        levelBlock = block
        for sel in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for el: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
                var a = Self.address(sel, kAudioDevicePropertyScopeOutput, el)
                guard AudioObjectHasProperty(id, &a) else { continue }
                if AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr { watched.append(a) }
            }
        }
    }

    private func detach() {
        if let b = levelBlock {
            for var a in watched { AudioObjectRemovePropertyListenerBlock(device, &a, .main, b) }
        }
        watched = []
        levelBlock = nil
    }

    // MARK: CoreAudio yardımcıları

    static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                        _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    static func describe(_ id: AudioDeviceID) -> AudioOutput? {
        guard id != 0 else { return nil }
        var a = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr,
              let n = name?.takeRetainedValue() as String? else { return nil }
        var transport: UInt32 = 0
        var tsize = UInt32(MemoryLayout<UInt32>.size)
        var ta = address(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(id, &ta, 0, nil, &tsize, &transport)
        return AudioOutput(name: n, kind: AudioOutput.guess(name: n, transport: transport))
    }

    private static func elements(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> [UInt32] {
        var main = address(sel, kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(id, &main) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { var a = address(sel, kAudioDevicePropertyScopeOutput, $0); return AudioObjectHasProperty(id, &a) }
    }

    static func volume(_ id: AudioDeviceID) -> Float? {
        let els = elements(id, kAudioDevicePropertyVolumeScalar)
        guard !els.isEmpty else { return nil }
        let values = els.compactMap { el -> Float? in
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, el)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? v : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool {
        guard let el = elements(id, kAudioDevicePropertyMute).first else { return false }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, el)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr && v != 0
    }

    static func setVolume(_ id: AudioDeviceID, _ value: Float) {
        var v = Float32(min(1, max(0, value)))
        for el in elements(id, kAudioDevicePropertyVolumeScalar) {
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, el)
            AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
        if v > 0, isMuted(id), let el = elements(id, kAudioDevicePropertyMute).first {
            var m: UInt32 = 0
            var a = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, el)
            AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }
}

// MARK: - Tam ekran

enum FullscreenDetector {
    /// Öndeki uygulamanın bir penceresi ekranı menü çubuğu dahil tamamen kaplıyorsa tam ekrandır.
    static func frontIsFullscreen(on screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        let target = CGRect(x: f.minX, y: primary - f.maxY, width: f.width, height: f.height)
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if abs(r.minX - target.minX) < 1, abs(r.minY - target.minY) < 1,
               abs(r.width - target.width) < 1, abs(r.height - target.height) < 1 { return true }
        }
        return false
    }
}

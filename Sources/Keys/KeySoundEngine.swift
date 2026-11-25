import AVFoundation

/// Bir paketin çalınmaya hazır sesleri (48 kHz, stereo, float).
final class LoadedPack {
    let id: String
    let volume: Float
    let randomPitch: Bool
    var down: [String: AVAudioPCMBuffer] = [:]
    var up: [String: AVAudioPCMBuffer] = [:]
    /// Pakette tanımı olmayan tuşlar için yedek sesler (harf tuşlarından).
    var fallbackDown: [AVAudioPCMBuffer] = []
    var fallbackUp: [AVAudioPCMBuffer] = []

    init(id: String, volume: Float, randomPitch: Bool) {
        self.id = id
        self.volume = volume
        self.randomPitch = randomPitch
    }

    func sound(_ code: String, up isUp: Bool) -> AVAudioPCMBuffer? {
        if isUp {
            if let b = up[code] { return b }
            return fallbackUp.isEmpty ? nil : fallbackUp[Self.stable(code) % fallbackUp.count]
        }
        if let b = down[code] { return b }
        return fallbackDown.isEmpty ? nil : fallbackDown[Self.stable(code) % fallbackDown.count]
    }

    func finish() {
        func pick(_ d: [String: AVAudioPCMBuffer]) -> [AVAudioPCMBuffer] {
            let letters = d.filter { $0.key.hasPrefix("Key") }.sorted { $0.key < $1.key }.map(\.value)
            return letters.isEmpty ? d.sorted { $0.key < $1.key }.map(\.value) : letters
        }
        fallbackDown = pick(down)
        fallbackUp = pick(up)
    }

    /// Çalıştırmadan çalıştırmaya değişmeyen basit karma.
    static func stable(_ s: String) -> Int { s.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } }
}

enum PackLoader {
    static let rate: Double = 48_000
    static let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    static let maxSlice: Double = 2_500   // ms

    static func load(_ info: SoundPackInfo) throws -> LoadedPack {
        if info.builtin { return SynthPacks.make(info.id) }
        guard let dir = info.folder else { throw SoundPackConfig.ParseError.noSound }
        let c = try SoundPackConfig.parse(Data(contentsOf: dir.appendingPathComponent("config.json")), fallbackID: dir.lastPathComponent)
        let pack = LoadedPack(id: info.id, volume: c.volume, randomPitch: c.randomPitch)
        var decoded: [String: AVAudioPCMBuffer] = [:]
        func file(_ name: String) throws -> AVAudioPCMBuffer {
            if let b = decoded[name] { return b }
            let b = try decode(dir.appendingPathComponent(name))
            decoded[name] = b
            return b
        }
        for (code, s) in c.down { if let b = try slice(file(s.file), s) { pack.down[code] = b } }
        for (code, s) in c.up { if let b = try slice(file(s.file), s) { pack.up[code] = b } }
        pack.finish()
        return pack
    }

    /// Ses dosyasını 48 kHz stereo float'a çevirir (Ogg Vorbis, WAV, MP3…).
    static func decode(_ url: URL) throws -> AVAudioPCMBuffer {
        let f = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(min(f.length, Int64(f.processingFormat.sampleRate * 600)))
        guard let src = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: max(frames, 1)) else { throw SoundPackConfig.ParseError.noSound }
        try f.read(into: src, frameCount: frames)
        var buf = src
        if src.format.sampleRate != rate {
            guard let dst = AVAudioFormat(standardFormatWithSampleRate: rate, channels: src.format.channelCount),
                  let conv = AVAudioConverter(from: src.format, to: dst),
                  let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * rate / src.format.sampleRate) + 4096)
            else { throw SoundPackConfig.ParseError.noSound }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true
                status.pointee = .haveData
                return src
            }
            if let err { throw err }
            buf = out
        }
        return stereo(buf)
    }

    /// Tek kanallıyı iki kanala çoğaltır, fazlasını atar.
    static func stereo(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if b.format.channelCount == 2, b.format.commonFormat == .pcmFormatFloat32, !b.format.isInterleaved { return b }
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: b.frameLength)!
        out.frameLength = b.frameLength
        guard let s = b.floatChannelData, let d = out.floatChannelData else { return out }
        let n = Int(b.frameLength), ch = Int(b.format.channelCount)
        for c in 0..<2 { d[c].update(from: s[min(c, ch - 1)], count: n) }
        return out
    }

    /// [başla, bitir] milisaniye aralığını keser; tıkırtı olmasın diye uçlarına kısa geçiş ekler.
    static func slice(_ b: AVAudioPCMBuffer, _ s: KeySlice) -> AVAudioPCMBuffer? {
        let total = Int(b.frameLength)
        let start = max(0, Int(s.start * rate / 1000))
        let end = min(total, Int(min(s.end, s.start + maxSlice) * rate / 1000))
        guard end - start > 16, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - start)),
              let src = b.floatChannelData, let dst = out.floatChannelData else { return nil }
        let n = end - start
        out.frameLength = AVAudioFrameCount(n)
        let fadeIn = min(n / 4, 24), fadeOut = min(n / 3, Int(rate * 0.004))
        for c in 0..<2 {
            dst[c].update(from: src[c] + start, count: n)
            for i in 0..<fadeIn { dst[c][i] *= Float(i) / Float(fadeIn) }
            for i in 0..<fadeOut { dst[c][n - 1 - i] *= Float(i) / Float(fadeOut) }
        }
        return out
    }
}

/// Dosya gerektirmeyen, kodla üretilmiş paketler.
enum SynthPacks {
    static let all: [SoundPackInfo] = [
        info("deskling.tik", "Deskling · Tık", "Tiz ve tıklamalı, mavi anahtar gibi"),
        info("deskling.tok", "Deskling · Tok", "Derin ve tok, ağır kasalı klavye gibi"),
        info("deskling.daktilo", "Deskling · Daktilo", "Satır sonunda zil çalan eski daktilo"),
        info("deskling.balon", "Deskling · Baloncuk", "Her tuşta küçük bir baloncuk patlar"),
    ]

    private static func info(_ id: String, _ name: String, _ d: String) -> SoundPackInfo {
        SoundPackInfo(id: id, name: name, author: "Deskling", description: d, license: nil, keyCount: KeyCodes.mac.count,
                      hasRelease: id == "deskling.tik" || id == "deskling.tok", builtin: true, folder: nil)
    }

    static func make(_ id: String) -> LoadedPack {
        let pack = LoadedPack(id: id, volume: 0.8, randomPitch: false)
        var rng = KeyRandom(seed: UInt64(LoadedPack.stable(id)))
        // Her tuş sınıfı için birkaç çeşit üretilir; tuşlar bunlara dağıtılır.
        var variants: [KeyCodes.Kind: [AVAudioPCMBuffer]] = [:]
        var ups: [KeyCodes.Kind: [AVAudioPCMBuffer]] = [:]
        for kind in [KeyCodes.Kind.normal, .space, .enter, .backspace, .modifier] {
            let count = kind == .normal ? 8 : 3
            variants[kind] = (0..<count).map { i in render(id, kind: kind, variant: i, up: false, rng: &rng) }
            if hasUp(id) { ups[kind] = (0..<count).map { i in render(id, kind: kind, variant: i, up: true, rng: &rng) } }
        }
        for code in Set(KeyCodes.mac.values) {
            let k = KeyCodes.kind(code)
            let list = variants[k]!
            pack.down[code] = list[LoadedPack.stable(code) % list.count]
            if let u = ups[k] { pack.up[code] = u[LoadedPack.stable(code) % u.count] }
        }
        pack.finish()
        return pack
    }

    private static func hasUp(_ id: String) -> Bool { id == "deskling.tik" || id == "deskling.tok" }

    private static func render(_ id: String, kind: KeyCodes.Kind, variant: Int, up: Bool, rng: inout KeyRandom) -> AVAudioPCMBuffer {
        let pitch: Double = {
            let base: Double
            switch kind {
            case .space: base = 0.72
            case .enter: base = 0.84
            case .backspace: base = 0.9
            case .modifier: base = 0.88
            case .normal: base = 1
            }
            return base * (0.95 + 0.1 * Double(variant) / 8)
        }()
        let long = kind == .space || kind == .enter ? 1.35 : 1.0
        let duration: Double
        switch id {
        case "deskling.daktilo": duration = kind == .enter ? 0.9 : 0.12 * long
        case "deskling.balon": duration = 0.09
        case "deskling.tok": duration = up ? 0.05 : 0.13 * long
        default: duration = up ? 0.04 : 0.09 * long
        }
        let n = Int(duration * PackLoader.rate)
        let out = AVAudioPCMBuffer(pcmFormat: PackLoader.format, frameCapacity: AVAudioFrameCount(n))!
        out.frameLength = AVAudioFrameCount(n)
        let l = out.floatChannelData![0], r = out.floatChannelData![1]
        var lp: Double = 0
        let twoPi = 2 * Double.pi
        for i in 0..<n {
            let t = Double(i) / PackLoader.rate
            let noise = rng.nextSigned()
            var v: Double
            switch id {
            case "deskling.tok":
                lp += (noise - lp) * 0.18
                let amp = up ? 0.35 : 1.0
                v = amp * (lp * exp(-t / 0.004) * 1.4 + sin(twoPi * 128 * pitch * t) * exp(-t / (0.045 * long)) * 0.75
                           + sin(twoPi * 410 * pitch * t) * exp(-t / 0.018) * 0.22)
            case "deskling.daktilo":
                v = noise * exp(-t / 0.003) * 0.9 + sin(twoPi * 1750 * pitch * t) * exp(-t / 0.025) * 0.3
                    + sin(twoPi * 92 * pitch * t) * exp(-t / 0.05) * 0.55
                if kind == .enter, t > 0.09 {
                    let tb = t - 0.09
                    v += (sin(twoPi * 2093 * tb) + 0.45 * sin(twoPi * 5230 * tb)) * exp(-tb / 0.35) * 0.32
                }
            case "deskling.balon":
                let f = (520 + 2600 * min(t, 0.05) / 0.05) * pitch
                v = sin(twoPi * f * t) * exp(-t / 0.028) * (1 - exp(-t / 0.002)) * 0.7
            default:
                let amp = up ? 0.45 : 1.0
                v = amp * (noise * exp(-t / 0.0015) * 0.8 + sin(twoPi * 4300 * pitch * t) * exp(-t / 0.011) * 0.28
                           + (up ? 0 : sin(twoPi * 230 * pitch * t) * exp(-t / (0.022 * long)) * 0.5))
            }
            let s = Float(max(-1, min(1, v * 0.6)))
            l[i] = s
            r[i] = s
        }
        // Son 3 ms yumuşak bitsin.
        let fade = min(n / 3, Int(PackLoader.rate * 0.003))
        for i in 0..<fade { let g = Float(i) / Float(fade); l[n - 1 - i] *= g; r[n - 1 - i] *= g }
        return out
    }
}

/// Testlerde ve sentezde her seferinde aynı sesi verir.
struct KeyRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextSigned() -> Double { Double(next() % 2_000_001) / 1_000_000 - 1 }
}

/// Düşük gecikmeli çalar: önceden hazır sesler, üst üste binebilen 14 ses kanalı.
final class KeySoundEngine {
    private let engine = AVAudioEngine()
    private var voices: [(player: AVAudioPlayerNode, speed: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    private let queue = DispatchQueue(label: "deskling.keys.audio", qos: .userInteractive)
    private var lastPlay = Date.distantPast
    private var idle: DispatchSourceTimer?

    init(voices count: Int = 14) {
        for _ in 0..<count {
            let p = AVAudioPlayerNode(), s = AVAudioUnitVarispeed()
            engine.attach(p)
            engine.attach(s)
            engine.connect(p, to: s, format: PackLoader.format)
            engine.connect(s, to: engine.mainMixerNode, format: PackLoader.format)
            voices.append((p, s))
        }
        engine.prepare()
    }

    /// `pan` -1 (sol) … 1 (sağ); `rate` 1 normal hız/perde.
    func play(_ buffer: AVAudioPCMBuffer, volume: Float, pan: Float, rate: Float = 1) {
        queue.async { [self] in
            if !engine.isRunning {
                do { try engine.start() } catch { return }
            }
            let v = voices[nextVoice]
            nextVoice = (nextVoice + 1) % voices.count
            v.player.stop()
            v.player.volume = max(0, min(1.5, volume))
            v.player.pan = max(-1, min(1, pan))
            v.speed.rate = rate
            v.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            v.player.play()
            lastPlay = Date()
            scheduleIdleStop()
        }
    }

    /// Yazmayı bırakınca ses motoru kapanır; işlemci boşta yorulmaz.
    private func scheduleIdleStop() {
        guard idle == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 20, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self, Date().timeIntervalSince(self.lastPlay) > 20 else { return }
            self.voices.forEach { $0.player.stop() }
            self.engine.stop()
            self.idle?.cancel()
            self.idle = nil
        }
        t.resume()
        idle = t
    }
}

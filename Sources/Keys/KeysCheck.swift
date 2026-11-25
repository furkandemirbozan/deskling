import AVFoundation
import AppKit

/// `--keys-check`: paket okuma, zip açma, ses kesme, sentez ve tuş eşlemesi.
/// Geçici klasörlerde çalışır; gerçek paket klasörüne dokunmaz, tuş dinlemez, ses çalmaz.
enum KeysCheck {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ info: String = "") {
            print((ok ? "GEÇTİ  " : "KALDI  ") + name + (ok || info.isEmpty ? "" : "  [\(info)]"))
            if !ok { failures += 1 }
        }

        // Tuş eşlemesi
        check("tuş kodları eşlenir", KeyCodes.mac[0] == "KeyA" && KeyCodes.mac[49] == "Space" && KeyCodes.mac[36] == "Enter"
              && KeyCodes.mac[51] == "Backspace" && KeyCodes.mac[56] == "ShiftLeft" && KeyCodes.mac[126] == "ArrowUp")
        check("her kod tek tuşa gider", Set(KeyCodes.mac.values).count == KeyCodes.mac.count)
        check("eski paket numaraları", KeyCodes.legacy[30] == "KeyA" && KeyCodes.legacy[57] == "Space" && KeyCodes.legacy[2] == "Digit1" && KeyCodes.legacy[59] == "F1")
        check("soldaki tuş solda, sağdaki sağda", KeyCodes.position("KeyQ") < KeyCodes.position("KeyP") && KeyCodes.position("Numpad5") == 1
              && KeyCodes.position("ShiftLeft") < KeyCodes.position("ShiftRight"))
        check("tuş sınıfları", KeyCodes.kind("Space") == .space && KeyCodes.kind("Enter") == .enter && KeyCodes.kind("MetaLeft") == .modifier
              && KeyCodes.kind("KeyJ") == .normal)
        var held = Set<UInt16>()
        let shiftDown = KeyListener.modifierChange(code: 56, held: &held, flags: .maskShift)
        let rightDown = KeyListener.modifierChange(code: 60, held: &held, flags: .maskShift)
        let rightUp = KeyListener.modifierChange(code: 60, held: &held, flags: .maskShift)
        let leftUp = KeyListener.modifierChange(code: 56, held: &held, flags: [])
        check("değiştirici tuşların basılıp bırakılması", shiftDown.map(\.1) == [true] && rightDown.map(\.1) == [true]
              && rightUp.map(\.1) == [false] && leftUp.map(\.1) == [false] && held.isEmpty)
        check("Caps Lock tek seferde bas-bırak", KeyListener.modifierChange(code: 57, held: &held, flags: .maskAlphaShift).map(\.1) == [true, false])

        // config.json
        let v2 = """
        {"id":"mv-test","name":"Deneme","author":"Ben","version":"2","audio_file":"ses.wav","definition_method":"single",
         "options":{"recommended_volume":0.5,"random_pitch":true},
         "definitions":{"KeyA":{"timing":[[0,100],[100,150]]},"Space":{"timing":[[200,400]]},"Bozuk":{"timing":[[5,1]]}}}
        """
        let c = try? SoundPackConfig.parse(Data(v2.utf8), fallbackID: "x")
        check("v2 paketi okunur", c?.name == "Deneme" && c?.down["KeyA"] == KeySlice(file: "ses.wav", start: 0, end: 100)
              && c?.up["KeyA"] == KeySlice(file: "ses.wav", start: 100, end: 150) && c?.up["Space"] == nil && c?.down["Bozuk"] == nil
              && c?.volume == 0.5 && c?.randomPitch == true)
        let multi = """
        {"name":"Çok","definition_method":"multi","audio_file":"a.ogg","definitions":{"KeyA":{"audio_file":"b.ogg","timing":[[0,80]]},"KeyB":{"timing":[[0,80]]}}}
        """
        let m = try? SoundPackConfig.parse(Data(multi.utf8), fallbackID: "klasor")
        check("çok dosyalı paket", m?.down["KeyA"]?.file == "b.ogg" && m?.down["KeyB"]?.file == "a.ogg" && m?.id == "klasor" && m?.files == ["a.ogg", "b.ogg"])
        let v1 = """
        {"id":"eski","name":"Eski","key_define_type":"single","sound":"s.ogg","defines":{"30":[100,50],"57":[300,80],"99999":[1,1]}}
        """
        let o = try? SoundPackConfig.parse(Data(v1.utf8), fallbackID: "x")
        check("v1 paketi okunur", o?.down["KeyA"] == KeySlice(file: "s.ogg", start: 100, end: 150) && o?.down["Space"]?.end == 380 && o?.down.count == 2)
        func rejects(_ json: String) -> Bool { (try? SoundPackConfig.parse(Data(json.utf8), fallbackID: "x")) == nil }
        check("paketin dışına çıkan dosya adı reddedilir", rejects(#"{"audio_file":"../gizli.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}"#)
              && rejects(#"{"audio_file":"/etc/x.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}"#)
              && rejects(#"{"audio_file":"betik.sh","definitions":{"KeyA":{"timing":[[0,10]]}}}"#))
        check("sessiz paket reddedilir", rejects(#"{"audio_file":"a.wav","definitions":{}}"#) && rejects("bozuk"))
        func lic(_ s: String) -> String? { SoundPackInfo(id: "", name: "", author: "", description: "", license: s, keyCount: 0, hasRelease: false, builtin: false).licenseTitle }
        check("lisans adları", lic("Personal use only. Original author: x") == "Kişisel kullanım" && lic("MIT License") == "MIT"
              && lic("CC BY 4.0") == "CC BY" && lic("CC0 1.0") == "CC0")

        // Sahte klasörde zip'ler
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("deskling-keys-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Kaynak"), cache = root.appendingPathComponent("Önbellek"), work = root.appendingPathComponent("hazırlık")
        try? fm.createDirectory(at: source, withIntermediateDirectories: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        func makeWAV(_ url: URL, seconds: Double, rate: Double = 44_100, channels: AVAudioChannelCount = 1) {
            let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
            let n = AVAudioFrameCount(seconds * rate)
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
            b.frameLength = n
            for ch in 0..<Int(channels) { for i in 0..<Int(n) { b.floatChannelData![ch][i] = Float(sin(Double(i) * 0.05)) * 0.5 } }
            let f = try? AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                                                  AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16])
            try? f?.write(from: b)
        }
        func makePack(_ name: String, id: String, version: String = "1", folder: String? = nil, extra: (URL) -> Void = { _ in }) -> URL {
            let d = work.appendingPathComponent(folder ?? name)
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            makeWAV(d.appendingPathComponent("ses.wav"), seconds: 1)
            let cfg = """
            {"id":"\(id)","name":"\(name)","author":"Deneme","version":"\(version)","audio_file":"ses.wav",
             "definitions":{"KeyA":{"timing":[[0,100],[100,160]]},"KeyS":{"timing":[[200,300]]},"Space":{"timing":[[400,700]]}}}
            """
            try? cfg.write(to: d.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
            try? "Personal use only.".write(to: d.appendingPathComponent("LICENSE.txt"), atomically: true, encoding: .utf8)
            extra(d)
            return d
        }
        func zip(_ dir: URL, to name: String) {
            let dest = source.appendingPathComponent(name)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--keepParent", dir.path, dest.path]
            try? p.run(); p.waitUntilExit()
        }
        zip(makePack("Birinci", id: "mv-1"), to: "birinci.zip")
        try? fm.copyItem(at: source.appendingPathComponent("birinci.zip"), to: source.appendingPathComponent("birinci (1).zip"))
        let folderPack = makePack("Klasörde", id: "mv-2")
        try? fm.copyItem(at: folderPack, to: source.appendingPathComponent("Klasörde"))
        zip(makePack("Bağlantılı", id: "mv-3") { d in try? fm.createSymbolicLink(at: d.appendingPathComponent("kaçak"), withDestinationURL: URL(fileURLWithPath: "/etc")) },
            to: "baglantili.zip")
        try? Data("zip değil".utf8).write(to: source.appendingPathComponent("bozuk.zip"))
        try? Data("ilgisiz".utf8).write(to: source.appendingPathComponent("not.txt"))
        // Alt klasörler: aynı paketin kopyası, yeni sürümü, aynı ad ve yapımcıyla yeniden yüklenmişi ve gerçekten yeni bir paket.
        try? fm.createDirectory(at: source.appendingPathComponent("YeniSesler"), withIntermediateDirectories: true)
        try? fm.copyItem(at: source.appendingPathComponent("birinci.zip"), to: source.appendingPathComponent("YeniSesler/birinci.zip"))
        zip(makePack("Birinci", id: "mv-1", version: "2", folder: "birinci-v2"), to: "YeniSesler/birinci-v2.zip")
        zip(makePack("Klasörde", id: "mv-9", folder: "yeniden-yuklenen"), to: "YeniSesler/yeniden.zip")
        zip(makePack("İkinci", id: "mv-4"), to: "YeniSesler/Derin/ikinci.zip")
        let before = (try? fm.contentsOfDirectory(atPath: source.path))?.sorted() ?? []

        let store = SoundPackStore(cache: cache)
        let r = store.sync(from: source)
        check("zip, klasör ve alt klasör paketleri okunur, kopyalar bir kez görünür", r.packs.map(\.name) == ["Birinci", "İkinci", "Klasörde"],
              r.packs.map(\.name).joined(separator: ","))
        check("atlanan kopyalar sayılır", r.duplicates == 4, "\(r.duplicates)")
        check("aynı paketin yeni sürümü seçilir", r.packs.first { $0.baseID == "mv-1" }?.version == "2")
        check("aynı ad ve yapımcıyla yeniden yüklenen paket kopya sayılır", r.packs.filter { $0.name == "Klasörde" }.count == 1)
        check("bağlantı içeren ve bozuk zip reddedilir", r.problems.count == 2 && r.problems.contains { $0.hasPrefix("baglantili.zip") }
              && r.problems.contains { $0.hasPrefix("bozuk.zip") }, r.problems.joined(separator: " | "))
        check("lisans ve bırakma sesi okunur", r.packs.first?.licenseTitle == "Kişisel kullanım" && r.packs.first?.hasRelease == true && r.packs.first?.keyCount == 3)
        check("kaynak klasör değişmez", ((try? fm.contentsOfDirectory(atPath: source.path))?.sorted() ?? []) == before)
        check("paket Deskling'in kendi klasörüne açılır", r.packs.first?.folder?.path.hasPrefix(cache.path) == true)
        let cachedBefore = (try? fm.contentsOfDirectory(atPath: cache.path))?.sorted() ?? []
        let r2 = store.sync(from: source)
        check("ikinci okumada zip yeniden açılmaz", r2.packs.count == 3 && ((try? fm.contentsOfDirectory(atPath: cache.path))?.sorted() ?? []) == cachedBefore)
        check("temiz zip'in girdileri kabul edilir", (try? SoundPackStore.checkEntries(source.appendingPathComponent("birinci.zip"))) != nil)

        // Sesleri yükleme ve kesme
        if let info = r.packs.first, let p = try? PackLoader.load(info) {
            let a = p.down["KeyA"]
            check("sesler 48 kHz stereo'ya çevrilir", a?.format.sampleRate == 48_000 && a?.format.channelCount == 2)
            check("aralık doğru uzunlukta kesilir", a.map { abs(Int($0.frameLength) - 4800) < 10 } == true && p.down["Space"].map { abs(Int($0.frameLength) - 14400) < 10 } == true)
            check("bırakma sesi ayrı", p.up["KeyA"] != nil && p.up["Space"] == nil)
            check("tanımsız tuşa yedek ses", p.sound("KeyZ", up: false) != nil && p.sound("KeyZ", up: false) === p.sound("KeyZ", up: false))
            check("kesilen sesin ucu sessizleşir", a.map { abs($0.floatChannelData![0][Int($0.frameLength) - 1]) < 0.01 } == true)
        } else { check("paket yüklenir", false) }

        // Kodla üretilmiş paketler
        var synth: [LoadedPack] = []
        for info in SynthPacks.all { synth.append(SynthPacks.make(info.id)) }
        check("dahili paketlerin hepsi her tuşa ses verir", synth.allSatisfy { p in KeyCodes.mac.values.allSatisfy { p.down[$0] != nil } })
        check("daktiloda Enter zil çalar (uzun)", (synth[2].down["Enter"]?.frameLength ?? 0) > 4 * (synth[2].down["KeyA"]?.frameLength ?? 1))
        check("tık ve tok bırakma sesi verir, baloncuk vermez", synth[0].up["KeyA"] != nil && synth[1].up["KeyA"] != nil && synth[3].up["KeyA"] == nil)
        let again = SynthPacks.make("deskling.tok")
        let x = again.down["KeyA"]!, y = synth[1].down["KeyA"]!
        check("aynı paket her seferinde aynı ses", x.frameLength == y.frameLength && x.floatChannelData![0][100] == y.floatChannelData![0][100])
        check("sentez sesleri taşmaz", synth.allSatisfy { p in p.down.values.allSatisfy { b in (0..<Int(b.frameLength)).allSatisfy { abs(b.floatChannelData![0][$0]) <= 1 } } })

        // Durum
        let center = KeySoundCenter(store: SoundPackStore(cache: cache), defaults: nil)
        check("varsayılan olarak kapalı", !center.enabled && center.muted && center.selectedID == "deskling.tok")
        center.enabled = false
        center.setPacksForTest(r.packs)
        check("dahili ve klasördeki paketler birlikte listelenir", center.packs.count == SynthPacks.all.count + 3)
        center.muteWithMic = true
        check("mikrofon ayarı tutulur", center.muteWithMic)

        print(failures == 0 ? "KLAVYE_GECTI" : "KLAVYE_KALDI hata=\(failures)")
        return failures == 0 ? 0 : 1
    }
}

/// `--keys-report <klasör>`: verilen klasördeki paketleri geçici bir yere açıp yükler ve özetler. Hiçbir şeyi değiştirmez.
enum KeysReport {
    static func run(folder: String) -> Int32 {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("deskling-keys-report-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let r = SoundPackStore(cache: tmp).sync(from: URL(fileURLWithPath: folder))
        for p in r.packs {
            let t0 = Date()
            if let l = try? PackLoader.load(p) {
                print(String(format: "✓ %@ — %d tuş, %d bırakma, %.2f sn, %@", p.name, l.down.count, l.up.count, Date().timeIntervalSince(t0), p.licenseTitle ?? "lisans yok"))
            } else { print("✗ \(p.name) yüklenemedi") }
        }
        for e in r.problems { print("! \(e)") }
        print("\(r.packs.count) paket, \(r.duplicates) kopya atlandı")
        return 0
    }
}

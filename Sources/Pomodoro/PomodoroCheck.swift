import Foundation

/// Pomodoro motorunu sahte saatle dener. Gerçek bildirimlere, sese ve güç yönetimine dokunmaz.
enum PomodoroCheck {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    /// Elle ilerletilen saat.
    final class Clock {
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
    }

    static func run() -> Int32 {
        stateMachine()
        pauseAndResume()
        durationChange()
        persistence()
        alertsAndAwake()
        formatting()
        particles()
        print(failures == 0 ? "POMODORO_GECTI" : "POMODORO_KALDI hata=\(failures)")
        return failures == 0 ? 0 : 1
    }

    private static func make(_ c: Clock, cycle: Int = 4) -> (PomodoroManager, () -> [PomoTransition]) {
        let m = PomodoroManager(durations: PomoDurations(focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, cycle: cycle),
                                now: { c.t })
        var log: [PomoTransition] = []
        m.onTransition = { log.append($0) }
        return (m, { log })
    }

    private static func stateMachine() {
        let c = Clock()
        let (m, log) = make(c)
        check("başlangıç hazır ve 25:00", m.phase == .idle && !m.running && m.clockText == "25:00")
        m.start()
        check("başlatınca odak çalışır", m.phase == .focus && m.running)
        c.advance(10 * 60); m.tick()
        check("10 dakika sonra 15:00 kalır", m.clockText == "15:00", m.clockText)
        check("ilerleme %40", abs(m.progress - 0.4) < 0.001, "\(m.progress)")
        c.advance(15 * 60); m.tick()
        check("odak bitince kısa mola kendiliğinden başlar", m.phase == .shortBreak && m.running && m.cycleDone == 1)
        check("bitiş geçişi 'süre doldu' olarak bildirilir", log().last == PomoTransition(from: .focus, to: .shortBreak, finished: true))
        c.advance(5 * 60); m.tick()
        check("mola bitince hazır duruma döner", m.phase == .idle && !m.running)
        for _ in 0..<3 {
            m.start(); c.advance(25 * 60); m.tick()
            if m.phase == .shortBreak { c.advance(5 * 60); m.tick() }
        }
        check("4. odaktan sonra uzun mola", m.phase == .longBreak && m.cycleDone == 4, "\(m.phase) \(m.cycleDone)")
        c.advance(15 * 60); m.tick()
        check("uzun moladan sonra döngü sıfırlanır, bugünkü sayı kalır", m.phase == .idle && m.cycleDone == 0 && m.todayDone == 4)

        // Atla ve sıfırla
        m.start(); c.advance(60); m.skip()
        check("odağı atlamak seans saymaz, molaya geçer", m.phase == .shortBreak && m.cycleDone == 0 && log().last?.finished == false)
        m.skip()
        check("molayı atlamak yeni odağı başlatır", m.phase == .focus && m.running && m.clockText == "25:00")
        m.reset()
        check("sıfırla hazır duruma döner", m.phase == .idle && !m.running && m.clockText == "25:00")

        // Uyku: tek bir tick'te geç kalınsa bile aşama bir kez biter
        m.start(); c.advance(3 * 3600); m.tick()
        check("uykudan dönünce tek geçiş olur", m.phase == .shortBreak && m.cycleDone == 1)

        // Odak kendiliğinden başlasın seçeneği
        let c2 = Clock()
        let (a, _) = make(c2, cycle: 2)
        a.autoStartFocus = true
        a.start(); c2.advance(25 * 60); a.tick(); c2.advance(5 * 60); a.tick()
        check("istenirse moladan sonra odak kendiliğinden başlar", a.phase == .focus && a.running)
        c2.advance(25 * 60); a.tick()
        check("döngü 2 ise ikinci odaktan sonra uzun mola", a.phase == .longBreak)
    }

    private static func pauseAndResume() {
        let c = Clock()
        let (m, _) = make(c)
        m.start(); c.advance(4 * 60); m.pause()
        check("duraklatınca süre donar", m.isPaused && m.clockText == "21:00")
        c.advance(30 * 60); m.tick()
        check("duraklatılmışken zaman geçse de süre azalmaz ve aşama bitmez", m.phase == .focus && m.clockText == "21:00")
        m.toggle(); c.advance(60); m.tick()
        check("devam edince kaldığı yerden sürer", m.running && m.clockText == "20:00", m.clockText)
    }

    private static func durationChange() {
        let c = Clock()
        let (m, _) = make(c)
        m.durations.focus = 50 * 60
        check("hazırken süre değişince yeni süre görünür", m.clockText == "50:00")
        m.start(); c.advance(10 * 60); m.tick()
        m.durations.focus = 30 * 60
        check("çalışırken süre kısalınca geçen süre korunur", m.clockText == "20:00", m.clockText)
        m.durations.focus = 5 * 60
        check("geçen süreden kısa ayar hemen bitirmez, 1 sn kalır", m.currentRemaining == 1, "\(m.currentRemaining)")
    }

    private static func persistence() {
        let name = "deskling-pomo-test-\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: name) else { check("geçici ayar alanı", false); return }
        defer { d.removePersistentDomain(forName: name) }
        let c = Clock()
        let m = PomodoroManager(defaults: d, now: { c.t })
        m.start(); c.advance(5 * 60); m.tick()
        let again = PomodoroManager(defaults: d, now: { c.t })
        check("yeniden açılınca çalışan sayaç kaldığı yerden sürer", again.phase == .focus && again.running && again.clockText == "20:00",
              "\(again.phase) \(again.clockText)")
        again.pause()
        let paused = PomodoroManager(defaults: d, now: { c.t })
        check("duraklatılmış sayaç duraklatılmış açılır", paused.isPaused && paused.clockText == "20:00")
        paused.start(); c.advance(3600)
        let late = PomodoroManager(defaults: d, now: { c.t })
        check("kapalıyken süresi dolan aşama sessizce kapanır", late.phase == .idle && !late.running)
        m.forget(); again.forget(); paused.forget(); late.forget()

        // Ayarlar sınırlar içinde okunur
        d.register(defaults: PomoLimits.defaults)
        d.set(500, forKey: "pomoFocus"); d.set(0, forKey: "pomoCycle"); d.set(9.0, forKey: "pomoScale"); d.set("yok", forKey: "pomoDrink")
        let s = AppModel.loadPomoSettings(d)
        check("bozuk ayarlar sınıra çekilir", s.focus == 90 && s.cycle == 2 && s.scale == 1.6 && s.drink == .tea,
              "\(s.focus) \(s.cycle) \(s.scale) \(s.drink)")
        d.removeObject(forKey: "pomoFocus"); d.removeObject(forKey: "pomoCycle"); d.removeObject(forKey: "pomoScale")
        let def = AppModel.loadPomoSettings(d)
        check("varsayılanlar 25/5/15/4", def.focus == 25 && def.shortBreak == 5 && def.longBreak == 15 && def.cycle == 4 && def.scale == 1)
    }

    private static func alertsAndAwake() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("deskling-pomo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Model ayarları gerçek ayar alanına yazar; testten önceki değerler sonunda geri konur.
        let std = UserDefaults.standard
        let keys = Array(PomoLimits.defaults.keys) + [PomodoroManager.stateKey]
        let own = std.persistentDomain(forName: Bundle.main.bundleIdentifier ?? AppInfo.bundleID) ?? [:]
        let saved = keys.map { ($0, own[$0]) }   // kayıtlı varsayılanlar değil, yalnızca gerçekten kaydedilmiş değerler
        defer { for (k, v) in saved { v == nil ? std.removeObject(forKey: k) : std.set(v, forKey: k) } }
        let model = AppModel(desktopOverride: tmp)
        let c = Clock()
        model.pomo.now = { c.t }
        var notes: [String] = [], sounds: [String] = []
        let awake = FakeKeepAwake()
        model.pomoAlerts = PomodoroAlerts(notify: { t, _ in notes.append(t) }, playSound: { sounds.append($0) }, keepAwake: awake)
        model.pomoEnabled = true
        model.pomoNotify = true
        model.pomoSound = true
        model.pomoKeepAwake = true
        model.pomoDrink = .tea
        model.pomoFocus = 25

        model.pomo.start()
        check("odakta ekran uyanık tutulur", awake.active)
        model.pomo.pause()
        check("duraklatınca uyanık tutma bırakılır", !awake.active)
        model.pomo.start(); c.advance(25 * 60); model.pomo.tick()
        check("odak bitince bildirim gelir", notes == ["Odak tamamlandı"], "\(notes)")
        check("çay temasında kaşık sesi çalar", sounds == ["Tink"], "\(sounds)")
        check("molada uyanık tutulmaz", !awake.active)
        model.pomo.skip()
        check("atlamada bildirim ve ses olmaz", notes.count == 1 && sounds.count == 1)
        model.pomoSound = false
        c.advance(25 * 60); model.pomo.tick()
        check("ses kapalıyken çalmaz ama bildirim gelir", sounds.count == 1 && notes.count == 2)
        model.pomoNotify = false
        c.advance(5 * 60); model.pomo.tick()
        check("bildirim kapalıyken gönderilmez", notes.count == 2)
        model.pomo.start()
        model.pomoKeepAwake = false
        check("ayar kapanınca uyanık tutma hemen bırakılır", !awake.active)
        model.pomoKeepAwake = true
        check("ayar açılınca hemen geri gelir", awake.active)
        model.pomoEnabled = false
        check("modül kapanınca sayaç durur ve uyanık tutma biter", model.pomo.phase == .idle && !awake.active)
        check("modül kapalıyken menü çubuğunda süre yok", model.pomoMenuLabel == nil)
        model.pomoEnabled = true
        model.pomo.start()
        check("menü çubuğu etiketi kalan süreyi gösterir", model.pomoMenuLabel == "25:00", model.pomoMenuLabel ?? "-")
        model.pomoMenuTimer = false
        check("menü çubuğu ayarı kapalıyken etiket yok", model.pomoMenuLabel == nil)
        model.pomo.reset()
        awake.release()
    }

    private static func formatting() {
        check("saat biçimi", PomodoroManager.clock(0) == "00:00" && PomodoroManager.clock(59.2) == "01:00"
              && PomodoroManager.clock(1455) == "24:15")
        let b = PomodoroAlerts.message(for: PomoTransition(from: .focus, to: .longBreak, finished: true), done: 4,
                                       durations: PomoDurations())
        check("uzun mola mesajı süreyi söyler", b?.body.contains("15 dakika") == true, b?.body ?? "-")
        check("atlanan geçişte mesaj yok", PomodoroAlerts.message(for: PomoTransition(from: .focus, to: .shortBreak, finished: false),
                                                                  done: 1, durations: PomoDurations()) == nil)
    }

    private static func particles() {
        func run(_ k: DrinkKind, steam: Double = 0.8, level: Double = 0.9, effects: DrinkEffects = .high, seconds: Double = 5) -> DrinkParticles {
            var st = DrinkState()
            st.kind = k; st.steam = steam; st.level = level; st.effects = effects
            var p = DrinkParticles(seed: 11)
            for _ in 0..<Int(seconds * 60) { st.time += 1.0 / 60; p.step(dt: 1.0 / 60, state: st) }
            return p
        }
        check("sıcak içeceklerden buhar yükselir", [DrinkKind.tea, .turkishCoffee, .mug].allSatisfy { run($0).puffs.count > 15 })
        check("Türk kahvesinin buharı daha yoğun", run(.turkishCoffee).puffs.count > run(.tea).puffs.count)
        check("birada buhar yok, baloncuk var", run(.beer).puffs.isEmpty && run(.beer).bubbles.count > 20)
        check("sıcak içecekte baloncuk yok", run(.tea).bubbles.isEmpty)
        check("buhar kesilince topaklar dağılır", run(.tea, steam: 0, seconds: 6).puffs.isEmpty)
        check("düşük yoğunlukta daha az partikül", run(.beer, effects: .low).bubbles.count < run(.beer).bubbles.count / 2 + 2)
        let bubbles = run(.beer, level: 0.5)
        let g = DrinkArt.geo(.beer)
        check("baloncuklar sıvının içinde kalır", bubbles.bubbles.allSatisfy { CGFloat($0.y) < g.surface(0.5) + 1 && CGFloat($0.y) > g.bottom })
        check("boş birada baloncuk çıkmaz", run(.beer, level: 0.01).bubbles.isEmpty)
        var st = DrinkState(); st.kind = .beer; st.phase = .focus
        var p = DrinkParticles(seed: 2)
        for k in 0...600 { st.level = 1 - Double(k) / 600 * 0.8; st.progress = Double(k) / 600 * 0.8; p.step(dt: 1.0 / 60, state: st) }
        check("bira azaldıkça camda köpük izi kalır", p.lacing.count >= 4, "\(p.lacing.count) iz")
        st.level = 1; p.step(dt: 1.0 / 60, state: st)
        check("yeniden dolunca izler yıkanır", p.lacing.isEmpty)
        for k in DrinkKind.allCases {
            var s2 = DrinkState(); s2.kind = k; s2.level = 0.6
            check("\(k.title) çizilir", DrawProbe.opaquePixels(s2) > 3000)
        }
    }
}

/// Çizimin boş olmadığını ölçer.
enum DrawProbe {
    static func opaquePixels(_ s: DrinkState) -> Int {
        guard let img = DrinkArt.render(s, particles: DrinkParticles(), size: DrinkArt.canvas, scale: 1),
              let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
        var n = 0
        for i in stride(from: 3, to: CFDataGetLength(data), by: 4) where ptr[i] > 128 { n += 1 }
        return n
    }
}

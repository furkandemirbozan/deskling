import AppKit
import SwiftUI
import JavaScriptCore
import CoreAudio

/// Dinamik adanın mantığını pencere açmadan dener. Gerçek ayarlara, panoya ya da dosyalara dokunmaz:
/// kalıcılık için geçici bir ayar alanı açılır ve sonunda silinir.
@MainActor
enum IslandCheck {
    final class Clock { var t = Date(timeIntervalSinceReferenceDate: 800_000_000); func advance(_ s: TimeInterval) { t += s } }

    private static var failures = 0
    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    static func make(_ clock: Clock, store: UserDefaults? = nil) -> IslandManager {
        let pomo = PomodoroManager(durations: PomoDurations(), defaults: nil, now: { clock.t })
        let media = NowPlaying()
        media.scriptsAllowed = false
        let m = IslandManager(settings: IslandSettings(store: store), pomo: pomo, store: store, media: media,
                              now: { clock.t }, autoTick: false)
        m.playSound = { _ in }
        return m
    }

    static func run() -> Int32 {
        geometry()
        priorities()
        transients()
        timers()
        media()
        hover()
        powerEvents()
        shelfAndPersistence()
        render()
        print(failures == 0 ? "ADA_GECTI" : "ADA_KALDI hata=\(failures)")
        return failures == 0 ? 0 : 1
    }

    // MARK: -

    private static func geometry() {
        let g = IslandGeometry.sample
        check("çentik ölçüsü bulunur", g.hasNotch && g.notch == CGRect(x: 646, y: 924, width: 179, height: 32), "\(g.notch)")
        let side = IslandGeometry.make(frame: CGRect(x: -1470, y: 200, width: 1470, height: 956),
                                       left: CGRect(x: -1470, y: 1124, width: 646, height: 32),
                                       right: CGRect(x: -645, y: 1124, width: 645, height: 32), safeTop: 32, menuBar: 33)
        check("yan ekranda çentik doğru yerde", side.notch == CGRect(x: -824, y: 1124, width: 179, height: 32), "\(side.notch)")
        let plain = IslandGeometry.make(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), left: nil, right: nil, safeTop: 0, menuBar: 25)
        check("çentiksiz ekranda ortada sanal çentik", !plain.hasNotch && plain.notch.midX == 960 && plain.notch.maxY == 1080)
        let closed = IslandLayout.rect(.closed, g)
        check("kapalıyken şekil tam çentik kadar", closed == g.notch, "\(closed)")
        let c = IslandLayout.rect(.compact(.live(.timer)), g)
        check("kulaklar çentiğin iki yanına eşit uzanır", abs(c.midX - g.notch.midX) < 0.01 && c.maxY == 956 && c.width > g.notch.width + 140)
        let e = IslandLayout.rect(.expanded, g)
        check("açık ada ekranın tepesinden aşağı iner", e.maxY == 956 && e.height == IslandLayout.expanded.height && abs(e.midX - g.notch.midX) < 0.01)
        let b = IslandLayout.bubbleRect(.compact(.live(.timer)), g)
        check("baloncuk adanın sağında", b.minX > c.maxX && b.height == g.notch.height)
        check("tuval açık adayı ve baloncuğu sığdırır", IslandLayout.canvas.width >= e.width && IslandLayout.canvas.height >= e.height
              && IslandLayout.canvas.width / 2 >= (b.maxX - g.notch.midX))
    }

    private static func priorities() {
        let clock = Clock()
        let m = make(clock)
        var pomoOn = true
        m.pomoEnabled = { pomoOn }
        check("boşken ada kapalı", m.display == .closed)
        m.startTimer(minutes: 5)
        check("zamanlayıcı kulakta", m.display == .compact(.live(.timer)))
        m.pomo.start()
        check("zamanlayıcı önde, Pomodoro baloncukta", m.display == .compact(.live(.timer)) && m.secondary == .pomodoro)
        m.cancelTimer()
        check("zamanlayıcı bitince Pomodoro öne geçer", m.display == .compact(.live(.pomodoro)) && m.secondary == nil)
        m.media.apply(TrackInfo(title: "Şarkı", artist: "Sanatçı", album: "", duration: 200, position: 0, stamp: clock.t, playing: true, source: .music), source: .music)
        check("müzik ikinci sıraya girer", m.secondary == .media)
        m.settings.set(.pomodoro, false)
        check("kapatılan etkinlik gizlenir", m.display == .compact(.live(.media)))
        m.settings.secondary = false
        pomoOn = false
        m.settings.set(.pomodoro, true)
        check("baloncuk kapatılabilir", m.secondary == nil)
        m.setRobot(busy: true, title: "Süpürüyor", detail: "3 görüntü kaldı")
        check("robot kısa yazısı", m.robot?.short == "3 kaldı")
        m.media.apply(nil, source: .music)
        check("müzik durunca robot görünür", m.display == .compact(.live(.robot)))
        m.settings.enabled = false
        check("ada kapatılınca gizlenir", m.display == .hidden)
        m.settings.enabled = true
        m.fullscreen = true
        check("tam ekranda süren etkinlik görünür", m.display == .compact(.live(.robot)))
        m.settings.fullscreenMode = .hidden
        check("'tamamen gizle' seçiliyse tam ekranda gizlenir", m.display == .hidden)
        m.settings.fullscreenMode = .activities
        m.setRobot(busy: false, title: "", detail: "")
        check("tam ekranda boş ada görünmez", m.display == .hidden)
        m.settings.fullscreenMode = .normal
        check("'her zamanki gibi' seçiliyse tam ekranda da durur", m.display == .closed)
        m.settings.fullscreenMode = .activities
        m.fullscreen = false
        check("tam ekrandan çıkınca boş ada yine görünür", m.display == .closed)
        m.setRobot(busy: true, title: "Süpürüyor", detail: "3 görüntü kaldı")
        m.geometry = IslandGeometry.make(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), left: nil, right: nil, safeTop: 0, menuBar: 25)
        m.setRobot(busy: false, title: "", detail: "")
        check("çentiksiz ekranda boşken görünmez", m.display == .hidden)
    }

    private static func transients() {
        let clock = Clock()
        let m = make(clock)
        m.startTimer(minutes: 10)
        m.volumeChanged(0.4, muted: false)
        check("ses değişince kısa çubuk", m.display == .compact(.transient(.volume(0.4, muted: false))))
        clock.advance(1)
        m.volumeChanged(0.5, muted: false)
        clock.advance(1.2)
        m.tick()
        check("yeni ses olayı süreyi uzatır", m.transient != nil)
        clock.advance(0.5)
        m.tick()
        check("süre bitince eski etkinliğe döner", m.display == .compact(.live(.timer)))
        m.settings.set(.volume, false)
        m.volumeChanged(0.2, muted: false)
        check("kapalı bildirim gösterilmez", m.transient == nil)
        m.expand()
        m.show(.clipboard(.text, "merhaba"))
        check("ada açıkken geçici bildirim bekletilmez", m.transient == nil && m.display == .expanded)
        m.collapse()
        m.powerChanged(PowerState(percent: 64, charging: true, plugged: true), [.plugged])
        check("şarja takınca bildirim", m.display == .compact(.transient(.power(PowerState(percent: 64, charging: true, plugged: true), .plugged))))
        m.powerChanged(PowerState(percent: 64, charging: true, plugged: true), [])
        check("olaysız pil güncellemesi bildirimi değiştirmez", m.transient != nil && m.power?.percent == 64)
        m.robotFinished(collected: 0)
        m.robotFinished(collected: 3)
        check("robot raporu", m.transient == .robot("3 ekran görüntüsü kutuya alındı"))

        // Kara delik
        m.holeFinished(title: "Kısa iş", ok: true)
        check("kısa kara delik işi adayı açmaz", m.transient == .robot("3 ekran görüntüsü kutuya alındı"))
        m.setHole(HoleJob(title: "Video işleniyor", percent: 42))
        check("video ilerlemesi adada akar", m.liveActivities.contains(.hole) && m.hole?.percent == 42)
        m.holeFinished(title: "Video sıkıştırıldı", ok: true)
        check("bitince sonuç söylenir", m.hole == nil && m.transient == .hole("Video sıkıştırıldı", ok: true))
        m.settings.set(.blackHole, false)
        m.setHole(HoleJob(title: "Video işleniyor", percent: 10))
        check("kara delik etkinliği kapatılabilir", !m.liveActivities.contains(.hole))
        m.setHole(nil)
        m.settings.set(.blackHole, true)

        // Bellek ve disk uyarıları
        let gb: UInt64 = 1 << 30
        func stats(_ pressure: Int, used: UInt64 = 8, swap: UInt64 = 0) -> MemoryStats {
            MemoryStats(total: 16 * gb, app: used * gb, wired: gb, compressed: gb, cached: gb, swapUsed: swap * gb, pressure: pressure)
        }
        var heavy = AppMemory(pid: 1, name: "Tarayıcı", bundleID: "x", footprint: 3 * gb); heavy.verdict = .remove
        check("normal bellekte uyarı yok", HealthRules.evaluate(memory: stats(1), volume: nil).isEmpty)
        let warn = HealthRules.evaluate(memory: stats(2), volume: nil, suggested: [heavy])
        check("bellek baskısı uyarısı ve önerisi", warn.first?.kind == .memory && warn.first?.level == .warning
              && warn.first?.action == "Belleği temizle" && warn.first?.body.contains("Tarayıcı") == true, warn.first?.body ?? "")
        check("kritik bellek", HealthRules.evaluate(memory: stats(4), volume: nil).first?.level == .critical)
        check("öneri yoksa Bellek sayfasına yönlendirir", HealthRules.evaluate(memory: stats(2), volume: nil).first?.action == "Bellek sayfası")
        let G: Int64 = 1_000_000_000
        func vol(_ free: Int64) -> VolumeInfo { VolumeInfo(total: 500 * G, available: free * G, free: free * G) }
        check("disk boşken uyarı yok", HealthRules.evaluate(memory: nil, volume: vol(120)).isEmpty)
        check("disk azalınca uyarı", HealthRules.evaluate(memory: nil, volume: vol(12)).first.map { $0.kind == .disk && $0.level == .warning } == true)
        check("disk dolunca kritik ve önce gelir", HealthRules.evaluate(memory: stats(2), volume: vol(3)).first.map { $0.kind == .disk && $0.level == .critical } == true)

        m.dismissAlert()
        clock.advance(5)
        m.tick()
        m.setHealth(HealthRules.evaluate(memory: stats(2), volume: nil, suggested: [heavy]))
        check("uyarı kulakta belirir, ada kendiliğinden açılmaz", m.display == .compact(.live(.health)) && m.alert == nil)
        m.showHealthAlert()
        check("tıklayınca tek tıklık eylemle açılır", m.alert?.action == "Belleği temizle" && m.display == .alert)
        var acted: [HealthWarning.Kind] = []
        m.onHealthAction = { acted.append($0) }
        m.performHealthAction()
        check("eylem çalışır ve uyarı 10 dk susar", acted == [.memory] && m.alert == nil && m.visibleHealth == nil)
        clock.advance(11 * 60)
        check("10 dk sonra yine görünür", m.visibleHealth?.kind == .memory)
        m.setHealth(HealthRules.evaluate(memory: stats(2), volume: vol(3)))
        check("kritik disk adayı bir kez kendiliğinden açar", m.alert.map { if case .health(.disk, .critical) = $0.kind { return true }; return false } == true)
        m.snoozeHealth()
        m.setHealth(HealthRules.evaluate(memory: stats(2), volume: vol(3)))
        check("'sonra' denince aynı uyarı tekrar açılmaz", m.alert == nil && m.visibleHealth?.kind == .memory)
        m.settings.set(.health, false)
        check("uyarılar kapatılabilir", !m.liveActivities.contains(.health))
        m.settings.set(.health, true)
        m.setHealth([])
        check("sorun geçince uyarı kalkar", m.visibleHealth == nil)
    }

    private static func timers() {
        let clock = Clock()
        let m = make(clock)
        var sounds: [String] = []
        m.playSound = { sounds.append($0) }
        m.startTimer(seconds: 60)
        clock.advance(30)
        check("geri sayım ilerler", abs((m.countdown?.remaining(clock.t) ?? 0) - 30) < 0.001)
        m.toggleTimer()
        clock.advance(100)
        check("duraklatınca durur", abs((m.countdown?.remaining(clock.t) ?? 0) - 30) < 0.001 && m.countdown?.running == false)
        m.toggleTimer()
        m.addToTimer(60)
        check("+1 dk eklenir", abs((m.countdown?.remaining(clock.t) ?? 0) - 90) < 0.001 && m.countdown?.total == 120)
        clock.advance(90)
        m.tick()
        check("süre dolunca uyarı açılır", m.countdown == nil && m.display == .alert && m.alert?.title == "Süre doldu")
        check("ses bir kez çalar", sounds == ["Glass"])
        m.tick()
        check("ikinci tıkta ses tekrarlanmaz", sounds.count == 1)
        m.snooze(minutes: 5)
        check("ertele 5 dakikalık zamanlayıcı kurar", m.alert == nil && m.countdown?.total == 300)
        m.cancelTimer()
        m.startTimer(seconds: 10)
        clock.advance(11)
        m.tick()
        clock.advance(31)
        m.tick()
        check("dokunulmayan uyarı kendiliğinden kapanır", m.alert == nil && m.display == .closed)
        m.settings.timerSound = false
        m.startTimer(seconds: 5)
        clock.advance(6)
        m.tick()
        check("ses kapalıysa çalmaz", sounds.count == 2, "\(sounds.count)")
        m.dismissAlert()

        m.toggleStopwatch()
        clock.advance(5)
        m.lapOrReset()
        clock.advance(2.4)
        m.toggleStopwatch()
        check("kronometre ve tur", abs(m.stopwatch.elapsed(clock.t) - 7.4) < 0.001 && m.stopwatch.laps == [5] && !m.stopwatch.running)
        check("kronometre kulakta", m.display == .compact(.live(.stopwatch)))
        m.lapOrReset()
        check("durmuşken sıfırlanır", !m.stopwatch.active)

        check("saat biçimi", IslandFormat.clock(65.4, tenths: true) == "1:05,4" && IslandFormat.clock(3725) == "1:02:05"
              && IslandFormat.clock(59.2, roundUp: true) == "1:00")
        check("dakika yazısı", IslandFormat.minutes(300) == "5 dakikalık" && IslandFormat.minutes(3600) == "1 saatlik" && IslandFormat.minutes(30) == "30 saniyelik")

        // Pomodoro geçişi
        m.pomoTransition(PomoTransition(from: .focus, to: .shortBreak, finished: true), title: "Odak tamamlandı", body: "5 dakika mola.")
        check("Pomodoro geçişi uyarı gösterir", m.display == .alert && m.alert?.kind == .pomodoro(.shortBreak))
        clock.advance(8)
        m.tick()
        check("Pomodoro uyarısı kısa sürer", m.alert == nil)
        m.pomoTransition(PomoTransition(from: .focus, to: .shortBreak, finished: false), title: "x", body: "y")
        check("atlanan odakta uyarı yok", m.alert == nil)
    }

    private static func media() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let music = NowPlayingParser.music(["Name": "Gesi Bağları", "Artist": "Sanatçı", "Album": "Albüm", "Player State": "Playing",
                                            "Total Time": NSNumber(value: 215_000)], now: now)
        check("Müzik bildirimi okunur", music?.title == "Gesi Bağları" && music?.duration == 215 && music?.playing == true)
        check("Müzik durdu bildirimi parça siler", NowPlayingParser.music(["Player State": "Stopped"], now: now) == nil)
        let sp = NowPlayingParser.spotify(["Name": "Parça", "Artist": "Grup", "Player State": "Paused", "Duration": NSNumber(value: 180_000),
                                           "Playback Position": NSNumber(value: 42.5)], now: now)
        check("Spotify bildirimi okunur", sp?.position == 42.5 && sp?.playing == false && sp?.duration == 180)
        let mr = NowPlayingParser.mediaRemote(["kMRMediaRemoteNowPlayingInfoTitle": "Video", "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
                                               "kMRMediaRemoteNowPlayingInfoElapsedTime": NSNumber(value: 10)], now: now)
        check("MediaRemote sözlüğü okunur", mr?.source == .system && mr?.playing == true && mr?.position == 10)
        check("boş MediaRemote yanıtı yok sayılır", NowPlayingParser.mediaRemote([:], now: now) == nil)

        let clock = Clock()
        let np = NowPlaying()
        np.scriptsAllowed = false
        np.now = { clock.t }
        var t = TrackInfo(title: "A", artist: "B", album: "C", duration: 200, position: 0, stamp: clock.t, playing: true, source: .music)
        np.apply(t, source: .music)
        clock.advance(40)
        check("çalarken konum ilerler", abs((np.track?.elapsed(clock.t) ?? 0) - 40) < 0.001)
        t.playing = false
        t.stamp = clock.t
        np.apply(t, source: .music)
        clock.advance(100)
        check("Müzik duraklayınca konum korunur", abs((np.track?.elapsed(clock.t) ?? 0) - 40) < 0.001)
        np.apply(nil, source: .spotify)
        check("başka kaynağın durması parçayı silmez", np.track?.title == "A")
        t.playing = true
        t.stamp = clock.t
        np.apply(t, source: .music)
        np.apply(TrackInfo(title: "Z", artist: "", album: "", duration: 0, position: 0, stamp: clock.t, playing: false, source: .spotify), source: .spotify)
        check("duraklamış Spotify çalan Müziği ezmez", np.track?.title == "A")
        clock.advance(500)
        check("konum süreyi aşmaz", np.track?.elapsed(clock.t) == 200)
        np.togglePlay()
        check("oynat/duraklat iyimser güncellenir", np.track?.playing == false)
        np.seek(to: 30)
        check("konuma atlanır", np.track?.elapsed(clock.t) == 30)

        // Tarayıcı
        let line = "1234|567|{\"t\":\"Gül Pembe\",\"a\":\"Barış Manço\",\"al\":\"\",\"art\":\"https://lh3.googleusercontent.com/x\",\"d\":241.2,\"p\":61.5,\"pl\":true}\n"
            + "88|9|{\"t\":\"(2) Başka | Şarkı - YouTube\",\"a\":\"\",\"al\":\"\",\"art\":\"\",\"d\":100,\"p\":5,\"pl\":false}\nbozuk satır\n"
        let parsed = BrowserMedia.parse(line + "ERR|12|JavaScript kapalı\n", browser: "com.google.Chrome")
        check("tarayıcı satırları okunur", parsed.count == 2 && parsed[0].0 == BrowserTab(browser: "com.google.Chrome", window: "1234", tab: "567")
              && parsed[0].1.title == "Gül Pembe" && parsed[0].1.duration == 241.2 && parsed[0].1.playing, "\(parsed.count)")
        check("sekme başlığı temizlenir", parsed.count == 2 && parsed[1].1.title == "Başka | Şarkı", parsed.last?.1.title ?? "")
        check("çalan sekme seçilir", BrowserMedia.pick(parsed.reversed())?.1.title == "Gül Pembe")
        check("JavaScript AppleScript dizgesini bozmaz", !BrowserMedia.readJS.contains("\"") && !BrowserMedia.readJS.contains("\\")
              && [BrowserMedia.Command.setPlaying(true), .setPlaying(false), .next, .previous, .seek(12)].allSatisfy { !$0.js.contains("\"") && !$0.js.contains("\\") })
        let js = JSContext()!
        let snippets = [BrowserMedia.readJS] + [BrowserMedia.Command.setPlaying(true), .setPlaying(false), .next, .previous, .seek(12)].map(\.js)
        check("sayfa betikleri sözdizimi hatasız", snippets.allSatisfy { src in
            js.setObject(src, forKeyedSubscript: "src" as NSString)
            return js.evaluateScript("(function(){try{new Function(src);return true}catch(e){return false}})()")?.toBool() == true
        })
        let limited = BrowserMedia.parse("ERR|12|JavaScript kapalı\nT|5|6|(1) KIYAMAM - YouTube Music\n", browser: "com.brave.Browser", sounding: true)
        check("ayar kapalıyken sekme başlığı okunur", limited.count == 1 && limited[0].1.title == "KIYAMAM" && limited[0].1.limited && limited[0].1.playing)
        let ff = BrowserMedia.fromTitle("Dinle • Şebnem Paker — Mozilla Firefox", browser: "org.mozilla.firefox", window: "0", tab: "0",
                                        sounding: false, requireSite: true)
        check("Firefox başlığından şarkı ve sanatçı", ff?.1.title == "Dinle" && ff?.1.artist == "Şebnem Paker" && ff?.1.playing == false)
        check("müzik dışı Firefox penceresi yok sayılır", BrowserMedia.fromTitle("GitHub — Mozilla Firefox", browser: "org.mozilla.firefox",
              window: "0", tab: "0", sounding: true, requireSite: true) == nil
              && BrowserMedia.fromTitle("YouTube Music — Mozilla Firefox", browser: "org.mozilla.firefox", window: "0", tab: "0",
                                        sounding: true, requireSite: true) == nil)
        let mixed = [limited[0], (BrowserTab(browser: "x", window: "1", tab: "1"),
                                  BrowserPayload(title: "Tam", artist: "", album: "", artwork: "", duration: 1, position: 0, playing: true))]
        check("tam okunan sekme başlıktan önce gelir", BrowserMedia.pick(mixed)?.1.title == "Tam")
        check("ses süreci tarayıcıya bağlanır", BrowserKind.find("com.google.Chrome")!.owns(audioBundle: "com.google.Chrome.helper")
              && BrowserKind.find("com.apple.Safari")!.owns(audioBundle: "com.apple.WebKit.GPU")
              && BrowserKind.find("org.mozilla.firefox")!.owns(audioBundle: "org.mozilla.plugincontainer")
              && !BrowserKind.find("com.brave.Browser")!.owns(audioBundle: "com.google.Chrome.helper"))
        check("ses süreçleri okunabilir", AudioActivity.playingBundles() != nil)
        for b in BrowserKind.all where b.engine != .firefox && NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.id) != nil {
            var err: NSDictionary?
            let ok = NSAppleScript(source: BrowserMedia.readScript(b))?.compileAndReturnError(&err) ?? false
            check("\(b.name) betiği derlenir", ok, "\(err?[NSAppleScript.errorMessage] ?? "")")
        }
        let bp = NowPlaying()
        bp.scriptsAllowed = false
        bp.now = { clock.t }
        let tab = BrowserTab(browser: "com.google.Chrome", window: "1", tab: "2")
        let pay = BrowserPayload(title: "Gül Pembe", artist: "Barış Manço", album: "", artwork: "", duration: 240, position: 10, playing: true)
        var changes = 0
        bp.onChange = { changes += 1 }
        bp.apply(.browser(pay, tab: tab, now: clock.t), source: .browser)
        clock.advance(1.5)
        var later = pay; later.position = 11.6
        bp.apply(.browser(later, tab: tab, now: clock.t), source: .browser)
        check("tahmini tutan yoklama yeniden çizdirmez", changes == 1 && bp.track?.appBundleID == "com.google.Chrome")
        later.position = 90
        bp.apply(.browser(later, tab: tab, now: clock.t), source: .browser)
        check("ileri sarılınca konum güncellenir", changes == 2 && abs((bp.track?.elapsed(clock.t) ?? 0) - 90) < 0.01)
        bp.apply(nil, source: .browser)
        check("sekme kapanınca parça silinir", bp.track == nil)

        let red = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { r in
            NSColor(srgbRed: 0.7, green: 0.05, blue: 0.08, alpha: 1).setFill(); r.fill(); return true
        }
        let a = NowPlaying.accent(of: red).usingColorSpace(.sRGB)!
        check("kapak rengi baskın renkten gelir", a.redComponent > 0.7 && a.greenComponent < 0.4 && a.blueComponent < 0.45,
              String(format: "%.2f %.2f %.2f", a.redComponent, a.greenComponent, a.blueComponent))
    }

    private static func hover() {
        var h = HoverLogic(delay: 0.15, grace: 0.35)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        check("çentiğe gelince bekler", h.update(inTrigger: true, inExpanded: false, expanded: false, enabled: true, now: t0) == .recheck(0.15))
        check("gecikmeden sonra açar", h.update(inTrigger: true, inExpanded: false, expanded: false, enabled: true, now: t0 + 0.16) == .expand)
        check("açıkken içerideyse bir şey yapmaz", h.update(inTrigger: false, inExpanded: true, expanded: true, enabled: true, now: t0 + 1) == .none)
        _ = h.update(inTrigger: false, inExpanded: false, expanded: true, enabled: true, now: t0 + 2)
        check("geri dönünce kapanmaz", h.update(inTrigger: false, inExpanded: true, expanded: true, enabled: true, now: t0 + 2.2) == .none)
        _ = h.update(inTrigger: false, inExpanded: false, expanded: true, enabled: true, now: t0 + 3)
        check("ayrılınca payla kapanır", h.update(inTrigger: false, inExpanded: false, expanded: true, enabled: true, now: t0 + 3.4) == .collapse)
        var g = HoverLogic(delay: 0.3)
        _ = g.update(inTrigger: true, inExpanded: false, expanded: false, enabled: true, now: t0)
        _ = g.update(inTrigger: false, inExpanded: false, expanded: false, enabled: true, now: t0 + 0.1)
        check("geçip giden fare açmaz", g.update(inTrigger: true, inExpanded: false, expanded: false, enabled: true, now: t0 + 0.35) == .recheck(0.3))
        check("ayar kapalıyken açmaz", g.update(inTrigger: true, inExpanded: false, expanded: false, enabled: false, now: t0 + 5) == .none)
    }

    private static func powerEvents() {
        let a = PowerState(percent: 50, charging: false, plugged: false)
        check("ilk okumada olay yok", PowerWatch.events(old: nil, new: a).isEmpty)
        check("fişe takma", PowerWatch.events(old: a, new: PowerState(percent: 50, charging: true, plugged: true)) == [.plugged])
        check("fişten çıkarma", PowerWatch.events(old: PowerState(percent: 50, charging: true, plugged: true), new: a) == [.unplugged])
        check("%20 altına inince uyarı", PowerWatch.events(old: PowerState(percent: 21, charging: false, plugged: false),
                                                          new: PowerState(percent: 20, charging: false, plugged: false)) == [.low])
        check("uyarı tekrarlanmaz", PowerWatch.events(old: PowerState(percent: 19, charging: false, plugged: false),
                                                     new: PowerState(percent: 18, charging: false, plugged: false)).isEmpty)
        check("%10 altında ikinci uyarı", PowerWatch.events(old: PowerState(percent: 11, charging: false, plugged: false),
                                                           new: PowerState(percent: 10, charging: false, plugged: false)) == [.low])
        check("dolunca bildirim", PowerWatch.events(old: PowerState(percent: 99, charging: true, plugged: true),
                                                   new: PowerState(percent: 100, charging: false, plugged: true)) == [.full])
        check("AirPods tanınır", AudioOutput.guess(name: "Ayşe'nin AirPods Pro", transport: 0) == .airpodsPro
              && AudioOutput.guess(name: "MacBook Air Hoparlörleri", transport: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
    }

    private static func shelfAndPersistence() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("deskling-island-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Ayar alanı geçici klasördeki bir dosyadır; ~/Library/Preferences'a hiçbir şey yazılmaz.
        let suiteName = dir.appendingPathComponent("ayarlar").path
        let suite = UserDefaults(suiteName: suiteName)!
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? fm.removeItem(at: dir)
        }
        let a = dir.appendingPathComponent("rapor.pdf"), b = dir.appendingPathComponent("foto.png")
        for u in [a, b] { try? Data("x".utf8).write(to: u) }

        let clock = Clock()
        let m = make(clock, store: suite)
        let added = m.shelf.add([a, b, a, dir.appendingPathComponent("yok.txt")])
        check("rafa yalnızca var olan dosyalar eklenir", added == 2 && m.shelf.items.count == 2, "\(added)")
        m.shelf.add([b])
        check("aynı dosya öne çıkar, çoğalmaz", m.shelf.items.count == 2 && m.shelf.items.first?.url == b.standardizedFileURL)
        m.shelf.remove(m.shelf.items[0])
        check("raftan kaldırmak dosyayı silmez", fm.fileExists(atPath: b.path) && m.shelf.items.count == 1)
        m.settings.hoverDelay = 0.4
        m.settings.set(.clipboard, false)
        m.settings.customMinutes = 33
        m.startTimer(minutes: 3)
        clock.advance(60)

        let again = make(clock, store: suite)
        check("raf yeniden açılışta hatırlanır", again.shelf.items.map(\.url) == [a.standardizedFileURL])
        check("ayarlar kaydedilir", again.settings.hoverDelay == 0.4 && !again.settings.isOn(.clipboard) && again.settings.customMinutes == 33)
        check("zamanlayıcı yeniden açılışta sürer", abs((again.countdown?.remaining(clock.t) ?? 0) - 120) < 0.001)
        clock.advance(500)
        let late = make(clock, store: suite)
        check("kapalıyken biten zamanlayıcı sessizce düşer", late.countdown == nil && suite.data(forKey: IslandManager.countdownKey) == nil)
        try? fm.removeItem(at: a)
        late.shelf.prune()
        check("silinen dosya raftan düşer", late.shelf.items.isEmpty)
        let mem = IslandSettings(store: nil)
        check("bellekteki ayarlar varsayılanla başlar", mem.enabled && mem.hoverOpen && mem.off.isEmpty && mem.hoverDelay == 0.15)
    }

    /// Her durum gerçekten bir şey çizer mi?
    private static func render() {
        for (name, d) in IslandGallery.states() {
            guard let img = IslandGallery.render(d, scale: 1) else { check("çizim: \(name)", false); continue }
            let dark = IslandGallery.darkPixels(img)
            check("çizim: \(name)", dark > 0.003, String(format: "%.3f", dark))
        }
    }
}

/// README ve göz kontrolü için adanın durumlarını PNG olarak çizer.
@MainActor
enum IslandGallery {
    /// Görünümlerdeki TimelineView gerçek saati kullanır; galeri de onunla başlar.
    static let clock: IslandCheck.Clock = { let c = IslandCheck.Clock(); c.t = Date(); return c }()

    /// Galeri için hazırlanmış bir ada: çalan parça, Pomodoro, raf, pil.
    static func states() -> [(String, IslandManager)] {
        func base() -> IslandManager {
            let m = IslandCheck.make(clock)
            m.pomoEnabled = { true }
            m.pomoDrink = { .tea }
            m.power = PowerState(percent: 76, charging: true, plugged: true)
            m.volume = 0.6
            return m
        }
        func withMusic(_ m: IslandManager) -> IslandManager {
            m.media.apply(TrackInfo(title: "Bir Derdim Var", artist: "Mor ve Ötesi", album: "Dünya Yalan Söylüyor", duration: 262,
                                    position: 97, stamp: clock.t, playing: true, source: .music), source: .music)
            m.media.setArtwork(sampleArtwork(), key: m.media.track!.key)
            return m
        }
        var out: [(String, IslandManager)] = []
        out.append(("1-kapali", base()))
        out.append(("2-muzik", withMusic(base())))
        let p = withMusic(base()); p.pomo.start(); clock.advance(0); out.append(("3-pomodoro-baloncuk", p))
        let charge = base(); charge.powerChanged(PowerState(percent: 76, charging: true, plugged: true), [.plugged]); out.append(("4-sarj", charge))
        let vol = base(); vol.volumeChanged(0.62, muted: false); out.append(("5-ses", vol))
        let dev = base(); dev.show(.device(AudioOutput(name: "AirPods Pro", kind: .airpodsPro))); out.append(("6-kulaklik", dev))
        let home = withMusic(base()); home.pomo.start(); home.expand(page: .home); out.append(("7-acik-simdi", home))
        let timer = base(); timer.startTimer(minutes: 25); timer.toggleStopwatch(); timer.expand(page: .timer); out.append(("8-acik-zamanlayici", timer))
        let shelf = base()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deskling-island-gallery")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = ["Sunum.key", "Rapor.pdf", "Kapak.png", "Notlar.txt"].map { dir.appendingPathComponent($0) }
        for f in files { try? Data("x".utf8).write(to: f) }
        shelf.shelf.add(files)
        shelf.expand(page: .shelf)
        out.append(("9-acik-raf", shelf))
        let alert = base(); alert.startTimer(seconds: 1); clock.advance(2); alert.tick(); out.append(("10-uyari", alert))
        let hole = base(); hole.setHole(HoleJob(title: "Video işleniyor", percent: 64)); out.append(("11-kara-delik", hole))
        let holeDone = base(); holeDone.setHole(HoleJob(title: "Video işleniyor", percent: 99)); holeDone.holeFinished(title: "Video 1,2 GB → 180 MB", ok: true)
        out.append(("12-kara-delik-bitti", holeDone))
        let robot = base(); robot.robotFinished(collected: 4); out.append(("13-robot-ozet", robot))
        let gb: UInt64 = 1 << 30
        var heavy = AppMemory(pid: 1, name: "Tarayıcı", bundleID: "x", footprint: 3 * gb); heavy.verdict = .remove
        var code = AppMemory(pid: 2, name: "Kod Düzenleyici", bundleID: "y", footprint: 2 * gb); code.verdict = .remove
        let mem = MemoryStats(total: 16 * gb, app: 11 * gb, wired: 2 * gb, compressed: 2 * gb, cached: gb, swapUsed: 3 * gb, pressure: 2)
        let warn = withMusic(base()); warn.setHealth(HealthRules.evaluate(memory: mem, volume: nil, suggested: [heavy, code])); out.append(("14-bellek-kulak", warn))
        let warnAlert = base(); warnAlert.setHealth(HealthRules.evaluate(memory: mem, volume: nil, suggested: [heavy, code])); warnAlert.showHealthAlert()
        out.append(("15-bellek-uyari", warnAlert))
        let diskAlert = base()
        diskAlert.setHealth(HealthRules.evaluate(memory: nil, volume: VolumeInfo(total: 500_000_000_000, available: 3_400_000_000, free: 3_000_000_000)))
        out.append(("16-disk-uyari", diskAlert))
        return out
    }

    static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 200, height: 200), flipped: false) { r in
            let g = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.16, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.95, green: 0.35, blue: 0.45, alpha: 1)])
            g?.draw(in: r, angle: -55)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 60, y: 60, width: 80, height: 80)).fill()
            NSColor(srgbRed: 0.42, green: 0.16, blue: 0.62, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 90, y: 90, width: 20, height: 20)).fill()
            return true
        }
    }

    /// Adayı, menü çubuğunu andıran bir şeridin üstünde çizer.
    static func render(_ m: IslandManager, scale: CGFloat) -> CGImage? {
        let view = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.78), Color(red: 0.62, green: 0.5, blue: 0.74)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: m.geometry.notch.height)
            IslandRootView(manager: m, interactive: false)
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height, alignment: .top)
        let r = ImageRenderer(content: view)
        r.scale = scale
        return r.cgImage
    }

    static func darkPixels(_ img: CGImage) -> Double {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var n = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i] < 12 && px[i + 1] < 12 && px[i + 2] < 12 { n += 1 }
        return Double(n) / Double(w * h)
    }

    static func run(output: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var images: [(String, CGImage)] = []
        for (name, m) in states() {
            guard let img = render(m, scale: 2) else { print("ÇİZİLEMEDİ \(name)"); return 1 }
            images.append((name, img))
            write(img, output.appendingPathComponent(name + ".png"))
        }
        // README için: kapalı olmayan durumlardan seçilmiş bir pano.
        let pick = ["2-muzik", "3-pomodoro-baloncuk", "4-sarj", "7-acik-simdi", "8-acik-zamanlayici", "9-acik-raf"]
        let chosen = images.filter { pick.contains($0.0) }.map(\.1)
        if let board = board(chosen) { write(board, output.appendingPathComponent("ada.png")) }
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("deskling-island-gallery"))
        print("ADA_GALERI \(images.count) görüntü: \(output.path)")
        return 0
    }

    /// Küçük durumları kırpar, büyükleri tam yüksekliğiyle alt alta dizer.
    private static func board(_ list: [CGImage]) -> CGImage? {
        guard let first = list.first else { return nil }
        let w = first.width
        let crops: [CGImage] = list.map { img in
            let dark = rowsWithInk(img)
            let h = min(img.height, dark + 40)
            return img.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) ?? img
        }
        let total = crops.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(data: nil, width: w, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var y = total
        for c in crops {
            y -= c.height
            ctx.draw(c, in: CGRect(x: 0, y: y, width: c.width, height: c.height))
        }
        return ctx.makeImage()
    }

    /// Siyah adanın bittiği satır (üstten).
    private static func rowsWithInk(_ img: CGImage) -> Int {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return h }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var last = 0
        for row in 0..<h {
            let i = (row * w + w / 2) * 4
            if px[i] < 12 && px[i + 1] < 12 && px[i + 2] < 12 { last = row }
        }
        return last
    }

    private static func write(_ img: CGImage, _ url: URL) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

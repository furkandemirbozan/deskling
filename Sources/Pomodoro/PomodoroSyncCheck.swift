import AppKit

/// Pomodoro'nun robot ve karla senkronunu geçici bir masaüstü klasöründe dener.
/// Gerçek masaüstüne dokunmaz; değiştirdiği ayarları sonunda eski haline getirir.
final class PomodoroSyncCheck {
    private let fm = FileManager.default
    private let tmp: URL
    private var failures = 0
    private let clock = PomodoroCheck.Clock()
    private var model: AppModel!
    private let touched = ["mode", "pomoEnabled", "pomoQuietFocus", "pomoCleanOnBreak", "pomoNotify", "pomoSound", "pomoKeepAwake"]
    private var saved: [(String, Any?)] = []

    init() {
        tmp = fm.temporaryDirectory.appendingPathComponent("deskling-pomo-sync-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    private func finish() {
        let d = UserDefaults.standard
        for (k, v) in saved { v == nil ? d.removeObject(forKey: k) : d.set(v, forKey: k) }
        try? fm.removeItem(at: tmp)
        print(failures == 0 ? "SENKRON_GECTI" : "SENKRON_KALDI hata=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    private func shot(_ name: String, age: TimeInterval) {
        let url = tmp.appendingPathComponent(name)
        SelfTest.png(url, comment: "Screenshot")
        try? fm.setAttributes([.creationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    func run() {
        after(150) { [self] in print("SENKRON_ZAMAN_ASIMI"); finish() }
        let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? AppInfo.bundleID) ?? [:]
        saved = touched.map { ($0, own[$0]) }
        shot("eski.png", age: 7200)
        shot("kilitli.png", age: 30)
        model = AppModel(desktopOverride: tmp)
        model.silent = true
        model.mode = .approval   // otomatik toplama testi karıştırmasın
        model.pomoNotify = false
        model.pomoSound = false
        model.pomoKeepAwake = false
        model.pomoEnabled = true
        model.pomo.now = { [clock] in clock.t }
        model.pomoQuietFocus = true
        model.pomoCleanOnBreak = true

        // 1) Odakta robot duraklar, odak bitince devam eder.
        model.runDemo()
        after(0.6) { [self] in
            check("robot görevde", model.engine.isBusy && !model.engine.paused)
            model.pomo.start()
            check("odak başlayınca robot duraklar", model.engine.paused && model.quietActive)
            model.pomo.pause()
            check("odak duraklatılınca robot devam eder", !model.engine.paused && !model.quietActive)
            model.pomo.start()
            model.pomoQuietFocus = false
            check("ayar kapatılınca hemen devam eder", !model.engine.paused && !model.quietActive)
            model.pomoQuietFocus = true
            check("ayar açılınca yeniden duraklar", model.engine.paused)
            model.pomo.reset()
            check("sıfırlanınca robot kaldığı yerden sürer", !model.engine.paused && !model.quietActive)
            model.engine.togglePause()
            model.pomo.start()
            model.pomo.reset()
            check("kullanıcının duraklattığı robotu odak sonu başlatmaz", model.engine.paused)
            model.engine.togglePause()
            model.goHome()
            waitIdle { [self] in breakCleanup() }
        }
    }

    private func waitIdle(_ then: @escaping () -> Void) {
        if model.engine.isIdle { then(); return }
        after(0.3) { [self] in waitIdle(then) }
    }

    /// 2) Molada yalnızca odak sırasında düşen, kilitsiz görüntüler toplanır.
    private func breakCleanup() {
        clock.t = Date()
        model.pomo.start()
        check("odak başlangıcı kaydedilir", model.pomoFocusStarted == clock.t)
        shot("yeni.png", age: 0)
        shot("yeni-kilitli.png", age: 0)
        model.scan { [self] in
            // Kilit, taramanın gördüğü kimlikle konur (geçici klasör /private altında görünür).
            for s in model.shots where s.name.contains("kilitli") { model.protected.insert(s.id) }
            check("kilitli görüntüler işaretlendi", model.protected.count >= 2)
            model.onMissionFinished = { [self] in
                let box = Set((try? fm.contentsOfDirectory(atPath: model.collectionDir.path)) ?? [])
                check("yalnızca odakta düşen görüntü toplanır", box == ["yeni.png"], "\(box.sorted())")
                check("eski ve kilitli görüntüler yerinde kalır",
                      ["eski.png", "kilitli.png", "yeni-kilitli.png"].allSatisfy { fm.fileExists(atPath: tmp.appendingPathComponent($0).path) })
                noCleanupWhenOff()
            }
            after(0.5) { [self] in
                clock.advance(25 * 60)
                model.pomo.tick()
                check("mola başladı ve odak susturması kalktı", model.pomo.phase == .shortBreak && !model.quietActive)
                after(2) { [self] in
                    check("molada robot yola çıkar", model.lastBreakCleanup == ["yeni.png"] && model.engine.isBusy,
                          "\(model.lastBreakCleanup ?? [])")
                }
            }
        }
    }

    /// 3) Ayar kapalıyken ya da odak atlanınca robot kalkmaz.
    private func noCleanupWhenOff() {
        model.onMissionFinished = nil
        waitIdle { [self] in
            model.pomo.reset()
            shot("yeni2.png", age: 0)
            model.pomoCleanOnBreak = false
            clock.t = Date()
            model.pomo.start()
            clock.advance(25 * 60)
            model.pomo.tick()
            after(1.5) { [self] in
                check("ayar kapalıyken molada robot kalkmaz", model.engine.isIdle && fm.fileExists(atPath: tmp.appendingPathComponent("yeni2.png").path))
                model.pomoCleanOnBreak = true
                model.pomo.reset()
                clock.t = Date()
                model.pomo.start()
                model.pomo.skip()
                after(1.5) { [self] in
                    check("atlanan odaktan sonra robot kalkmaz", model.engine.isIdle && fm.fileExists(atPath: tmp.appendingPathComponent("yeni2.png").path))
                    model.pomo.reset()
                    finish()
                }
            }
        }
    }
}

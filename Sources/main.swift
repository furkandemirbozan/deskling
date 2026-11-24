import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var overlay: OverlayController!
    private var panel: NSWindow?
    private var status: NSStatusItem!
    private var rug: RugController!
    private var rugCheck: RugCheck?
    private var motionCheck: MotionCheck?
    private var snow: SnowController?
    private var hole: BlackHoleController?
    private var holeCheck: HoleUICheck?
    private var clipPanel: ClipboardPanelController?
    private var devCheck: DevCheck?
    private var clipCheck: ClipboardCheck?
    private var statusSymbol = "robot"
    private var drink: DrinkController?
    private var drinkCheck: DrinkUICheck?
    private var syncCheck: PomodoroSyncCheck?
    private var island: IslandController?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.applicationIconImage = RobotArt.appIcon(256)
        let args = CommandLine.arguments
        if args.contains("--rug-check") {
            let i = args.firstIndex(of: "--rug-check")!
            let out = i + 1 < args.count ? URL(fileURLWithPath: args[i + 1]) : nil
            rugCheck = RugCheck(output: out)
            rugCheck?.run()
            return
        }
        if let i = args.firstIndex(of: "--motion-check") {
            motionCheck = MotionCheck(output: i + 1 < args.count ? URL(fileURLWithPath: args[i + 1]) : nil)
            motionCheck?.run()
            return
        }
        if args.contains("--dev-check") {
            devCheck = DevCheck()
            devCheck?.run()
            return
        }
        if args.contains("--pomo-sync-check") {
            syncCheck = PomodoroSyncCheck()
            syncCheck?.run()
            return
        }
        if let i = args.firstIndex(of: "--drink-ui-check") {
            drinkCheck = DrinkUICheck(output: i + 1 < args.count ? URL(fileURLWithPath: args[i + 1]) : nil)
            drinkCheck?.run()
            return
        }
        if args.contains("--clip-check") {
            clipCheck = ClipboardCheck()
            clipCheck?.run()
            return
        }
        if let i = args.firstIndex(of: "--hole-ui-check") {
            holeCheck = HoleUICheck(output: i + 1 < args.count ? URL(fileURLWithPath: args[i + 1]) : nil)
            holeCheck?.run()
            return
        }
        if args.contains("--auto-check") {
            runAutoCheck()
            return
        }
        if args.contains("--patrol-check") {
            runPatrolCheck()
            return
        }
        if args.contains("--double-click-check") {
            runClickCheck()
            return
        }
        if let i = args.firstIndex(of: "--demo-run"), i + 1 < args.count {
            runDemoCheck(output: URL(fileURLWithPath: args[i + 1]))
            return
        }
        Migration.run()   // Robo Süpürge'den kalan ayar ve veriler yeni isme taşınır
        model = AppModel()
        overlay = OverlayController()
        rug = RugController(store: model.rugStore, restoreFallback: model.desktop, persist: true) { [weak self] in
            self?.model.rugMoved()
        }
        model.connectRug(rug)
        rug.lock.enabled = { [weak self] in self?.model.rugTouchID ?? false }
        model.attach(overlay)
        snow = SnowController()
        model.connectSnow(snow!)
        hole = BlackHoleController()
        model.connectHole(hole!)
        setUpClipboard()
        let drink = DrinkController(pomo: model.pomo)
        drink.onOpenSettings = { [weak self] in
            self?.model.panelTab = .pomodoro
            self?.showPanel()
        }
        self.drink = drink
        model.connectDrink(drink)
        model.island.onOpenSettings = { [weak self] in
            self?.model.island.collapse()
            self?.model.panelTab = .island
            self?.showPanel()
        }
        island = IslandController(manager: model.island)
        model.memory.startTracking()
        model.startHealthWatch()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: AppInfo.name)
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        model.onNeedsPanel = { [weak self] in self?.showPanel() }
        model.pomoListeners.append { [weak self] in self?.updateStatusButton() }
        updateStatusButton()
    }

    /// Sayaç çalışırken menü çubuğunda içeceğin simgesi ve kalan süre görünür.
    private func updateStatusButton() {
        guard let button = status?.button else { return }
        let label = model.pomoMenuLabel
        // Odakta içeceğin kendi simgesi, kalan süreyle birlikte boşalır; molada yürüyen adam.
        let fill = 1 - model.pomo.progress * 0.92
        let key = label == nil ? "robot" : model.pomo.phase.isBreak ? "mola"
            : "\(model.pomoDrink.rawValue)-\(Int((fill * 8).rounded()))"
        if statusSymbol != key {
            button.image = label == nil
                ? NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: AppInfo.name)
                : model.pomo.phase.isBreak ? NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Mola")
                : DrinkIcons.menuIcon(model.pomoDrink, fill: fill)
            statusSymbol = key
        }
        let text = label.map { " " + $0 } ?? ""
        if button.attributedTitle.string != text {
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
            button.imagePosition = label == nil ? .imageOnly : .imageLeading
        }
        button.alphaValue = label == nil || model.pomo.running ? 1 : 0.55   // duraklatılınca soluk
    }

    /// Uygulama açıkken simgesine çift tıklanırsa denetim paneli açılır; temizlik yalnızca robottan başlar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    /// 1 saati geçen görüntülerin kendiliğinden toplandığını doğrular.
    private func runAutoCheck() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("robo-auto-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let ages: [(String, Double)] = [("eski.png", 7200), ("kilitli.png", 7200), ("yeni.png", 3000)]
        for (name, age) in ages {
            let url = tmp.appendingPathComponent(name)
            SelfTest.png(url, comment: "Screenshot")
            try? fm.setAttributes([.creationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        model = AppModel(desktopOverride: tmp)
        model.silent = true
        model.mode = .automatic
        model.minAge = 60
        model.protected = Set(ScreenshotDetector.scan(tmp).filter { $0.name == "kilitli.png" }.map(\.id))
        let exists = { (n: String) in fm.fileExists(atPath: tmp.appendingPathComponent(n).path) }
        model.onMissionFinished = { [self] in
            let inBox = Set((try? fm.contentsOfDirectory(atPath: model.collectionDir.path)) ?? [])
            let ok = !exists("eski.png") && exists("kilitli.png") && exists("yeni.png") && inBox == ["eski.png"]
            try? fm.removeItem(at: tmp)
            print(ok ? "OTOMATIK_GECTI kutu=\(inBox.sorted())" : "OTOMATIK_KALDI kutu=\(inBox.sorted())")
            exit(ok ? 0 : 1)
        }
        overlay = OverlayController()
        model.attach(overlay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("OTOMATIK_ZAMAN_ASIMI"); exit(2) }
    }

    /// Boş klasörde çift tıklamanın robotu tura çıkardığını doğrular.
    private func runPatrolCheck() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("robo-patrol-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        model = AppModel(desktopOverride: tmp)
        model.silent = true
        overlay = OverlayController()
        model.attach(overlay)
        let engine = model.engine
        var farthest: CGFloat = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { _ in
            farthest = max(farthest, hypot(engine.pos.x - engine.basePoint.x, engine.pos.y - engine.basePoint.y))
        }
        RunLoop.main.add(t, forMode: .common)
        model.onMissionFinished = { [self] in
            let ok = farthest > 200 && engine.pos == engine.basePoint && model.history.isEmpty
            try? fm.removeItem(at: tmp)
            print(ok ? "TUR_GECTI mesafe=\(Int(farthest))" : "TUR_KALDI mesafe=\(Int(farthest))")
            exit(ok ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in overlay.simulateClick(count: 2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("TUR_ZAMAN_ASIMI"); exit(2) }
    }

    /// Geçici klasörde gerçek tıklama yolunu ve temizliği uçtan uca doğrular.
    private func runClickCheck() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("robo-click-\(UUID().uuidString)").resolvingSymlinksInPath()
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        for n in ["bir.png", "iki.png", "kilitli.png"] { SelfTest.png(tmp.appendingPathComponent(n), comment: "Screenshot") }
        SelfTest.png(tmp.appendingPathComponent("tatil.png"), comment: nil)
        model = AppModel(desktopOverride: tmp)
        model.silent = true
        overlay = OverlayController()
        model.attach(overlay)
        model.protected = Set(ScreenshotDetector.scan(tmp).filter { $0.name == "kilitli.png" }.map(\.id))
        let exists = { (n: String) in fm.fileExists(atPath: tmp.appendingPathComponent(n).path) }
        var boxOpened = false
        model.openCollection = { boxOpened = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            overlay.simulateClick(count: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let singleIgnored = !model.engine.isBusy && exists("bir.png")
                model.onMissionFinished = { [self] in
                    overlay.simulateClick(count: 1, onStation: true)
                    let inBox = Set((try? fm.contentsOfDirectory(atPath: model.collectionDir.path)) ?? [])
                    let ok = singleIgnored && !exists("bir.png") && !exists("iki.png") && exists("kilitli.png")
                        && exists("tatil.png") && model.history.count == 2
                        && inBox == ["bir.png", "iki.png"] && boxOpened
                    try? fm.removeItem(at: tmp)
                    print(ok ? "HAZNE_GECTI kutu=\(inBox.sorted())" : "HAZNE_KALDI tek=\(singleIgnored) gecmis=\(model.history.count) kutu=\(inBox.sorted()) acildi=\(boxOpened)")
                    exit(ok ? 0 : 1)
                }
                overlay.simulateClick(count: 2)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("CIFT_TIK_ZAMAN_ASIMI"); exit(2) }
    }

    /// Boş geçici klasörle demoyu oynatır; gerçek Masaüstü taranmaz.
    private func runDemoCheck(output: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("robo-demo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        model = AppModel(desktopOverride: tmp)
        model.silent = true
        overlay = OverlayController()
        model.attach(overlay)
        model.runDemo()
        var seen: Set<String> = []
        let root = overlay.root
        let engine = model.engine
        let watcher = Timer(timeInterval: 0.05, repeats: true) { _ in
            let key: String
            switch engine.phase {
            case .scanning: key = "1-tarama"
            case .driving: key = "2-surus"
            case .vacuuming: key = "3-supurme"
            case .dumping: key = "4-bosaltma"
            default: return
            }
            guard engine.phase == .driving || seen.isEmpty || !seen.contains(key) else { return }
            if seen.insert(key).inserted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    SelfTest.capture(root, to: output.appendingPathComponent(key + ".png"))
                }
            }
        }
        RunLoop.main.add(watcher, forMode: .common)
        model.onDemoFinished = {
            print("DEMO_TAMAM asamalar=\(seen.sorted())")
            try? FileManager.default.removeItem(at: tmp)
            exit(0)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = NSMenuItem(title: "\(model.statusTitle) · %\(model.battery)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        add(menu, "Denetim Panelini Aç", #selector(showPanel))
        if model.clipEnabled {
            add(menu, "Pano Geçmişi  \(model.clipShortcut.label)", #selector(openClipboard))
        }
        add(menu, "Portlar ve Servisler", #selector(openPorts))
        if model.pomoEnabled {
            menu.addItem(.separator())
            let info = NSMenuItem(title: model.pomoSummary, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            let p = model.pomo
            add(menu, p.phase == .idle ? "Odak Başlat" : p.running ? "Duraklat" : "Devam Et", #selector(pomoToggle))
            add(menu, model.pomoShowDrink ? "İçeceği Gizle" : "İçeceği Göster", #selector(toggleDrink))
            if p.phase != .idle {
                add(menu, p.phase == .focus ? "Molaya Geç" : "Molayı Atla", #selector(pomoSkip))
                add(menu, "Sayacı Sıfırla", #selector(pomoReset))
            }
            menu.addItem(.separator())
        }
        let isl = model.island
        add(menu, isl.settings.enabled ? "Dinamik Adayı Kapat" : "Dinamik Adayı Aç", #selector(toggleIsland))
        if isl.settings.enabled {
            if isl.countdown != nil {
                add(menu, isl.countdown?.running == true ? "Zamanlayıcıyı Duraklat" : "Zamanlayıcıyı Sürdür", #selector(islandTimerToggle))
                add(menu, "Zamanlayıcıyı İptal Et", #selector(islandTimerCancel))
            } else {
                let item = NSMenuItem(title: "Zamanlayıcı Başlat", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for n in [1, 5, 10, 15, 25, 45, 60] {
                    let i = NSMenuItem(title: n >= 60 ? "\(n / 60) saat" : "\(n) dakika", action: #selector(islandTimer(_:)), keyEquivalent: "")
                    i.target = self
                    i.tag = n
                    sub.addItem(i)
                }
                item.submenu = sub
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        add(menu, "Toz Haznesini Aç", #selector(openBox))
        add(menu, model.snowEnabled ? "Karı Durdur" : "Kar Yağdır", #selector(toggleSnow))
        add(menu, model.snowPlowEnabled ? "Küreme Aracını Kapat" : "Küreme Aracını Aç", #selector(togglePlow))
        add(menu, "Halının Altını Aç", #selector(openRug))
        add(menu, model.rugVisible ? "Halıyı Gizle" : "Halıyı Göster", #selector(toggleRug))
        add(menu, model.holeEnabled ? "Kara Deliği Gizle" : "Kara Deliği Göster", #selector(toggleHole))
        if model.busy {
            add(menu, model.paused ? "Devam Et" : "Duraklat", #selector(pause))
            add(menu, "İstasyona Dön", #selector(home))
        } else if !model.selected.isEmpty {
            add(menu, "\(model.selected.count) Görüntüyü Topla", #selector(clean))
        }
        menu.addItem(.separator())
        add(menu, "Çıkış", #selector(quit))
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc func showPanel() {
        if panel == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = AppInfo.name
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PanelView(model: model))
            w.center()
            panel = w
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc func openBox() { model.openCollection() }
    @objc func toggleIsland() { model.island.settings.enabled.toggle() }
    @objc func islandTimer(_ sender: NSMenuItem) { model.island.startTimer(minutes: sender.tag) }
    @objc func islandTimerToggle() { model.island.toggleTimer() }
    @objc func islandTimerCancel() { model.island.cancelTimer() }
    @objc func toggleSnow() { model.snowEnabled.toggle() }
    @objc func togglePlow() { model.snowPlowEnabled.toggle() }
    @objc func openRug() { rug.openFolder() }
    @objc func toggleHole() { model.holeEnabled.toggle() }
    @objc func openClipboard() { clipPanel?.show() }
    @objc func pomoToggle() { model.pomo.toggle() }
    @objc func pomoSkip() { model.pomo.skip() }
    @objc func pomoReset() { model.pomo.reset() }
    @objc func toggleDrink() { model.pomoShowDrink.toggle() }
    @objc func openPorts() {
        model.panelTab = .ports
        showPanel()
    }

    /// Pano izleme, genel kısayol ve yüzer pencere.
    private func setUpClipboard() {
        let panel = ClipboardPanelController(store: model.clipboard)
        clipPanel = panel
        model.clipboard.limit = model.clipLimit
        model.clipboard.enabled = model.clipEnabled
        let apply: (ClipShortcut?) -> Void = { [weak self] s in
            guard let self else { return }
            panel.setShortcut(self.model.clipEnabled ? s : nil)
            self.model.clipShortcutWorks = !self.model.clipEnabled || panel.shortcutWorks
        }
        model.onShortcutChange = apply
        model.onShortcutRecording = { [weak self] recording in
            guard let self else { return }
            panel.setShortcut(recording || !self.model.clipEnabled ? nil : self.model.clipShortcut)
        }
        apply(model.clipShortcut)
    }
    @objc func toggleRug() {
        model.rugVisible.toggle()
    }
    @objc func pause() { model.togglePause() }
    @objc func home() { model.goHome() }
    @objc func clean() { model.cleanSelected() }
    @objc func quit() { NSApp.terminate(nil) }
}

let arguments = CommandLine.arguments
if arguments.contains("--snow-windows") {
    print("takip_edilen_pencere=\(SnowController.visibleWindows().count)")
    exit(0)
}
if let i = arguments.firstIndex(of: "--snow-check") {
    exit(SnowCheck.run(output: i + 1 < arguments.count ? URL(fileURLWithPath: arguments[i + 1]) : nil))
}
if let i = arguments.firstIndex(of: "--sculpt-check") {
    exit(SculptCheck.run(output: i + 1 < arguments.count ? URL(fileURLWithPath: arguments[i + 1]) : nil))
}
if let i = arguments.firstIndex(of: "--drink-gallery"), i + 1 < arguments.count {
    exit(DrinkGallery.run(output: URL(fileURLWithPath: arguments[i + 1])))
}
if let i = arguments.firstIndex(of: "--disk-gallery"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { DiskGallery.run(output: arguments[i + 1]) })
}
if arguments.contains("--disk-report") {
    exit(DiskReport.run())
}
if arguments.contains("--disk-check") {
    exit(DiskCheck.run())
}
if arguments.contains("--rug-lock-check") {
    exit(RugLockCheck.run())
}
if arguments.contains("--island-check") {
    exit(MainActor.assumeIsolated { IslandCheck.run() })
}
if let i = arguments.firstIndex(of: "--island-gallery"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { IslandGallery.run(output: URL(fileURLWithPath: arguments[i + 1])) })
}
if arguments.contains("--pomo-check") {
    exit(PomodoroCheck.run())
}
if arguments.contains("--migration-check") {
    exit(MigrationCheck.run())
}
if let i = arguments.firstIndex(of: "--hole-check") {
    exit(HoleCheck.run(output: i + 1 < arguments.count ? URL(fileURLWithPath: arguments[i + 1]) : nil))
}
if arguments.contains("--login-status") {
    print("giris_durumu=\(SMAppService.mainApp.status.rawValue)")   // 0 kayıtsız, 1 etkin, 2 onay bekliyor, 3 bulunamadı
    exit(0)
}
if arguments.contains("--self-test") {
    exit(SelfTest.run())
}
if let i = arguments.firstIndex(of: "--export-icons"), i + 1 < arguments.count {
    SelfTest.exportIcons(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    _ = NSApplication.shared
    SelfTest.snapshots(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

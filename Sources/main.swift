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
        model = AppModel()
        overlay = OverlayController()
        rug = RugController(store: model.rugStore, restoreFallback: model.desktop, persist: true) { [weak self] in
            self?.model.rugMoved()
        }
        model.connectRug(rug)
        model.attach(overlay)

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: "Robo Süpürge")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        model.onNeedsPanel = { [weak self] in self?.showPanel() }
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
        add(menu, "Toz Haznesini Aç", #selector(openBox))
        add(menu, "Halının Altını Aç", #selector(openRug))
        add(menu, model.rugVisible ? "Halıyı Gizle" : "Halıyı Göster", #selector(toggleRug))
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
            w.title = "Robo Süpürge"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PanelView(model: model))
            w.center()
            panel = w
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc func openBox() { model.openCollection() }
    @objc func openRug() { NSWorkspace.shared.open(model.rugStore.dir) }
    @objc func toggleRug() {
        model.rugVisible.toggle()
    }
    @objc func pause() { model.togglePause() }
    @objc func home() { model.goHome() }
    @objc func clean() { model.cleanSelected() }
    @objc func quit() { NSApp.terminate(nil) }
}

let arguments = CommandLine.arguments
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

import AppKit

/// Halıyı geçici klasörde, gerçek pencere olaylarıyla uçtan uca dener. Gerçek masaüstüne dokunmaz.
final class RugCheck {
    private let fm = FileManager.default
    private let tmp: URL
    private let output: URL?
    private let model: AppModel
    private let overlay: OverlayController
    private let rug: RugController
    private var failures = 0

    init(output: URL?) {
        self.output = output
        tmp = fm.temporaryDirectory.appendingPathComponent("robo-rug-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        if let output { try? fm.createDirectory(at: output, withIntermediateDirectories: true) }
        for n in ["gorunen.png", "ortulu.png", "sakli.png"] { SelfTest.png(tmp.appendingPathComponent(n), comment: "Screenshot") }
        let folder = tmp.appendingPathComponent("Gizli Klasor")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? "gizli".write(to: folder.appendingPathComponent("not.txt"), atomically: true, encoding: .utf8)

        model = AppModel(desktopOverride: tmp)
        model.silent = true
        model.positionProvider = { names, _, done in
            let fixed = ["ortulu.png": CGPoint(x: 500, y: 500), "gorunen.png": CGPoint(x: 800, y: 500)]
            done(fixed.filter { names.contains($0.key) })
        }
        overlay = OverlayController()
        rug = RugController(store: model.rugStore, restoreFallback: tmp, persist: false) {}
        model.connectRug(rug)
        model.rugFrameLocal = { CGRect(x: 450, y: 450, width: 100, height: 100) }
        model.attach(overlay)
    }

    private func check(_ name: String, _ ok: Bool) {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name)
        if !ok { failures += 1 }
    }

    private func exists(_ n: String) -> Bool { fm.fileExists(atPath: tmp.appendingPathComponent(n).path) }

    private func send(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: rug.window.windowNumber, context: nil, eventNumber: 1,
                                         clickCount: clicks, pressure: 1) else { return }
        rug.window.sendEvent(e)
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    private func snap(_ name: String) {
        guard let output else { return }
        rug.view.renderPNG(to: output.appendingPathComponent(name), background: CGColor(srgbRed: 0.42, green: 0.55, blue: 0.62, alpha: 1))
    }

    /// Boyut ve göster/gizle ayarları, panelin kullandığı model üzerinden denenir.
    private func sizeAndVisibility(then next: @escaping () -> Void) {
        let view = rug.view
        let center = CGPoint(x: rug.window.frame.midX, y: rug.window.frame.midY)
        model.rugScale = 0.7
        let small = RugView.sizeFor(scale: 0.7)
        check("halı küçültülür", abs(rug.window.frame.width - small.width) < 1 && abs(rug.window.frame.height - small.height) < 1)
        check("boyut değişince halının ortası kaymaz", abs(rug.window.frame.midX - center.x) < 1 && abs(rug.window.frame.midY - center.y) < 1)

        // Köşeye tek tıklayınca açılan katta bırakma alanı görünmeli.
        let corner = view.testPoint(cornerOffset: CGPoint(x: -8, y: -8))
        send(.leftMouseDown, corner)
        send(.leftMouseUp, corner)
        after(0.5) { [self] in
            check("köşeye tıklayınca bırakma alanı açılır", view.isFolded && view.testShowsUnderside)
            snap("hali-kucuk.png")
            sizeLimits(then: next)
        }
    }

    private func sizeLimits(then next: @escaping () -> Void) {
        let view = rug.view
        model.rugScale = 1.6
        let screen = DesktopMap.screen.frame.insetBy(dx: -RugView.padding, dy: -RugView.padding)
        check("büyütünce katlama kapanır ve halı ekranda kalır", !view.isFolded && screen.contains(rug.window.frame))
        model.rugScale = 5
        check("boyut en fazla %160 olur", abs(rug.window.frame.width - RugView.sizeFor(scale: 1.6).width) < 1)
        model.rugScale = 1

        model.rugVisible = false
        check("halı gizlenir", !rug.isVisible && rug.frameLocal == nil)
        model.rugVisible = true
        check("halı yeniden görünür", rug.isVisible && rug.frameLocal != nil)
        after(0.3, next)
    }

    func run() {
        after(0.6) { [self] in
            model.rugScale = 1
            sizeAndVisibility { [self] in mainFlow() }
        }
        after(150) { print("HALI_ZAMAN_ASIMI"); exit(2) }
    }

    private func mainFlow() {
        do {
            snap("hali-kapali.png")

            // 1. Sürükleme
            let view = rug.view
            let start = rug.window.frame.origin
            let c = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            view.testMouse = NSPoint(x: 100, y: 100)
            send(.leftMouseDown, c)
            view.testMouse = NSPoint(x: 160, y: 70)
            send(.leftMouseDragged, c)
            send(.leftMouseUp, c)
            view.testMouse = nil
            let now = rug.window.frame.origin
            check("halı fareyle sürüklenir", abs(now.x - start.x - 60) < 1 && abs(now.y - start.y + 30) < 1)

            // 2. Köşeden katlama
            let corner = view.testPoint(cornerOffset: CGPoint(x: -10, y: -10))
            let inside = view.testPoint(cornerOffset: CGPoint(x: -300, y: -230))
            send(.leftMouseDown, corner)
            send(.leftMouseDragged, inside)
            send(.leftMouseUp, inside)
            check("halı köşesinden katlanır ve açık kalır", view.isFolded)

            // 3. Halının altına süpürme
            view.acceptDrop([tmp.appendingPathComponent("sakli.png"), tmp.appendingPathComponent("Gizli Klasor")], at: inside)
            after(1.2) { [self] in step3() }
        }
    }

    private func step3() {
        let view = rug.view
        let names = Set(model.rugStore.items.map(\.name))
        check("ekran görüntüsü ve klasör halının altına girer", names == ["sakli.png", "Gizli Klasor"])
        check("süpürülenler masaüstünde görünmez", !exists("sakli.png") && !exists("Gizli Klasor"))
        check("katlanınca altındakiler görünür", view.testCellCount >= 1)
        snap("hali-katli.png")

        // Sistem klasörleri halı altına giremez
        check("ev klasörü halı altına giremez", !model.rugStore.canSweep(fm.homeDirectoryForCurrentUser))

        // 4. Katlamayı kapatma
        let flap = view.testFlapPoint
        send(.leftMouseDown, flap)
        send(.leftMouseUp, flap)
        after(0.6) { [self] in
            check("halı örtülünce kapanır", !rug.view.isFolded)
            model.scan { [self] in after(0.4) { [self] in step5() } }
        }
    }

    private func step5() {
        check("robot halı altındakini ve örtüleni göremez", model.visibleShots.map(\.name) == ["gorunen.png"])
        model.onMissionFinished = { [self] in
            let box = Set((try? fm.contentsOfDirectory(atPath: model.collectionDir.path)) ?? [])
            check("robot yalnızca açıktaki görüntüyü toplar", box == ["gorunen.png"])
            check("halının örttüğü görüntü yerinde kalır", exists("ortulu.png"))
            check("halı altındaki görüntüye dokunulmaz", model.rugStore.items.contains { $0.name == "sakli.png" })

            // 5. Geri çıkarma
            if let item = model.rugStore.items.first(where: { $0.name == "sakli.png" }) {
                _ = try? model.rugStore.restore(item, fallback: tmp)
            }
            check("halı altından geri çıkarılır", exists("sakli.png"))
            try? fm.removeItem(at: tmp)
            print(failures == 0 ? "HALI_GECTI" : "HALI_KALDI \(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        model.cleanAllNow()
    }
}

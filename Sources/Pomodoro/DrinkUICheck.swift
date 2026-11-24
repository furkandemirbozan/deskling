import AppKit

/// Masaüstü içeceğini gerçekten açıp dener: pencere katmanı, sürükleme, çalkalanma, kontrol çubuğu ve sağ tık menüsü.
/// Konum kaydedilmez, gerçek sayaç kaydına dokunulmaz; sayaç sahte saatle ilerler.
final class DrinkUICheck {
    private let output: URL?
    private var failures = 0
    private let clock = PomodoroCheck.Clock()
    private let pomo: PomodoroManager
    private let drink: DrinkController
    private var picked: [String] = []

    init(output: URL?) {
        self.output = output
        let c = clock
        pomo = PomodoroManager(now: { c.t })
        drink = DrinkController(pomo: pomo, persist: false)
        drink.runsTimer = false
        if let output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        drink.onChooseKind = { [weak self] in self?.picked.append("tema:" + $0.rawValue) }
        drink.onChooseScale = { [weak self] in self?.picked.append("boyut:\($0)") }
        drink.onHide = { [weak self] in self?.picked.append("gizle") }
        pomo.onTransition = { [weak self] in self?.drink.transition($0) }
    }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    private func frames(_ seconds: Double, _ each: ((Int) -> Void)? = nil) {
        let n = Int(seconds * 60)
        for i in 0..<n { each?(i); drink.frame(dt: 1.0 / 60) }
    }

    private func snap(_ name: String) {
        guard let output, let img = DrinkArt.render(drink.view.state, particles: drink.view.particles, size: DrinkArt.canvas, scale: 2) else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
    }

    func run() {
        after(60) { print("ICECEK_ZAMAN_ASIMI"); exit(2) }
        let savedAnchor = UserDefaults.standard.object(forKey: "pomoAnchorX")
        drink.setVisible(true)
        after(0.3) { [self] in
            windows()
            dragAndSlosh()
            clicks()
            levels()
            menu()
            hover { [self] in
                check("test konumu kaydetmedi", UserDefaults.standard.object(forKey: "pomoAnchorX") as? Double == savedAnchor as? Double)
                drink.setVisible(false)
                check("gizlenince bütün pencereler kapanır", !drink.window.isVisible && !drink.hitPanel.isVisible && !drink.barPanel.isVisible)
                print(failures == 0 ? "ICECEK_GECTI" : "ICECEK_KALDI hata=\(failures)")
                exit(failures == 0 ? 0 : 1)
            }
        }
    }

    private func windows() {
        let v = DesktopMap.screen.visibleFrame
        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        check("içecek ve tutma alanı görünür", drink.window.isVisible && drink.hitPanel.isVisible)
        check("masaüstü simgelerinin hemen üstünde durur", drink.window.level.rawValue == desktopLevel + 1 && drink.hitPanel.level == drink.window.level)
        check("çizim penceresi tıklamaları geçirir", drink.window.ignoresMouseEvents && !drink.hitPanel.ignoresMouseEvents)
        check("tutma alanı odak çalmaz", drink.hitPanel.styleMask.contains(.nonactivatingPanel) && !drink.hitPanel.canBecomeMain)
        check("tüm masaüstlerinde görünür", drink.window.collectionBehavior.contains(.canJoinAllSpaces))
        check("varsayılan yeri sağ alt", drink.anchor.x > v.midX && drink.anchor.y < v.midY)
        check("tutma alanı bardağın gövdesiyle aynı", drink.hitPanel.frame.equalTo(drink.bodyFrame))

        let bottom = drink.bodyFrame.minY, width = drink.bodyFrame.width
        drink.scale = 1.5
        check("büyütünce bardak tabanı yerinde kalır", abs(drink.bodyFrame.minY - bottom) < 0.5 && abs(drink.bodyFrame.width - width * 1.5) < 0.5)
        check("büyütünce tutma alanı da büyür", drink.hitPanel.frame.equalTo(drink.bodyFrame))
        drink.scale = 1
        for k in DrinkKind.allCases {
            drink.kind = k
            if !drink.window.frame.contains(drink.bodyFrame) { check("\(k.title) gövdesi pencereye sığar", false) }
        }
        drink.kind = .tea
    }

    private func dragAndSlosh() {
        frames(1)
        let start = drink.anchor
        let calm = drink.view.state.slosh.energy
        drink.grab(at: start)
        drink.drag(to: NSPoint(x: start.x + 2, y: start.y))
        check("küçük titreme sürükleme sayılmaz", !drink.moved && drink.anchor == start)
        // Sağa hızlanarak sürüklenir: sıvı sola yığılır (yüzeyin sol ucu yükselir).
        var leftHigh = false
        frames(0.35) { [self] i in
            let x = start.x + CGFloat(i * i) * 0.9
            drink.drag(to: NSPoint(x: x, y: start.y))
            let s = drink.view.state.slosh
            if s.height(at: -1, halfWidth: 30) > s.height(at: 1, halfWidth: 30) + 4 { leftHigh = true }
        }
        check("sürüklenince bardak fareyi izler", drink.moved && drink.anchor.x > start.x + 100, "\(Int(drink.anchor.x - start.x)) pt")
        check("hızlanınca sıvı hareketin tersine yığılır", leftHigh)
        let stopAt = drink.anchor
        drink.drag(to: stopAt)
        frames(0.25) { [self] _ in drink.drag(to: stopAt) }   // ani duruş
        let peak = drink.view.state.slosh.energy
        check("ani duruşta sıvı çalkalanır", peak > calm * 10 + 1e-3, String(format: "%.4f", peak))
        snap("icecek-calkalanma.png")
        drink.letGo()
        frames(1)
        let mid = drink.view.state.slosh.energy
        frames(4)
        let end = drink.view.state.slosh.energy
        check("bırakınca yavaşça durulur", mid < peak && end < mid && drink.view.state.slosh.isCalm,
              String(format: "%.4f → %.4f → %.6f", peak, mid, end))
        var wild = false
        frames(0.5) { [self] i in
            drink.grab(at: drink.anchor)
            drink.drag(to: NSPoint(x: drink.anchor.x + (i % 2 == 0 ? 160 : -160), y: drink.anchor.y + (i % 3 == 0 ? 90 : -90)))
            let s = drink.view.state.slosh
            if !s.tilt.isFinite || abs(s.tilt) > s.maxTilt + 1e-9 || abs(s.wave) > s.maxWave + 1e-9 { wild = true }
        }
        drink.letGo()
        check("sert sallamada bile yüzey sınırda kalır", !wild)
        drink.resetPosition()
        frames(6)
    }

    private func clicks() {
        drink.grab(at: drink.anchor)
        drink.letGo()
        frames(0.1)
        check("tek tıkta sıvı hafifçe sıçrar", drink.view.state.slosh.energy > 1e-4)
        drink.doubleClick()
        check("çift tık sayacı başlatır", pomo.phase == .focus && pomo.running)
        drink.doubleClick()
        check("ikinci çift tık duraklatır", pomo.isPaused)
        pomo.reset()
        frames(3)
    }

    private func levels() {
        pomo.start()
        frames(0.05)
        check("odak başlayınca bardak boşalıp dolmaya başlar", drink.view.state.level < 0.2 && drink.view.state.pour > 0)
        frames(0.8)
        snap("icecek-dolum.png")
        frames(2.5)
        check("dolum birkaç saniyede biter", drink.view.state.level > 0.97 && drink.view.state.pour < 0.05,
              String(format: "%.2f", drink.view.state.level))
        clock.advance(12.5 * 60); pomo.tick(); frames(2)
        check("süre yarılanınca sıvı da yarıya iner", abs(drink.view.state.level - 0.54) < 0.03, String(format: "%.2f", drink.view.state.level))
        check("buhar süreyle incelir", drink.view.state.steam < 0.75)
        snap("icecek-yari.png")
        clock.advance(12.5 * 60 - 20); pomo.tick(); frames(6)
        check("bitime yakın buhar kesilir", drink.view.state.steam < 0.12, String(format: "%.2f", drink.view.state.steam))
        clock.advance(25); pomo.tick(); frames(0.05)
        check("süre bitince bardak titrer", drink.view.state.shake > 0.8 && pomo.phase == .shortBreak)
        frames(1.5)
        check("titreme kısa sürer", drink.view.state.shake == 0)
        frames(3)
        check("molada bardak yeniden dolar", drink.view.state.level > 0.97)
        pomo.reset()
    }

    private func menu() {
        drink.kind = .mug
        let m = drink.menu()
        let titles = m.items.map(\.title)
        check("sağ tık menüsünde dört tema", DrinkKind.allCases.allSatisfy { titles.contains($0.title) })
        check("seçili tema işaretli", m.items.first { $0.title == DrinkKind.mug.title }?.state == .on
              && m.items.filter { $0.state == .on }.count == 2)
        check("boyutlar ve gizle var", ["Küçük", "Orta", "Büyük", "Gizle"].allSatisfy(titles.contains))
        for t in ["Bira", "Büyük", "Gizle"] {
            if let i = m.items.firstIndex(where: { $0.title == t }) { m.performActionForItem(at: i) }
        }
        check("menü seçimleri ayarlara iletilir", picked == ["tema:beer", "boyut:1.35", "gizle"], "\(picked)")
        check("menüden sayaç da yönetilir", titles.contains("Odak Başlat"))
        drink.kind = .tea
    }

    private func hover(_ done: @escaping () -> Void) {
        drink.setHover(glass: true)
        after(0.4) { [self] in
            check("üzerine gelince kontrol çubuğu belirir", drink.barShown && drink.barPanel.isVisible && drink.barPanel.alphaValue > 0.9)
            check("çubuk bardağın hemen altında", drink.barPanel.frame.maxY <= drink.bodyFrame.minY
                  && abs(drink.barPanel.frame.midX - drink.bodyFrame.midX) < 1)
            check("çubuk de odak çalmaz", drink.barPanel.styleMask.contains(.nonactivatingPanel))
            snap("icecek-hover.png")
            if let output, let v = drink.barPanel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("icecek-cubuk.png"))
            }
            drink.setHover(glass: false)
            drink.setHover(bar: true)
            after(0.7) { [self] in
                check("fare çubuğa geçince çubuk kalır", drink.barShown)
                drink.setHover(bar: false)
                after(0.9) { [self] in
                    check("fare ayrılınca çubuk kaybolur", !drink.barShown && !drink.barPanel.isVisible)
                    // Ekranın dibine taşınınca çubuk bardağın üstüne geçer.
                    let v = DesktopMap.screen.visibleFrame
                    drink.grab(at: drink.anchor)
                    drink.drag(to: NSPoint(x: drink.anchor.x, y: v.minY + 8))
                    drink.letGo()
                    drink.setHover(glass: true)
                    after(0.3) { [self] in
                        check("ekranın altında çubuk bardağın üstüne geçer", drink.barPanel.frame.minY >= drink.bodyFrame.maxY)
                        drink.setHover(glass: false)
                        drink.resetPosition()
                        drink.runsTimer = true
                        drink.effects = .low
                        drink.setVisible(false); drink.setVisible(true)
                        check("düşük yoğunlukta 20 fps", abs((drink.frameInterval ?? 0) - 1.0 / 20) < 1e-6)
                        drink.effects = .high
                        check("yüksek yoğunlukta sakinken 30 fps", abs((drink.frameInterval ?? 0) - 1.0 / 30) < 1e-6)
                        drink.grab(at: drink.anchor)
                        drink.frame()
                        check("tutulunca 60 fps'e çıkar", abs((drink.frameInterval ?? 0) - 1.0 / 60) < 1e-6)
                        drink.letGo()
                        after(0.8, done)
                    }
                }
            }
        }
    }
}

/// Dört içeceğin dolu, yarım ve neredeyse boş hallerini masaüstü benzeri bir zeminde çizer; çizim süresini ölçer.
enum DrinkGallery {
    static func run(output: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cell = CGSize(width: 220, height: 300), scale: CGFloat = 2
        let levels: [(Double, Double, PomoPhase)] = [(1, 0, .idle), (0.55, 0.5, .focus), (0.12, 0.96, .focus)]
        let w = Int(cell.width * CGFloat(levels.count) * scale), h = Int(cell.height * CGFloat(DrinkKind.allCases.count) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        // Masaüstü duvar kâğıdına benzer zemin
        ctx.drawLinearGradient(DrinkArt.gradient([(0, DrinkArt.rgb(0.22, 0.3, 0.42)), (1, DrinkArt.rgb(0.52, 0.45, 0.5))]),
                               start: .zero, end: CGPoint(x: w, y: h), options: [])
        var worst = 0.0
        for (row, kind) in DrinkKind.allCases.enumerated() {
            for (col, l) in levels.enumerated() {
                var s = DrinkState()
                s.kind = kind; s.level = l.0; s.progress = l.1; s.phase = l.2
                s.steam = l.2 == .focus ? max(0, 1 - pow(l.1, 1.6)) : 0.75
                var p = DrinkParticles(seed: 3)
                for _ in 0..<300 { s.time += 1.0 / 60; p.step(dt: 1.0 / 60, state: s) }
                // Köpük izi görünsün diye bira yukarıdan aşağı içilmiş gibi ilerletilir
                if kind == .beer, l.0 < 1 {
                    var t = s
                    for k in 0...60 {
                        t.level = 1 - (1 - l.0) * Double(k) / 60; t.progress = l.1 * Double(k) / 60
                        p.step(dt: 1.0 / 60, state: t)
                    }
                }
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(col) * cell.width * scale, y: CGFloat(DrinkKind.allCases.count - 1 - row) * cell.height * scale)
                ctx.scaleBy(x: scale, y: scale)
                DrinkArt.draw(s, particles: p, in: ctx, size: cell, pixelScale: scale)
                ctx.restoreGState()
                // Çizim süresi: önbellek hazırken bir karenin maliyeti
                let start = CACurrentMediaTime()
                for _ in 0..<60 { _ = DrinkArt.render(s, particles: p, size: cell, scale: scale) }
                let ms = (CACurrentMediaTime() - start) / 60 * 1000
                let t1 = CACurrentMediaTime()
                for _ in 0..<60 { _ = DrinkArt.steamImage(p) }
                let steamMs = (CACurrentMediaTime() - t1) / 60 * 1000
                let r = DrinkArt.regions(kind).liquid
                let lctx = CGContext(data: nil, width: Int(r.width * 2), height: Int(r.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                     space: DrinkArt.space, bitmapInfo: DrinkArt.bitmapInfo)!
                lctx.scaleBy(x: 2, y: 2); lctx.translateBy(x: -r.minX, y: -r.minY)
                let t2 = CACurrentMediaTime()
                for _ in 0..<60 { lctx.clear(r); DrinkArt.dynamic(s, particles: p, in: lctx); _ = lctx.makeImage() }
                let liquidMs = (CACurrentMediaTime() - t2) / 60 * 1000
                print(String(format: "   buhar %.2f ms, sıvı bölgesi %.2f ms", steamMs, liquidMs))
                worst = max(worst, ms)
                print(String(format: "%@ seviye %.2f: %.2f ms/kare, partikül %d", kind.title, l.0, ms, p.count))
            }
        }
        icons(to: output.appendingPathComponent("simgeler.png"))
        row(to: output.appendingPathComponent("icecekler-sira.png"))
        guard let img = ctx.makeImage() else { return 1 }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("icecekler.png"))
        print(String(format: "EN_YAVAS %.2f ms", worst))
        return 0
    }
}

extension DrinkGallery {
    /// Menü çubuğu simgelerini büyütülmüş halde tek görüntüye çizer.
    static func icons(to url: URL) {
        let size = NSSize(width: 18 * 4 * 5, height: 18 * 4 * 4)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            for (r, k) in DrinkKind.allCases.enumerated() {
                for (c, f) in [1, 0.75, 0.5, 0.25, 0].enumerated() {
                    DrinkIcons.menuIcon(k, fill: f).draw(in: NSRect(x: CGFloat(c) * 72, y: CGFloat(3 - r) * 72, width: 72, height: 72))
                }
            }
            return true
        }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

extension DrinkGallery {
    /// README için dört içeceği yan yana, masaüstü benzeri zeminde çizer.
    static func row(to url: URL) {
        let cell = CGSize(width: 220, height: 250), scale: CGFloat = 2
        let w = Int(cell.width * 4 * scale), h = Int(cell.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: DrinkArt.space, bitmapInfo: DrinkArt.bitmapInfo) else { return }
        ctx.drawLinearGradient(DrinkArt.gradient([(0, DrinkArt.rgb(0.2, 0.27, 0.4)), (1, DrinkArt.rgb(0.45, 0.38, 0.48))]),
                               start: .zero, end: CGPoint(x: w, y: h), options: [])
        let looks: [(DrinkKind, Double, Double)] = [(.tea, 0.85, 0.15), (.turkishCoffee, 0.9, 0.2), (.mug, 0.75, 0.3), (.beer, 0.7, 0.35)]
        for (i, l) in looks.enumerated() {
            var s = DrinkState()
            s.kind = l.0; s.phase = .focus; s.running = true; s.level = l.1; s.progress = l.2
            s.steam = max(0, 1 - pow(l.2, 1.6))
            var p = DrinkParticles(seed: UInt64(9 + i))
            for k in 0..<360 {
                var t = s
                if l.0 == .beer { t.level = 1 - (1 - l.1) * Double(k) / 360; t.progress = l.2 * Double(k) / 360 }
                s.time += 1.0 / 60; t.time = s.time
                p.step(dt: 1.0 / 60, state: t)
            }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(i) * cell.width * scale, y: 4 * scale)
            ctx.scaleBy(x: scale, y: scale)
            DrinkArt.draw(s, particles: p, in: ctx, size: DrinkArt.canvas, pixelScale: scale)
            ctx.restoreGState()
        }
        if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url) }
    }
}

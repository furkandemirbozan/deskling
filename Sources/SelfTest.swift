import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Gerçek Masaüstü'ne hiç dokunmadan, geçici klasörde çalışan doğrulamalar.
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool) {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name)
        if !ok { failures += 1 }
    }

    static func png(_ url: URL, comment: String?) {
        let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let comment { props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: comment] }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    static func run() -> Int32 {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("robo-test-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // Algılama
        let real = dir.appendingPathComponent("gercek.png")
        png(real, comment: "Screenshot")
        png(dir.appendingPathComponent("Ekran Resmi 2026-01-01 12.00.00.png"), comment: nil)   // adı benziyor ama değil
        png(dir.appendingPathComponent("tatil.png"), comment: "Vacation")
        try? "metin".write(to: dir.appendingPathComponent("Screenshot.txt"), atomically: true, encoding: .utf8)
        let sub = dir.appendingPathComponent("altklasor")
        try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
        png(sub.appendingPathComponent("icerde.png"), comment: "Screenshot")
        try? fm.createSymbolicLink(at: dir.appendingPathComponent("baglanti.png"), withDestinationURL: real)

        let found = ScreenshotDetector.scan(dir)
        check("küçük önizleme üretilir", ScreenshotDetector.thumbnail(real) != nil)
        check("yalnızca gerçek ekran görüntüsü bulunur", found.map(\.name) == ["gercek.png"])

        // Değişen dosya korunur
        let hazne = dir.appendingPathComponent(".hazne")
        if let shot = found.first {
            let stale = Shot(url: shot.url, size: shot.size + 1, created: shot.created, modified: shot.modified, evidence: shot.evidence)
            check("taramadan sonra değişen dosyaya dokunulmaz", (try? Cleaner.collect(stale, into: hazne)) == nil && fm.fileExists(atPath: real.path))

            // Hazneye toplama ve geri alma
            if let rec = try? Cleaner.collect(shot, into: hazne) {
                check("dosya masaüstünden kalkar", !fm.fileExists(atPath: real.path))
                check("dosya toz haznesindedir", rec.trashPath.contains("/.hazne/") && fm.fileExists(atPath: rec.trashPath))
                check("dosya Çöp Sepeti'ne gitmez", !rec.trashPath.contains("/.Trash/"))
                png(real, comment: "Screenshot")
                if let second = ScreenshotDetector.scan(dir).first, let rec2 = try? Cleaner.collect(second, into: hazne) {
                    check("aynı adlı dosya üzerine yazılmaz", rec2.trashPath != rec.trashPath && fm.fileExists(atPath: rec.trashPath))
                    _ = try? fm.removeItem(atPath: rec2.trashPath)
                }
                let back = try? Cleaner.restore(rec)
                check("geri alma dosyayı yerine koyar", back?.resolvingSymlinksInPath().path == real.resolvingSymlinksInPath().path && fm.fileExists(atPath: real.path))
                check("geri alınca haznede kopya kalmaz", !fm.fileExists(atPath: rec.trashPath))
            } else {
                check("toz haznesine toplama", false)
            }
        }

        // Motor senaryosu
        var events: [String] = []
        let e = RobotEngine(base: CGPoint(x: 130, y: 84), trash: CGPoint(x: 1100, y: 90))
        e.capacity = 2
        e.onPickup = { j in events.append("al:\(j.id)"); return j.id != "bozuk" }
        e.onDump = { n in events.append("boşalt:\(n)") }
        var ended = false
        e.onMissionEnd = { ended = true }
        let pts = [("a", 900.0, 700.0), ("bozuk", 500.0, 500.0), ("b", 300.0, 650.0), ("c", 700.0, 300.0)]
        e.start(pts.map { Job(id: $0.0, point: CGPoint(x: $0.1, y: $0.2), shot: nil, thumb: nil) })
        var t = 0.0
        while !ended && t < 180 { e.tick(1.0 / 60); t += 1.0 / 60 }
        check("görev biter ve robot istasyona döner", ended && e.pos == e.basePoint && e.phase == .docked)
        check("alınamayan dosya hazneye sayılmaz", events.filter { $0.hasPrefix("boşalt") }.reduce(0) { $0 + Int($1.dropFirst(7))! } == 3)
        check("hazne kapasitesi aşılmaz", !events.contains { $0.hasPrefix("boşalt:") && Int($0.dropFirst(7))! > 2 })
        print("       olaylar: \(events.joined(separator: " → ")) (\(Int(t)) sn)")

        // Eve dön komutu
        var homeEnded = false
        let h = RobotEngine(base: CGPoint(x: 130, y: 84), trash: CGPoint(x: 1100, y: 90))
        var taken = 0
        h.onPickup = { _ in taken += 1; return true }
        h.onMissionEnd = { homeEnded = true }
        h.start((0..<5).map { Job(id: "\($0)", point: CGPoint(x: 400 + Double($0) * 120, y: 500), shot: nil, thumb: nil) })
        for _ in 0..<150 { h.tick(1.0 / 60) }
        h.goHome()
        t = 0
        while !homeEnded && t < 60 { h.tick(1.0 / 60); t += 1.0 / 60 }
        check("İstasyona dön kalan işleri iptal eder", homeEnded && taken == 0 && h.jobs.isEmpty)

        print(failures == 0 ? "\nTüm testler geçti." : "\n\(failures) test kaldı.")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Görsel kontrol

    /// Canlı sahnenin o anki halini, ekran kaydı izni istemeden PNG olarak yazar.
    static func capture(_ root: CALayer, to url: URL) {
        for l in root.sublayers ?? [] where l.animationKeys()?.isEmpty == false && l.contents != nil {
            if let p = l.presentation() {
                let s = (p.value(forKeyPath: "transform.scale") as? Double) ?? 1
                print(String(format: "ANIM %@ opaklik=%.2f olcek=%.2f konum=%.0f,%.0f", url.lastPathComponent, p.opacity, s, p.position.x, p.position.y))
            }
        }
        let w = Int(root.bounds.width), h = Int(root.bounds.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.55, blue: 0.62, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        (root.presentation() ?? root).render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        save(NSBitmapImageRep(cgImage: image), url)
    }

    private static func save(_ rep: NSBitmapImageRep, _ url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func exportIcons(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                           ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            guard let cg = RobotArt.appIcon(CGFloat(px)).cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            save(NSBitmapImageRep(cgImage: ctx.makeImage()!), dir.appendingPathComponent("icon_\(name).png"))
        }
    }

    static func snapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Robot sahnesi
        let side: CGFloat = 420
        let scene = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor(calibratedRed: 0.42, green: 0.55, blue: 0.62, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            guard let x = NSGraphicsContext.current?.cgContext else { return false }
            x.translateBy(x: side / 2, y: side / 2)
            x.scaleBy(x: 2.6, y: 2.6)
            x.rotate(by: 0.5)
            let S = RobotArt.size
            x.draw(RobotArt.shadow, in: CGRect(x: -(S + 28) / 2, y: -(S + 28) / 2, width: S + 28, height: S + 28))
            for y in [CGFloat(29), -29] {
                x.draw(RobotArt.brush, in: CGRect(x: 27 - 32, y: y - 32, width: 64, height: 64))
            }
            x.draw(RobotArt.body, in: CGRect(x: -S / 2, y: -S / 2, width: S, height: S))
            x.draw(RobotArt.lidar, in: CGRect(x: -S / 2, y: -S / 2, width: S, height: S))
            return true
        }
        if let tiff = scene.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { save(rep, dir.appendingPathComponent("robot.png")) }

        // Panel, örnek verilerle (geçici klasör)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("robo-snap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let names = ["Ekran Resmi 2026-11-18 14.02.11.png", "Ekran Resmi 2026-11-17 09.41.36.png", "Ekran Resmi 2026-11-12 22.15.03.png"]
        names.forEach { png(tmp.appendingPathComponent($0), comment: "Screenshot") }
        let model = AppModel(desktopOverride: tmp)
        model.shots = ScreenshotDetector.scan(tmp)
        model.selected = Set(model.shots.prefix(2).map(\.id))
        for (i, shot) in model.shots.enumerated() {
            let card = RobotArt.demoCard(i)
            model.thumbs[shot.id] = NSImage(cgImage: card, size: NSSize(width: card.width, height: card.height))
        }
        model.history = [CleanRecord(name: names[0], originalPath: "/x", trashPath: "/y", date: Date())]

        // Portlar sekmesi örnek verilerle çizilir; gerçek süreçler ve proje adları görüntüye girmez.
        let me = getuid()
        var sample = PortScanner.parse("p4120\ncnode\nu\(me)\nn*:3000\np4188\ncpython3.12\nu\(me)\nn127.0.0.1:8000\n" +
                                       "p3001\ncruby\nu\(me)\nn127.0.0.1:4000\np671\ncControlCenter\nu\(me)\nn*:5000\n")
        let extra: [Int32: (String, String, String)] = [
            4120: ("/usr/local/bin/node", "/usr/local/bin/node /p/node_modules/.bin/vite --port 3000", "/Projeler/magaza-web"),
            4188: ("/usr/bin/python3", "/usr/bin/python3 -m uvicorn app.main:app --reload", "/Projeler/api"),
            3001: ("/usr/bin/ruby", "/usr/bin/ruby bin/jekyll serve", "/Projeler/blog"),
            671: ("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", "", "/"),
        ]
        for i in sample.indices {
            if let e = extra[sample[i].pid] { sample[i].executable = e.0; sample[i].commandLine = e.1; sample[i].cwd = e.2 }
        }
        let ports = sample
        let containers = DockerService.parse("""
        {"ID":"a1","Names":"magaza-postgres","Image":"postgres:17","State":"running","Status":"Up 2 hours","Ports":"127.0.0.1:5432->5432/tcp","Labels":"com.docker.compose.project=magaza"}
        {"ID":"b2","Names":"magaza-redis","Image":"redis:7","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:6379->6379/tcp","Labels":"com.docker.compose.project=magaza"}
        {"ID":"c3","Names":"eski-mongo","Image":"mongo:8","State":"exited","Status":"Exited (0) 3 days ago","Ports":"","Labels":""}
        """)
        model.dev.scanPorts = { ports }
        model.dev.scanDocker = { (.ready, containers) }
        model.dev.showSystem = true

        for tab in PanelTab.allCases {
            model.panelTab = tab
            let host = NSHostingView(rootView: PanelView(model: model).background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: 460, height: 640)
            let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(tab == .ports ? 1.0 : 0.4))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                save(rep, dir.appendingPathComponent("panel-\(PanelTab.allCases.firstIndex(of: tab)!).png"))
            }
        }

        // Pano penceresi, örnek kayıtlarla
        let board = NSPasteboard(name: NSPasteboard.Name("robo-snap-\(UUID().uuidString)"))
        let store = ClipboardStore(pasteboard: board, fileURL: nil)
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        let samples: [(String, String?)] = [
            ("Toplantı notları: sunum perşembe 14.00'te, slaytları Ayşe hazırlayacak.", "com.apple.Notes"),
            ("#4F46E5", "com.apple.Safari"),
            ("https://developer.apple.com/documentation/appkit", "com.apple.Safari"),
            ("func selamla(_ ad: String) -> String {\n    return \"Merhaba, \\(ad)!\"\n}", "com.apple.dt.Xcode"),
            ("rgb(16, 185, 129)", "com.apple.Safari"),
            ("Kargo takip no: 1Z 999 AA1 01 2345 6784", "com.apple.mail"),
        ]
        for (text, bundle) in samples.reversed() {
            store.add(text: text, rtf: nil, app: nil)
            let path = bundle.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path } ?? finder?.path
            if let i = store.items.firstIndex(where: { $0.text == text }) { store.setSource(at: i, name: nil, path: path) }
        }
        store.togglePin(store.items[5])
        let clip = ClipboardPanelController(store: store)
        clip.state.selection = 1
        let view = NSHostingView(rootView: ClipboardView(store: store, state: clip.state, list: { clip.list }, choose: { _, _ in }, close: {})
            .background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(origin: .zero, size: ClipboardPanelController.size)
        let w = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            save(rep, dir.appendingPathComponent("pano.png"))
        }
        board.releaseGlobally()
    }
}

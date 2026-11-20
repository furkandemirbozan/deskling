import AppKit

/// Kara delik penceresini gerçekten açıp geçici dosyalarla dener. Çöp Sepeti ve konum ayarı kullanılmaz.
final class HoleUICheck {
    private let fm = FileManager.default
    private let output: URL?
    private let dir: URL
    private var failures = 0
    private let hole = BlackHoleController(persist: false)
    private var trashed: [URL] = []

    init(output: URL?) {
        self.output = output
        dir = fm.temporaryDirectory.appendingPathComponent("robo-hole-ui-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir.appendingPathComponent("Klasor"), withIntermediateDirectories: true)
        try? String(repeating: "kara delik ", count: 3000).write(to: dir.appendingPathComponent("Klasor/a.txt"), atomically: true, encoding: .utf8)
        SelfTest.png(dir.appendingPathComponent("resim.png"), comment: nil)
        if let output { try? fm.createDirectory(at: output, withIntermediateDirectories: true) }
        hole.trash = { [weak self] in self?.trashed.append($0) }
    }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    private func snap(_ name: String) {
        guard let output, let layer = hole.window.contentView?.layer else { return }
        SelfTest.capture(layer, to: output.appendingPathComponent(name))
    }

    func run() {
        after(120) { print("KARADELIK_ARAYUZ_ZAMAN_ASIMI"); exit(2) }
        hole.setVisible(true)
        after(0.4) { [self] in
            let v = DesktopMap.screen.visibleFrame
            check("kara delik açılır", hole.window.isVisible && hole.hitPanel.isVisible)
            check("varsayılan yeri sol üst köşe", hole.center.x < v.minX + 260 && hole.center.y > v.maxY - 220)
            check("bırakma alanı deliğin tam ortasında",
                  abs(hole.hitPanel.frame.midX - hole.window.frame.midX) < 0.5 && abs(hole.hitPanel.frame.midY - hole.window.frame.midY) < 0.5)
            check("görüntü penceresi tıklamaları alttakine geçirir", hole.window.ignoresMouseEvents)
            hole.setVisible(false)
            check("kara delik gizlenir", !hole.window.isVisible && !hole.hitPanel.isVisible)
            hole.setVisible(true)
            check("kara delik yeniden görünür", hole.window.isVisible)
            dropFolder()
        }
    }

    private func dropFolder() {
        let folder = dir.appendingPathComponent("Klasor")
        let point = NSPoint(x: BlackHoleController.size.width / 2 + 120, y: BlackHoleController.size.height / 2 + 70)
        hole.receive([folder], mode: .normal, at: point)
        check("bırakılınca kara delik işlemeye başlar", hole.busy)
        after(0.45) { [self] in
            let icons = hole.fx.sublayers?.filter { $0.animation(forKey: "fx") != nil }.count ?? 0
            check("dosya simgesi içine çekilir", icons >= 1)
            snap("delik-arayuz-1-cekme.png")
        }
        after(1.9) { [self] in
            let r = hole.lastResult
            check("işlem biter ve kara delik serbest kalır", !hole.busy && r?.ok == true, r?.title ?? "sonuç yok")
            check("ZIP orijinalin yanına kaydedilir", fm.fileExists(atPath: dir.appendingPathComponent("Klasor.zip").path))
            check("orijinal klasör yerinde kalır", fm.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
            check("sonuç etiketi kara deliğin üstünde görünür", hole.label != nil && (hole.label?.position.y ?? 0) > BlackHoleController.size.height / 2)
            snap("delik-arayuz-2-sonuc.png")
            dropUnsupported()
        }
    }

    private func dropUnsupported() {
        let png = dir.appendingPathComponent("resim.png")
        hole.receive([png], mode: .normal, at: NSPoint(x: 330, y: 200))
        after(1.6) { [self] in
            check("işlenemeyen dosya geri tükürülür ve yerinde kalır", hole.lastResult?.consumed == false && fm.fileExists(atPath: png.path))
            snap("delik-arayuz-3-geri.png")
            dropRed()
        }
    }

    private func dropRed() {
        let png = dir.appendingPathComponent("resim.png")
        hole.receive([png], mode: .red, at: NSPoint(x: 100, y: 120))
        after(1.6) { [self] in
            check("kırmızı modda dosya Çöp Sepeti'ne gönderilir", trashed == [png] && hole.lastResult?.ok == true)
            dropVideo()
        }
    }

    /// Uzun süren video işinde kara deliğin üstünde yüzde görünür.
    private func dropVideo() {
        let movie = dir.appendingPathComponent("uzun kayit.mov")
        try? HoleVideoCheck.makeVideo(movie, w: 1920, h: 1080, seconds: 12, fps: 30, bitrate: 30_000_000)
        var settings = HoleSettings(); settings.quality = .high
        hole.settings = settings
        hole.receive([movie], mode: .normal, at: NSPoint(x: 330, y: 200))
        var sawProgress = false
        func poll() {
            if hole.progressBox != nil { sawProgress = true }
            if hole.busy { after(0.1, poll); return }
            check("uzun video işlenirken ilerleme yüzdesi görünür", sawProgress)
            check("video işi bitince ilerleme kalkar ve sonuç görünür", hole.progressBox == nil && hole.lastResult?.ok == true, hole.lastResult?.detail ?? "")
            finishAll()
        }
        after(1.4) { [self] in
            if hole.progressBox != nil { snap("delik-arayuz-4-ilerleme.png") }
            poll()
        }
    }

    private func finishAll() {
        after(0.1) { [self] in
            try? fm.removeItem(at: dir)
            print(failures == 0 ? "KARADELIK_ARAYUZ_GECTI" : "KARADELIK_ARAYUZ_KALDI \(failures)")
            exit(failures == 0 ? 0 : 1)
        }
    }
}

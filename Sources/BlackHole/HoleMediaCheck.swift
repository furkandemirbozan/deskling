import AppKit
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Görsel ve PDF işlemlerini geçici klasörde, gerçek dosyalarla dener.
enum HoleMediaCheck {
    static var failures = 0
    private static let fm = FileManager.default

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    /// Fotoğrafa benzeyen, yumuşak geçişli ve hafif gürültülü bir görüntü.
    static func photo(_ w: Int, _ h: Int, alphaBorder: Int = 0) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var seed: UInt32 = 7
        for y in 0..<h {
            for x in 0..<w {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let n = Int(seed % 23) - 11
                let i = (y * w + x) * 4
                let edge = alphaBorder > 0 && (x < alphaBorder || y < alphaBorder || x >= w - alphaBorder || y >= h - alphaBorder)
                let a = edge ? 0 : 255
                let r = min(255, max(0, x * 255 / w + n)), g = min(255, max(0, y * 255 / h + n)), b = min(255, max(0, 140 + Int(60 * sin(Double(x + y) / 90)) + n))
                p[i] = UInt8(r * a / 255); p[i + 1] = UInt8(g * a / 255); p[i + 2] = UInt8(b * a / 255); p[i + 3] = UInt8(a)
            }
        }
        return ctx.makeImage()!
    }

    static func save(_ img: CGImage, _ url: URL, _ type: UTType, _ props: [CFString: Any] = [:]) {
        let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        CGImageDestinationFinalize(d)
    }

    private static func props(_ u: URL) -> [CFString: Any] {
        guard let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return [:] }
        return (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]) ?? [:]
    }

    private static func type(_ u: URL) -> String {
        guard let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return "" }
        return (CGImageSourceGetType(s) as String?) ?? ""
    }

    static func makePDF(_ url: URL, pages: [String], image: CGImage? = nil, password: String? = nil) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        var info: [CFString: Any] = [:]
        if let password { info[kCGPDFContextUserPassword] = password; info[kCGPDFContextOwnerPassword] = password + "x" }
        let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary)!
        for text in pages {
            ctx.beginPDFPage(nil)
            if let image { ctx.draw(image, in: CGRect(x: 40, y: 200, width: 515, height: 515)) }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 24)]))
            ctx.textPosition = CGPoint(x: 60, y: 760)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    static func run(in dir: URL) {
        var trashed: [URL] = []
        let fakeTrash: (URL) throws -> Void = { trashed.append($0) }
        func go(_ urls: [URL], _ mode: HoleMode = .normal, _ s: HoleSettings = HoleSettings()) -> HoleResult {
            HoleProcessor.process(urls, mode: mode, trashOriginal: false, settings: s, trash: fakeTrash)
        }
        func sized(_ u: URL) -> (Int, Int) {
            let p = props(u)
            return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0)
        }

        // Fotoğraf: 3000x2000, yan çekilmiş (yönlendirme 6), konum bilgili, en yüksek kalitede JPG
        let big = photo(3000, 2000)
        let foto = dir.appendingPathComponent("foto.jpg")
        save(big, foto, .jpeg, [kCGImageDestinationLossyCompressionQuality: 1.0, kCGImagePropertyOrientation: 6,
                                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0, kCGImagePropertyGPSLatitudeRef: "N",
                                                                kCGImagePropertyGPSLongitude: 29.0, kCGImagePropertyGPSLongitudeRef: "E"],
                                kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Deneme Lens"]])
        let ekran = dir.appendingPathComponent("ekran.png")
        save(photo(2400, 1600, alphaBorder: 40), ekran, .png)
        let heic = dir.appendingPathComponent("telefon.heic")
        save(photo(1600, 1200), heic, .heic, [kCGImageDestinationLossyCompressionQuality: 0.9])
        let kucuk = dir.appendingPathComponent("ikon.png")
        SelfTest.png(kucuk, comment: nil)
        let docA = dir.appendingPathComponent("A.pdf"), docB = dir.appendingPathComponent("B.pdf")
        makePDF(docA, pages: ["Belge A sayfa 1", "Belge A sayfa 2"])
        makePDF(docB, pages: ["Belge B sayfa 1", "Belge B sayfa 2", "Belge B sayfa 3"])
        let heavy = dir.appendingPathComponent("katalog.pdf")
        makePDF(heavy, pages: ["Katalog 1", "Katalog 2"], image: photo(1600, 1600))
        let locked = dir.appendingPathComponent("gizli.pdf")
        makePDF(locked, pages: ["Gizli"], password: "1234")
        let video = dir.appendingPathComponent("kayit.mov")
        try? Data(repeating: 0, count: 1000).write(to: video)
        let originals = [foto, ekran, heic, kucuk, docA, docB, heavy, locked]
        let sums = originals.map { (try? Data(contentsOf: $0)) ?? Data() }

        // Görseller
        let r1 = go([foto])
        let out1 = r1.outputs.first
        let p1 = out1.map(props) ?? [:]
        check("fotoğraf sıkıştırılır", r1.ok && out1?.lastPathComponent == "foto_compressed.jpg" && HoleProcessor.size(of: out1!) < HoleProcessor.size(of: foto), r1.detail ?? r1.title)
        check("fotoğrafın konum bilgisi silinir", p1[kCGImagePropertyGPSDictionary] == nil && r1.detail?.contains("konum silindi") == true)
        check("diğer fotoğraf bilgileri korunur", ((p1[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String) == "Deneme Lens")
        let (w1, h1) = out1.map(sized) ?? (0, 0)
        check("yan çekilmiş fotoğraf düz kaydedilir", w1 == 2000 && h1 == 3000 && ((p1[kCGImagePropertyOrientation] as? Int) ?? 1) == 1, "\(w1)x\(h1)")

        var keep = HoleSettings(); keep.stripLocation = false
        let rk = go([foto], .normal, keep)
        check("istenirse konum bilgisi korunur", rk.outputs.first.map { props($0)[kCGImagePropertyGPSDictionary] != nil } ?? false)

        var sizes: [Int64] = []
        for q in HoleSettings.Quality.allCases {
            var s = HoleSettings(); s.quality = q
            sizes.append(go([foto], .normal, s).outputs.first.map(HoleProcessor.size) ?? 0)
        }
        check("düşük kalite en küçük, yüksek kalite en büyük dosyayı verir", sizes[0] > 0 && sizes[0] < sizes[1] && sizes[1] < sizes[2],
              sizes.map(HoleProcessor.bytes).joined(separator: " < "))
        var low = HoleSettings(); low.quality = .low
        let lowOut = go([foto], .normal, low).outputs.first
        check("düşük kalitede uzun kenar 2048 piksele iner", lowOut.map { max(sized($0).0, sized($0).1) } == 2048)

        let r2 = go([ekran])
        let px = r2.outputs.first.flatMap { u -> UInt8? in
            guard let s = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(s, 0, nil),
                  let data = img.dataProvider?.data, let b = CFDataGetBytePtr(data) else { return nil }
            return b[0]
        }
        check("saydam ekran görüntüsü JPG olunca kenarları beyaz olur", r2.ok && (px ?? 0) > 240, "köşe \(px ?? 0)")

        let r3 = go([heic])
        check("HEIC fotoğraf JPG'ye dönüşür", r3.ok && r3.title == "HEIC → JPG" && r3.outputs.first?.lastPathComponent == "telefon_converted.jpg"
              && r3.outputs.first.map(type) == UTType.jpeg.identifier, r3.title)
        var toHeic = HoleSettings(); toHeic.format = .heic
        let r4 = go([foto], .normal, toHeic)
        check("istenirse çıktı HEIC olur", r4.ok && r4.outputs.first.map(type) == UTType.heic.identifier, r4.title)
        var toWebP = HoleSettings(); toWebP.format = .webp
        if HoleTools.cwebp == nil {
            let r5 = go([foto], .normal, toWebP)
            check("cwebp yoksa WebP için nazik uyarı verilir", !r5.ok && !r5.consumed && r5.title.contains("cwebp"))
        } else {
            let r5 = go([foto], .normal, toWebP)
            check("WebP çıktısı oluşur", r5.ok && r5.outputs.first?.pathExtension == "webp")
        }
        let r6 = go([kucuk])
        check("zaten küçük görsel geri fırlatılır, çıktı bırakılmaz", !r6.consumed && !fm.fileExists(atPath: dir.appendingPathComponent("ikon_compressed.jpg").path), r6.title)
        let r7 = go([foto, ekran])
        check("birden çok görsel tek tek küçülür", r7.ok && r7.outputs.count == 2 && r7.title == "2 görsel küçüldü", r7.title)

        // PDF
        let m = go([docA, docB])
        let merged = m.outputs.first.flatMap { PDFDocument(url: $0) }
        check("iki PDF tek dosyada birleşir", m.ok && merged?.pageCount == 5 && m.outputs.first?.lastPathComponent == "A_merged.pdf", m.detail ?? "")
        check("birleşen PDF'te sayfa sırası korunur",
              merged?.page(at: 0)?.string?.contains("Belge A sayfa 1") == true && merged?.page(at: 4)?.string?.contains("Belge B sayfa 3") == true)
        let c = go([heavy])
        let cd = c.outputs.first.flatMap { PDFDocument(url: $0) }
        check("görsel ağırlıklı PDF sıkışır", c.ok && cd?.pageCount == 2, c.detail ?? c.title)
        let t = go([docA])
        check("zaten küçük PDF geri fırlatılır", !t.consumed && !fm.fileExists(atPath: dir.appendingPathComponent("A_compressed.pdf").path), t.title)
        let sp = go([docB], .white)
        let pages = sp.outputs.first.flatMap { try? fm.contentsOfDirectory(atPath: $0.path) }?.sorted() ?? []
        check("beyaz delik PDF'i sayfalara ayırır", sp.ok && pages == ["B_1.pdf", "B_2.pdf", "B_3.pdf"], pages.joined(separator: ","))
        let ip = go([foto, heic], .white)
        check("beyaz delik görselleri tek PDF yapar", ip.ok && ip.outputs.first.flatMap { PDFDocument(url: $0) }?.pageCount == 2, ip.title)
        let lk = go([locked])
        check("şifreli PDF nazikçe geri fırlatılır", !lk.ok && !lk.consumed && lk.detail == "Şifreli PDF işlenemez", lk.detail ?? "")

        let v = go([video])
        check("bozuk video nazikçe geri fırlatılır", !v.ok && !v.consumed, v.detail ?? v.title)
        check("görsel ve PDF işlemlerinde orijinaller değişmez", originals.map { (try? Data(contentsOf: $0)) ?? Data() } == sums && trashed.isEmpty)
    }
}

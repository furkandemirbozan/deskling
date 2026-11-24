import AppKit
import CryptoKit
import Metal

/// Kara deliğin işlemlerini geçici klasörde, görünüşünü ekran dışında dener.
/// Gerçek Çöp Sepeti'ne ve gerçek masaüstüne dokunmaz.
enum HoleCheck {
    private static var failures = 0
    private static let fm = FileManager.default

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private static func digest(_ u: URL) -> String {
        guard let d = try? Data(contentsOf: u) else { return "" }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    private static func listZip(_ u: URL) -> [String] {
        ((try? HoleProcessor.run("/usr/bin/zipinfo", ["-1", u.path])) ?? "")
            .split(separator: "\n").map(String.init)
    }

    static func run(output: URL?) -> Int32 {
        let dir = fm.temporaryDirectory.appendingPathComponent("robo-hole-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        var trashed: [URL] = []
        let fakeTrash: (URL) throws -> Void = { trashed.append($0) }   // gerçek Çöp Sepeti'ne gitmez
        func process(_ urls: [URL], _ mode: HoleMode? = nil, trashOriginal: Bool = false) -> HoleResult {
            HoleProcessor.process(urls, mode: mode ?? HoleProcessor.mode(for: urls, shift: false, option: false),
                                  trashOriginal: trashOriginal, trash: fakeTrash)
        }

        // Örnek dosyalar
        let folder = dir.appendingPathComponent("Proje")
        try? fm.createDirectory(at: folder.appendingPathComponent("alt"), withIntermediateDirectories: true)
        let filler = String(repeating: "Deskling kara delik deneme satırı. ", count: 4000)
        try? filler.write(to: folder.appendingPathComponent("not.txt"), atomically: true, encoding: .utf8)
        try? "iç".write(to: folder.appendingPathComponent("alt/ic.txt"), atomically: true, encoding: .utf8)
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try? filler.write(to: a, atomically: true, encoding: .utf8)
        try? "b".write(to: b, atomically: true, encoding: .utf8)
        let json = dir.appendingPathComponent("veri.json")
        try? #"{"zeta":1,"alfa":{"liste":[1,2,{"x":"a b, c"}],"bos":{},"dizi":[]},"metin":"tırnak \"içinde\" ğüşİ","ok":true}"#
            .write(to: json, atomically: true, encoding: .utf8)
        let csv = dir.appendingPathComponent("liste.csv")
        try? "\u{FEFF}Ad;Şehir;Not;\r\nAyşe;İzmir;\"çok; güzel\"\r\n\"Mehmet \"\"Memo\"\"\";Muğla;\"iki\nsatır\"\r\n"
            .write(to: csv, atomically: true, encoding: .utf8)
        let png = dir.appendingPathComponent("resim.png")
        SelfTest.png(png, comment: nil)
        let originals = [a, b, json, csv, png, folder.appendingPathComponent("not.txt")]
        let before = Dictionary(uniqueKeysWithValues: originals.map { ($0.path, digest($0)) })

        // 1. Renk modları
        check("Option ile bırakılınca kırmızı mod", HoleProcessor.mode(for: [a], shift: false, option: true) == .red)
        check("Shift ile bırakılınca beyaz delik", HoleProcessor.mode(for: [a], shift: true, option: false) == .white)
        check("yalnızca arşiv bırakılınca kendiliğinden beyaz delik", HoleProcessor.mode(for: [dir.appendingPathComponent("x.zip")], shift: false, option: false) == .white)
        check("normal bırakma mor mod", HoleProcessor.mode(for: [a, b], shift: false, option: false) == .normal)

        // 2. Klasör ZIP olur
        let z1 = process([folder])
        let zipURL = z1.outputs.first
        check("klasör ZIP olur", z1.ok && zipURL?.lastPathComponent == "Proje.zip" && fm.fileExists(atPath: zipURL?.path ?? ""), z1.title + " " + (z1.detail ?? ""))
        let entries = zipURL.map(listZip) ?? []
        check("ZIP içinde klasörün dosyaları vardır", entries.contains("Proje/not.txt") && entries.contains("Proje/alt/ic.txt"), entries.joined(separator: ","))
        check("ZIP içinde __MACOSX artığı olmaz", !entries.contains { $0.hasPrefix("__MACOSX") })
        check("sıkıştırma kazancı yazılır", z1.detail?.contains("−%") == true, z1.detail ?? "")
        let z2 = process([folder])
        check("ikinci ZIP öncekinin üzerine yazmaz", z2.outputs.first?.lastPathComponent == "Proje 2.zip" && fm.fileExists(atPath: zipURL?.path ?? ""))

        // 3. Birden çok dosya tek ZIP olur
        let z3 = process([a, b])
        check("birden çok dosya tek ZIP olur", z3.ok && Set(z3.outputs.first.map(listZip) ?? []) == ["a.txt", "b.txt"])

        // 4. Arşiv açma
        if let zipURL {
            let x = process([zipURL])
            let out = x.outputs.first
            check("ZIP bırakılınca yanındaki klasöre açılır", x.ok && fm.fileExists(atPath: out?.appendingPathComponent("Proje/alt/ic.txt").path ?? ""), out?.lastPathComponent ?? "")
            check("açılan arşivin kendisi yerinde kalır", fm.fileExists(atPath: zipURL.path))
        }
        let tarDir = dir.appendingPathComponent("tarkaynak")
        try? fm.createDirectory(at: tarDir, withIntermediateDirectories: true)
        try? "tar".write(to: tarDir.appendingPathComponent("t.txt"), atomically: true, encoding: .utf8)
        let tgz = dir.appendingPathComponent("yedek.tar.gz")
        _ = try? HoleProcessor.run("/usr/bin/tar", ["-czf", tgz.path, "-C", tarDir.path, "t.txt"])
        let xt = process([tgz])
        check("TAR.GZ açılır", xt.ok && xt.outputs.first?.lastPathComponent == "yedek" && fm.fileExists(atPath: xt.outputs.first?.appendingPathComponent("t.txt").path ?? ""))
        let notArchive = process([a], .white)
        check("beyaz delik arşiv olmayan dosyayı geri fırlatır", !notArchive.ok && !notArchive.consumed)

        // 5. JSON
        let j1 = process([json])
        let pretty = j1.outputs.first.flatMap { try? String(contentsOf: $0) } ?? ""
        let same: (String, String) -> Bool = { x, y in
            guard let p = try? JSONSerialization.jsonObject(with: Data(x.utf8)) as? NSDictionary,
                  let q = try? JSONSerialization.jsonObject(with: Data(y.utf8)) as? NSDictionary else { return false }
            return p.isEqual(q)
        }
        let original = (try? String(contentsOf: json)) ?? ""
        check("tek satırlık JSON okunur hale gelir", j1.ok && j1.outputs.first?.lastPathComponent == "veri_formatted.json" && pretty.contains("\n  \"alfa\": {"), j1.title)
        check("düzenlenen JSON aynı veriyi taşır", same(pretty, original))
        let zeta = pretty.range(of: "zeta")?.lowerBound, alfa = pretty.range(of: "alfa")?.lowerBound
        check("JSON anahtar sırası korunur", zeta != nil && alfa != nil && zeta! < alfa!)
        check("metinlerin içi ve boş nesneler bozulmaz", pretty.contains("\"a b, c\"") && pretty.contains("\"bos\": {}") && pretty.contains("ğüşİ"))
        if let p = j1.outputs.first {
            let j2 = process([p])
            let mini = j2.outputs.first.flatMap { try? String(contentsOf: $0) } ?? ""
            check("girintili JSON tek satıra küçülür", j2.ok && j2.title == "JSON küçültüldü" && !mini.contains("\n") && same(mini, original))
        }
        let bad = dir.appendingPathComponent("bozuk.json")
        try? "{\"a\": 1,,}".write(to: bad, atomically: true, encoding: .utf8)
        let jb = process([bad])
        check("bozuk JSON için çıktı oluşmaz, dosya geri fırlatılır", !jb.ok && !jb.consumed && !fm.fileExists(atPath: dir.appendingPathComponent("bozuk_formatted.json").path))

        // 6. CSV → JSON
        let c1 = process([csv])
        let rows = c1.outputs.first.flatMap { try? JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [[String: String]] } ?? []
        let text = c1.outputs.first.flatMap { try? String(contentsOf: $0) } ?? ""
        check("CSV JSON'a dönüşür", c1.ok && c1.outputs.first?.lastPathComponent == "liste_converted.json" && rows.count == 2, c1.detail ?? "")
        check("noktalı virgül ayracı ve Türkçe harfler doğru okunur", rows.first?["Şehir"] == "İzmir" && rows.first?["Not"] == "çok; güzel")
        check("tırnak içindeki tırnak ve satır sonu korunur", rows.last?["Ad"] == "Mehmet \"Memo\"" && rows.last?["Not"] == "iki\nsatır")
        check("boş başlık adlandırılır, sütun sırası korunur", rows.first?["sutun_4"] != nil && (text.range(of: "\"Ad\"")!.lowerBound < text.range(of: "\"Şehir\"")!.lowerBound))
        let legacy = dir.appendingPathComponent("eski.csv")
        try? "İl,İlçe\nİstanbul,Şişli\n".data(using: .windowsCP1254)?.write(to: legacy)
        let c2 = process([legacy])
        let legacyRows = c2.outputs.first.flatMap { try? JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [[String: String]] } ?? []
        check("Windows Türkçe kodlamalı CSV doğru okunur", legacyRows.first?["İlçe"] == "Şişli")

        // 7. Desteklenmeyen tür ve kırmızı mod
        let u = process([png])
        check("henüz desteklenmeyen dosya geri fırlatılır", !u.ok && !u.consumed && fm.fileExists(atPath: png.path))
        trashed = []
        let red = process([a, b], .red)
        check("kırmızı modda dosyalar Çöp Sepeti'ne gider", red.ok && trashed == [a, b], red.title)
        trashed = []
        let t1 = process([folder], trashOriginal: true)
        check("istenirse orijinal işlemden sonra Çöp Sepeti'ne gider", t1.ok && trashed == [folder])
        trashed = []
        _ = process([bad], trashOriginal: true)
        check("işlem başarısızsa orijinale dokunulmaz", trashed.isEmpty)

        // 8. Orijinaller değişmez
        let after = Dictionary(uniqueKeysWithValues: originals.map { ($0.path, digest($0)) })
        check("kırmızı mod dışında hiçbir orijinal dosya değişmez", before == after)

        // 9. Görsel ve PDF
        HoleMediaCheck.run(in: dir)
        failures += HoleMediaCheck.failures
        HoleVideoCheck.run(in: dir)
        failures += HoleVideoCheck.failures

        // 9. Görünüm
        renderLooks(output)
        print(failures == 0 ? "KARADELIK_GECTI" : "KARADELIK_KALDI \(failures)")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Görünüm

    private static func renderLooks(_ output: URL?) {
        guard let r = HoleRenderer() else { check("Metal çizici kurulur", false); return }
        check("Metal çizici kurulur", true)
        let scale: Float = 2, w = 440, h = 300
        var look = HoleLook()
        look.size = SIMD2(Float(w) * scale, Float(h) * scale)
        look.center = look.size / 2
        look.rs = 36 * scale
        look.time = 3.7
        let states: [(String, (inout HoleLook) -> Void)] = [
            ("0-bosta", { _ in }),
            ("1-cekim", { $0.pull = 1; $0.tintAmount = 0.85; $0.cursorOn = 1; $0.cursor = SIMD2(800, 140); $0.spin = 3 }),
            ("2-beyaz", { $0.pull = 1; $0.tint = SIMD3(0.9, 0.96, 1); $0.tintAmount = 0.9; $0.spin = 3 }),
            ("3-kirmizi", { $0.pull = 1; $0.tint = SIMD3(1, 0.22, 0.2); $0.tintAmount = 0.9; $0.spin = 3 }),
            ("4-isleme", { $0.pulse = 1; $0.tintAmount = 0.85; $0.spin = 2.5; $0.time = 3.75 }),
            ("5-firlatma", { $0.burst = 0.35; $0.tintAmount = 0.5 }),
        ]
        var lit = 0
        for (name, change) in states {
            var l = look
            change(&l)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w * 2, height: h * 2, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            guard let tex = r.device.makeTexture(descriptor: d) else { continue }
            r.draw(l, to: tex, drawable: nil, wait: true)
            var bytes = [UInt8](repeating: 0, count: w * h * 16)
            tex.getBytes(&bytes, bytesPerRow: w * 8, from: MTLRegionMake2D(0, 0, w * 2, h * 2), mipmapLevel: 0)
            // Merkez kapkara, halka parlak olmalı
            let centerAlpha = bytes[((h) * w * 2 + w) * 4 + 3], centerRed = bytes[((h) * w * 2 + w) * 4 + 2]
            if name == "0-bosta" {
                check("olay ufku tam karanlıktır", centerAlpha > 240 && centerRed < 10)
                let ringRow = h - Int(36 * scale * 1.03)
                let ringPixel = bytes[(ringRow * w * 2 + w) * 4 + 2]
                check("foton halkası parlaktır", ringPixel > 200, "\(ringPixel)")
            }
            lit += bytes.enumerated().filter { $0.offset % 4 == 3 && $0.element > 30 }.count > 1000 ? 1 : 0
            guard let output else { continue }
            try? fm.createDirectory(at: output, withIntermediateDirectories: true)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let ctx = CGContext(data: &bytes, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: w * 8, space: space, bitmapInfo: info),
                  let img = ctx.makeImage(),
                  let bg = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { continue }
            let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.09, green: 0.10, blue: 0.16, alpha: 1),
                                                            CGColor(srgbRed: 0.22, green: 0.28, blue: 0.42, alpha: 1)] as CFArray, locations: [0, 1])!
            bg.drawLinearGradient(g, start: CGPoint(x: 0, y: h * 2), end: .zero, options: [])
            bg.draw(img, in: CGRect(x: 0, y: 0, width: w * 2, height: h * 2))
            if let out = bg.makeImage() {
                try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("kara-delik-\(name).png"))
            }
        }
        check("bütün durumlar çizilir", lit == states.count)
    }
}

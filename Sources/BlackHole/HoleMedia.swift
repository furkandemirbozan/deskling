import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Kara deliğin görsel ayarları (sağ tık menüsünden ve Ayarlar'dan değişir).
struct HoleSettings: Equatable {
    enum Format: String, CaseIterable {
        case jpg, heic, webp
        var title: String { self == .jpg ? "JPG" : self == .heic ? "HEIC" : "WebP" }
        var ext: String { self == .jpg ? "jpg" : rawValue }
    }
    enum Quality: String, CaseIterable {
        case low, medium, high
        var title: String { self == .low ? "Düşük" : self == .medium ? "Orta" : "Yüksek" }
        var compression: CGFloat { self == .low ? 0.55 : self == .medium ? 0.72 : 0.85 }
        /// Uzun kenar sınırı; yüksek kalitede boyut küçültülmez.
        var maxSide: Int? { self == .low ? 2048 : self == .medium ? 3840 : nil }
    }

    var format: Format = .jpg
    var quality: Quality = .medium
    var stripLocation = true
}

/// İsteğe bağlı dış araçlar. Hiçbiri zorunlu değildir.
enum HoleTools {
    static func find(_ name: String) -> URL? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let u = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        return nil
    }
    static var cwebp: URL? { find("cwebp") }
}

extension HoleProcessor {
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "webp", "bmp"]
    static let videoExts: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi"]

    static func isImage(_ u: URL) -> Bool { imageExts.contains(u.pathExtension.lowercased()) && !isDirectory(u) }
    static func isPDF(_ u: URL) -> Bool { u.pathExtension.lowercased() == "pdf" && !isDirectory(u) }
    static func isVideo(_ u: URL) -> Bool { videoExts.contains(u.pathExtension.lowercased()) && !isDirectory(u) }

    // MARK: - Görseller

    private struct ImageOutcome {
        let output: URL?
        let before: Int64
        let after: Int64
        let removedLocation: Bool
    }

    /// Görselleri ayara göre sıkıştırır ya da dönüştürür. Yeni dosya daha büyük olursa tutulmaz.
    static func images(_ urls: [URL], settings s: HoleSettings) throws -> HoleResult {
        if s.format == .webp, HoleTools.cwebp == nil {
            return HoleResult(ok: false, title: "WebP için cwebp gerekli",
                              detail: "Terminalde: brew install webp · ya da biçimi JPG yap", consumed: false)
        }
        var outcomes: [ImageOutcome] = []
        for u in urls { outcomes.append(try image(u, settings: s)) }
        let kept = outcomes.filter { $0.output != nil }
        guard !kept.isEmpty else {
            return HoleResult(ok: false, title: urls.count == 1 ? "Bu görsel zaten küçük" : "Bu görseller zaten küçük",
                              detail: "Daha düşük kalite seçebilirsin", consumed: false)
        }
        let before = kept.reduce(Int64(0)) { $0 + $1.before }, after = kept.reduce(Int64(0)) { $0 + $1.after }
        let first = urls[0].pathExtension.lowercased()
        let title: String
        if urls.count == 1 {
            title = ["heic", "heif", "webp"].contains(first) || first != s.format.ext && !(first == "jpeg" && s.format == .jpg)
                ? "\(first.uppercased()) → \(s.format.title)" : "Görsel sıkıştırıldı"
        } else {
            title = kept.count == urls.count ? "\(kept.count) görsel küçüldü" : "\(kept.count)/\(urls.count) görsel küçüldü"
        }
        var detail = saving(before, after)
        if kept.contains(where: \.removedLocation) { detail += " · konum silindi" }
        return HoleResult(ok: true, title: title, detail: detail, outputs: kept.compactMap(\.output), consumed: true)
    }

    private static func image(_ u: URL, settings s: HoleSettings) throws -> ImageOutcome {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw HoleError.unreadable
        }
        var side = max(w, h)
        if let limit = s.quality.maxSide { side = min(side, limit) }
        // Yönlendirme uygulanır, böylece çıktıda yan dönmüş fotoğraf olmaz.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard var img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw HoleError.unreadable }
        if s.format == .jpg, let flat = flatten(img) { img = flat }   // JPG saydamlık taşımaz: beyaz zemine oturur

        var meta: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] {
            if let v = props[key] { meta[key] = v }
        }
        let hadLocation = meta[kCGImagePropertyGPSDictionary] != nil
        if s.stripLocation { meta[kCGImagePropertyGPSDictionary] = nil }
        if var tiff = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        meta[kCGImagePropertyOrientation] = 1
        meta[kCGImageDestinationLossyCompressionQuality] = s.quality.compression

        let srcExt = u.pathExtension.lowercased()
        let compatibility = ["heic", "heif", "webp"].contains(srcExt)   // amaç uyumluluk: büyüse de tutulur
        let base = u.deletingPathExtension().lastPathComponent + (compatibility ? "_converted" : "_compressed")
        let out = freeURL(in: u.deletingLastPathComponent(), base: base, ext: s.format.ext)

        if s.format == .webp, let cwebp = HoleTools.cwebp {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("robo-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try write(img, meta: [:], to: tmp, type: .png)
            try run(cwebp.path, ["-quiet", "-q", String(Int(s.quality.compression * 100)), tmp.path, "-o", out.path])
        } else {
            try write(img, meta: meta, to: out, type: s.format == .heic ? .heic : .jpeg)
        }
        let before = size(of: u), after = size(of: out)
        if !compatibility, after >= Int64(Double(before) * 0.95) {
            try? FileManager.default.removeItem(at: out)
            return ImageOutcome(output: nil, before: before, after: before, removedLocation: false)
        }
        return ImageOutcome(output: out, before: before, after: after, removedLocation: hadLocation && s.stripLocation)
    }

    private static func write(_ img: CGImage, meta: [CFString: Any], to url: URL, type: UTType) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw HoleError.tool("\(type.preferredFilenameExtension?.uppercased() ?? "Görsel") yazılamadı")
        }
        CGImageDestinationAddImage(dest, img, meta as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw HoleError.tool("Görsel kaydedilemedi") }
    }

    /// Saydam görseli beyaz zemine oturtur; saydamlığı yoksa nil döner.
    private static func flatten(_ img: CGImage) -> CGImage? {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(r)
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    // MARK: - PDF

    private static func document(_ u: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: u) else { throw HoleError.unreadable }
        if d.isLocked || d.isEncrypted && !d.unlock(withPassword: "") { throw HoleError.tool("Şifreli PDF işlenemez") }
        return d
    }

    /// Birden çok PDF bırakıldığı sırayla tek dosyada birleşir.
    static func mergePDFs(_ urls: [URL]) throws -> HoleResult {
        let merged = PDFDocument()
        for u in urls {
            let d = try document(u)
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage { merged.insert(p, at: merged.pageCount) }
            }
        }
        let out = freeURL(in: urls[0].deletingLastPathComponent(), base: urls[0].deletingPathExtension().lastPathComponent + "_merged", ext: "pdf")
        guard merged.write(to: out) else { throw HoleError.tool("PDF kaydedilemedi") }
        return HoleResult(ok: true, title: "\(urls.count) PDF birleştirildi", detail: "\(merged.pageCount) sayfa · \(bytes(size(of: out)))",
                          outputs: [out], consumed: true)
    }

    /// İçindeki görselleri ekran kalitesinde JPG olarak yeniden yazar. Küçülmezse dosya tutulmaz.
    static func compressPDF(_ u: URL) throws -> HoleResult {
        let d = try document(u)
        let out = freeURL(in: u.deletingLastPathComponent(), base: u.deletingPathExtension().lastPathComponent + "_compressed", ext: "pdf")
        guard #available(macOS 13.4, *) else {
            return HoleResult(ok: false, title: "PDF sıkıştırma macOS 13.4 ister", consumed: false)
        }
        guard d.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]) else {
            throw HoleError.tool("PDF kaydedilemedi")
        }
        let before = size(of: u), after = size(of: out)
        guard after < Int64(Double(before) * 0.95) else {
            try? FileManager.default.removeItem(at: out)
            return HoleResult(ok: false, title: "Bu PDF zaten sıkıştırılmış", detail: bytes(before), consumed: false)
        }
        return HoleResult(ok: true, title: "PDF sıkıştırıldı", detail: saving(before, after), outputs: [out], consumed: true)
    }

    /// Beyaz delik: her sayfa ayrı bir PDF olarak bir klasöre çıkar.
    static func splitPDF(_ u: URL) throws -> HoleResult {
        let d = try document(u)
        guard d.pageCount > 1 else { return HoleResult(ok: false, title: "Tek sayfalık PDF ayrılamaz", consumed: false) }
        let name = u.deletingPathExtension().lastPathComponent
        let folder = freeURL(in: u.deletingLastPathComponent(), base: name + "_pages", ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let digits = String(d.pageCount).count
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
            let one = PDFDocument()
            one.insert(p, at: 0)
            let n = String(repeating: "0", count: digits - String(i + 1).count) + String(i + 1)
            guard one.write(to: folder.appendingPathComponent("\(name)_\(n).pdf")) else { throw HoleError.tool("Sayfa kaydedilemedi") }
        }
        return HoleResult(ok: true, title: "PDF sayfalara ayrıldı", detail: "\(d.pageCount) ayrı PDF", outputs: [folder], consumed: true)
    }

    /// Beyaz delik: görseller bırakıldığı sırayla tek bir PDF'in sayfaları olur.
    static func imagesToPDF(_ urls: [URL]) throws -> HoleResult {
        let pdf = PDFDocument()
        for u in urls {
            guard let img = NSImage(contentsOf: u), let page = PDFPage(image: img) else { throw HoleError.unreadable }
            pdf.insert(page, at: pdf.pageCount)
        }
        let out = freeURL(in: urls[0].deletingLastPathComponent(), base: urls[0].deletingPathExtension().lastPathComponent + "_merged", ext: "pdf")
        guard pdf.write(to: out) else { throw HoleError.tool("PDF kaydedilemedi") }
        return HoleResult(ok: true, title: "\(urls.count) görsel tek PDF oldu", detail: "\(pdf.pageCount) sayfa · \(bytes(size(of: out)))",
                          outputs: [out], consumed: true)
    }
}

import Foundation

/// Kara deliğin rengi, ne yapacağını belirler.
enum HoleMode: Equatable {
    case normal     // mor: sıkıştırma ve dönüştürme
    case white      // beyaz delik: çıkarma (arşiv açma)
    case red        // kırmızı: Çöp Sepeti'ne taşıma
}

struct HoleResult {
    var ok: Bool
    var title: String
    var detail: String?
    var outputs: [URL] = []
    /// Dosyalar kara delikte kaldı mı? Hayırsa kara delik onları geri fırlatır.
    var consumed: Bool
}

enum HoleError: LocalizedError {
    case tool(String)
    case invalidJSON
    case emptyCSV
    case unreadable

    var errorDescription: String? {
        switch self {
        case .tool(let m): return m.isEmpty ? "İşlem tamamlanamadı" : m
        case .invalidJSON: return "Geçerli bir JSON değil"
        case .emptyCSV: return "CSV dosyasında veri yok"
        case .unreadable: return "Dosya okunamadı"
        }
    }
}

/// Kara deliğe bırakılan dosyaları işler. Kırmızı mod dışında orijinal dosyaya asla dokunmaz,
/// çıktıyı orijinalin yanına, üzerine yazmadan kaydeder.
enum HoleProcessor {
    static func isArchive(_ u: URL) -> Bool {
        let n = u.lastPathComponent.lowercased()
        return !isDirectory(u) && (n.hasSuffix(".zip") || n.hasSuffix(".tar.gz") || n.hasSuffix(".tgz") || n.hasSuffix(".tar"))
    }

    static func isDirectory(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && (try? u.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
    }

    /// Sürükleme sırasında kara deliğin rengi.
    static func mode(for urls: [URL], shift: Bool, option: Bool) -> HoleMode {
        if option { return .red }
        if shift || (!urls.isEmpty && urls.allSatisfy(isArchive)) { return .white }
        return .normal
    }

    static func process(_ urls: [URL], mode: HoleMode, trashOriginal: Bool, settings: HoleSettings = HoleSettings(),
                        trash: (URL) throws -> Void, progress: (Double) -> Void = { _ in }) -> HoleResult {
        guard !urls.isEmpty else { return HoleResult(ok: false, title: "Dosya yok", consumed: false) }
        if mode == .red {
            var moved = 0
            for u in urls { if (try? trash(u)) != nil { moved += 1 } }
            return HoleResult(ok: moved > 0, title: moved == urls.count ? "\(moved) öğe Çöp Sepeti'ne taşındı" : "\(moved)/\(urls.count) öğe Çöp Sepeti'ne taşındı",
                              detail: "Çöp Sepeti'nden geri alabilirsin", consumed: moved > 0)
        }
        var result: HoleResult
        do {
            result = try route(urls, mode: mode, settings: settings, progress: progress)
        } catch {
            return HoleResult(ok: false, title: "Olmadı", detail: error.localizedDescription, consumed: false)
        }
        if result.ok, result.consumed, trashOriginal {
            for u in urls { try? trash(u) }
            result.detail = [result.detail, "Orijinal Çöp Sepeti'nde"].compactMap { $0 }.joined(separator: " · ")
        }
        return result
    }

    private static func route(_ urls: [URL], mode: HoleMode, settings: HoleSettings, progress: (Double) -> Void) throws -> HoleResult {
        if urls.allSatisfy(isVideo) { return try videos(urls, mode: mode, settings: settings, progress: progress) }
        if mode == .white || urls.allSatisfy(isArchive) {
            if urls.count == 1, isPDF(urls[0]) { return try splitPDF(urls[0]) }
            if urls.allSatisfy(isImage) { return try imagesToPDF(urls) }
            guard urls.allSatisfy(isArchive) else {
                return HoleResult(ok: false, title: "Beyaz delik bunu ayıramaz",
                                  detail: "Arşivi açar, PDF'i ayırır, görselleri PDF yapar, videodan ses ya da GIF çıkarır", consumed: false)
            }
            var outs: [URL] = []
            var items = 0
            for u in urls {
                let (dest, n) = try extract(u)
                outs.append(dest)
                items += n
            }
            return HoleResult(ok: true, title: urls.count == 1 ? "Arşiv açıldı" : "\(urls.count) arşiv açıldı",
                              detail: "\(items) öğe çıkarıldı", outputs: outs, consumed: true)
        }
        if urls.allSatisfy(isImage) { return try images(urls, settings: settings) }
        if urls.allSatisfy(isPDF) { return urls.count == 1 ? try compressPDF(urls[0]) : try mergePDFs(urls) }
        if urls.count == 1, let u = urls.first, !isDirectory(u) {
            switch u.pathExtension.lowercased() {
            case "json": return try formatJSON(u)
            case "csv": return try csvToJSON(u)
            default:
                return HoleResult(ok: false, title: "Bu dosya türü için henüz işlem yok",
                                  consumed: false)
            }
        }
        return try zip(urls)
    }

    // MARK: - Ortak

    static func size(of u: URL) -> Int64 {
        guard isDirectory(u) else { return Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let f = e?.nextObject() as? URL {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    /// Örnek: "−%72 · 12,4 MB → 3,4 MB"
    static func saving(_ before: Int64, _ after: Int64) -> String {
        guard before > 0 else { return bytes(after) }
        let change = Int((Double(after - before) / Double(before) * 100).rounded())
        let sign = change < 0 ? "−" : "+"
        return "\(sign)%\(abs(change)) · \(bytes(before)) → \(bytes(after))"
    }

    /// Aynı adlı bir şey varsa "Ad 2", "Ad 3" diye yeni bir ad bulur; hiçbir şeyin üzerine yazmaz.
    static func freeURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        func make(_ n: String) -> URL { ext.isEmpty ? dir.appendingPathComponent(n) : dir.appendingPathComponent(n).appendingPathExtension(ext) }
        var url = make(base)
        var k = 2
        while fm.fileExists(atPath: url.path) { url = make("\(base) \(k)"); k += 1 }
        return url
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw HoleError.tool(String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Arşivler

    /// Tek klasör kendi adıyla, birden çok öğe "Arşiv.zip" olarak sıkıştırılır.
    static func zip(_ urls: [URL]) throws -> HoleResult {
        let before = urls.reduce(Int64(0)) { $0 + size(of: $1) }
        let out: URL
        if urls.count == 1, let u = urls.first {
            out = freeURL(in: u.deletingLastPathComponent(), base: u.lastPathComponent, ext: "zip")
            // __MACOSX artıkları olmadan, her sistemde temiz açılan bir ZIP
            try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", u.path, out.path])
        } else {
            let root = commonParent(urls)
            out = freeURL(in: urls[0].deletingLastPathComponent(), base: "Arşiv", ext: "zip")
            let names = urls.map { "./" + relative($0, to: root) }
            try run("/usr/bin/zip", ["-r", "-y", "-q", out.path] + names + ["-x", "*.DS_Store"], cwd: root)
        }
        let after = size(of: out)
        return HoleResult(ok: true, title: urls.count == 1 && isDirectory(urls[0]) ? "Klasör ZIP oldu" : "\(urls.count) öğe ZIP oldu",
                          detail: saving(before, after), outputs: [out], consumed: true)
    }

    private static func commonParent(_ urls: [URL]) -> URL {
        var parts = urls[0].deletingLastPathComponent().standardizedFileURL.pathComponents
        for u in urls.dropFirst() {
            let other = u.deletingLastPathComponent().standardizedFileURL.pathComponents
            var k = 0
            while k < min(parts.count, other.count), parts[k] == other[k] { k += 1 }
            parts = Array(parts.prefix(k))
        }
        return URL(fileURLWithPath: NSString.path(withComponents: parts.isEmpty ? ["/"] : parts))
    }

    private static func relative(_ u: URL, to root: URL) -> String {
        let a = u.standardizedFileURL.pathComponents, b = root.standardizedFileURL.pathComponents
        return a.dropFirst(b.count).joined(separator: "/")
    }

    /// Arşivi yanındaki yeni bir klasöre açar. Arşivin kendisi yerinde kalır.
    static func extract(_ u: URL) throws -> (URL, Int) {
        let name = u.lastPathComponent
        let lower = name.lowercased()
        var base = name
        for ext in [".tar.gz", ".tgz", ".tar", ".zip"] where lower.hasSuffix(ext) {
            base = String(name.dropLast(ext.count))
            break
        }
        let dest = freeURL(in: u.deletingLastPathComponent(), base: base.isEmpty ? "Arşiv" : base, ext: "")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        do {
            if lower.hasSuffix(".zip") {
                try run("/usr/bin/ditto", ["-x", "-k", u.path, dest.path])
            } else {
                try run("/usr/bin/tar", [lower.hasSuffix(".tar") ? "-xf" : "-xzf", u.path, "-C", dest.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dest.path))?.filter { !$0.hasPrefix(".") }.count ?? 0
        return (dest, items)
    }

    // MARK: - JSON

    static func readText(_ u: URL) throws -> String {
        guard let data = try? Data(contentsOf: u) else { throw HoleError.unreadable }
        for enc in [String.Encoding.utf8, .utf16, .windowsCP1254, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return s }
        }
        throw HoleError.unreadable
    }

    /// Tek satırlık JSON okunur hale getirilir, girintili JSON tek satıra küçültülür. Anahtar sırası korunur.
    static func formatJSON(_ u: URL) throws -> HoleResult {
        let text = try readText(u)
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { throw HoleError.invalidJSON }
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.count
        let pretty = lines <= 1
        let out = freeURL(in: u.deletingLastPathComponent(), base: u.deletingPathExtension().lastPathComponent + (pretty ? "_formatted" : "_minified"), ext: "json")
        try reformat(text, pretty: pretty).write(to: out, atomically: true, encoding: .utf8)
        return HoleResult(ok: true, title: pretty ? "JSON düzenlendi" : "JSON küçültüldü",
                          detail: saving(size(of: u), size(of: out)), outputs: [out], consumed: true)
    }

    static func reformat(_ text: String, pretty: Bool) -> String {
        let s = Array(text.unicodeScalars)
        let space: Set<Unicode.Scalar> = [" ", "\n", "\r", "\t"]
        var out = String.UnicodeScalarView()
        var indent = 0, inString = false, escaped = false, i = 0
        func newline() {
            guard pretty else { return }
            out.append("\n")
            for _ in 0..<(indent * 2) { out.append(" ") }
        }
        while i < s.count {
            let ch = s[i]
            if inString {
                out.append(ch)
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                i += 1
                continue
            }
            switch ch {
            case _ where space.contains(ch): break
            case "\"":
                inString = true
                out.append(ch)
            case "{", "[":
                out.append(ch)
                var j = i + 1
                while j < s.count, space.contains(s[j]) { j += 1 }
                if j < s.count, s[j] == "}" || s[j] == "]" {
                    out.append(s[j])
                    i = j
                } else {
                    indent += 1
                    newline()
                }
            case "}", "]":
                indent = max(0, indent - 1)
                newline()
                out.append(ch)
            case ",":
                out.append(ch)
                newline()
            case ":":
                out.append(ch)
                if pretty { out.append(" ") }
            default:
                out.append(ch)
            }
            i += 1
        }
        return String(out) + (pretty ? "\n" : "")
    }

    // MARK: - CSV

    /// Tırnaklı alanları, satır içi satır sonlarını ve ; veya sekme ayracını tanır.
    static func parseCSV(_ raw: String) -> [[String]] {
        var scalars = Array(raw.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var quoted = false
        for ch in scalars {
            if ch == "\"" { quoted.toggle() }
            if !quoted, ch == "\n" || ch == "\r" { break }
            if !quoted, counts[ch] != nil { counts[ch]! += 1 }
        }
        let delimiter = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key != "," }!.key

        var rows: [[String]] = [], row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false, i = 0
        func endField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < scalars.count {
            let ch = scalars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                endField()
            } else if ch == "\r" {
                endRow()
                if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            } else if ch == "\n" {
                endRow()
            } else {
                field.append(ch)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        while let last = rows.last, last.allSatisfy(\.isEmpty) { rows.removeLast() }
        return rows
    }

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    /// İlk satır başlık olur; her satır sütun sırası korunarak bir JSON nesnesine dönüşür. Değerler metin olarak kalır.
    static func csvToJSON(_ u: URL) throws -> HoleResult {
        let rows = parseCSV(try readText(u))
        guard let header = rows.first, rows.count >= 1 else { throw HoleError.emptyCSV }
        var keys: [String] = []
        for (k, h) in header.enumerated() {
            var key = h.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { key = "sutun_\(k + 1)" }
            var unique = key, n = 2
            while keys.contains(unique) { unique = "\(key)_\(n)"; n += 1 }
            keys.append(unique)
        }
        var json = "[\n"
        let body = rows.dropFirst()
        for (r, row) in body.enumerated() {
            json += "  {\n"
            for (k, key) in keys.enumerated() {
                let value = k < row.count ? row[k] : ""
                json += "    \(jsonString(key)): \(jsonString(value))" + (k < keys.count - 1 ? ",\n" : "\n")
            }
            json += "  }" + (r < body.count - 1 ? ",\n" : "\n")
        }
        json += "]\n"
        let out = freeURL(in: u.deletingLastPathComponent(), base: u.deletingPathExtension().lastPathComponent + "_converted", ext: "json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return HoleResult(ok: true, title: "CSV → JSON", detail: "\(body.count) satır, \(keys.count) sütun",
                          outputs: [out], consumed: true)
    }
}

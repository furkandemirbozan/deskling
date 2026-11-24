import AppKit

enum ClipKind: String, Codable, CaseIterable {
    case text, link, code, color

    var title: String {
        switch self {
        case .text: return "Metin"
        case .link: return "Bağlantı"
        case .code: return "Kod"
        case .color: return "Renk"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        }
    }

    /// Arama kutusuna yazılınca bu türü getiren kelimeler.
    var keywords: [String] {
        switch self {
        case .text: return ["metin", "yazı"]
        case .link: return ["link", "bağlantı", "url"]
        case .code: return ["kod", "code"]
        case .color: return ["renk", "color", "hex", "rgb"]
        }
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var rtf: Data?
    var kind: ClipKind
    var date: Date
    var appName: String?
    var appBundle: String?
    var appPath: String?
    var pinned = false

    /// Listede görünen iki satırlık özet.
    var preview: String {
        let raw = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        // Kodda girinti korunur, düz metinde satırlar tek satıra toplanır.
        let joined = kind == .code
            ? raw.prefix(3).map { String($0.replacingOccurrences(of: "\t", with: "    ")) }.joined(separator: "\n")
            : raw.prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return joined.count > 220 ? String(joined.prefix(219)) + "…" : joined
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if kind.keywords.contains(where: { $0.hasPrefix(q.lowercased()) }) { return true }
        return text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || (appName?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
    }
}

/// Kopyalanan metnin türünü tahmin eder.
enum ClipClassifier {
    static func kind(of raw: String) -> ClipKind {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClipColor.parse(t) != nil { return .color }
        if isLink(t) { return .link }
        if codeScore(raw) >= 3 { return .code }
        return .text
    }

    static func isLink(_ t: String) -> Bool {
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace }) else { return false }
        if t.lowercased().hasPrefix("www."), t.contains(".") { return true }
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased() else { return false }
        if ["http", "https", "ftp"].contains(scheme) { return u.host != nil }
        return ["mailto", "ssh", "file"].contains(scheme)
    }

    /// Kod belirtilerini sayar: süslü parantez, noktalı virgülle biten satır, girinti, anahtar kelime, ok işareti.
    static func codeScore(_ t: String) -> Int {
        let lines = t.split(separator: "\n", omittingEmptySubsequences: false)
        var score = 0
        if t.contains("{") && t.contains("}") { score += 1 }
        if lines.filter({ $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }).count >= 1 { score += 1 }
        if lines.count >= 2, lines.dropFirst().contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) { score += 1 }
        let keywords = ["func ", "let ", "var ", "const ", "def ", "class ", "import ", "return ", "=>", "->", "#include", "public ",
                        "private ", "SELECT ", "function ", "</", "elif ", "fn ", "struct ", "interface ", "async ", "await "]
        let hits = keywords.filter { t.contains($0) }.count
        score += min(2, hits)
        if t.range(of: #"\w+\([^)]*\)"#, options: .regularExpression) != nil { score += 1 }
        if lines.count == 1 { score -= 1 }   // tek satırlık cümleler kolayca kod sanılmasın
        return score
    }
}

/// HEX, rgb() ve hsl() biçimlerini okur ve birbirine çevirir.
struct ClipColor: Equatable {
    var r: Double, g: Double, b: Double   // 0...255
    var a: Double = 1

    static func parse(_ raw: String) -> ClipColor? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
            if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            let v = UInt64(hex, radix: 16)!
            if hex.count == 8 {
                return ClipColor(r: Double((v >> 24) & 255), g: Double((v >> 16) & 255), b: Double((v >> 8) & 255), a: Double(v & 255) / 255)
            }
            return ClipColor(r: Double((v >> 16) & 255), g: Double((v >> 8) & 255), b: Double(v & 255))
        }
        func numbers(_ prefix: String) -> [Double]? {
            guard s.hasPrefix(prefix), s.hasSuffix(")"), let open = s.firstIndex(of: "(") else { return nil }
            let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
            let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { $0.replacingOccurrences(of: "%", with: "") }
            let values = parts.compactMap(Double.init)
            return values.count == parts.count && (3...4).contains(values.count) ? values : nil
        }
        if let v = numbers("rgb"), v[0...2].allSatisfy({ (0...255).contains($0) }) {
            return ClipColor(r: v[0], g: v[1], b: v[2], a: v.count == 4 ? min(1, v[3]) : 1)
        }
        if let v = numbers("hsl"), (0...360).contains(v[0]), (0...100).contains(v[1]), (0...100).contains(v[2]) {
            var c = fromHSL(v[0], v[1] / 100, v[2] / 100)
            if v.count == 4 { c.a = min(1, v[3]) }
            return c
        }
        return nil
    }

    static func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> ClipColor {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return ClipColor(r: ((r + m) * 255).rounded(), g: ((g + m) * 255).rounded(), b: ((b + m) * 255).rounded())
    }

    var hex: String {
        let base = String(format: "#%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
        return a < 1 ? base + String(format: "%02X", Int((a * 255).rounded())) : base
    }

    var rgb: String {
        a < 1 ? String(format: "rgba(%d, %d, %d, %.2g)", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()), a)
              : "rgb(\(Int(r.rounded())), \(Int(g.rounded())), \(Int(b.rounded())))"
    }

    var hsl: String {
        let rr = r / 255, gg = g / 255, bb = b / 255
        let mx = max(rr, gg, bb), mn = min(rr, gg, bb)
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case rr: h = (gg - bb) / d + (gg < bb ? 6 : 0)
            case gg: h = (bb - rr) / d + 2
            default: h = (rr - gg) / d + 4
            }
            h *= 60
        }
        return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    var nsColor: NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
}

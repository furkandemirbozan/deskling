import Foundation

/// Bir tuşun sesi: hangi dosyanın hangi aralığı (milisaniye).
struct KeySlice: Equatable {
    var file: String
    var start: Double
    var end: Double
}

/// Ses paketinin tanımı (Mechvibes `config.json`, sürüm 1 ve 2).
struct SoundPackConfig: Equatable {
    var id: String
    var name: String
    var author: String
    var description: String
    var version: String
    var volume: Float
    var randomPitch: Bool
    var down: [String: KeySlice]
    var up: [String: KeySlice]

    var files: Set<String> { Set(down.values.map(\.file) + up.values.map(\.file)) }

    static let audioExtensions: Set<String> = ["ogg", "wav", "mp3", "m4a", "aif", "aiff", "flac", "caf"]

    /// Paketin dışına çıkan ya da garip adlı dosyaları reddeder.
    static func safeFileName(_ s: String) -> Bool {
        !s.isEmpty && !s.contains("/") && !s.contains("\\") && s != "." && s != ".." && !s.hasPrefix(".")
            && audioExtensions.contains((s as NSString).pathExtension.lowercased())
    }

    enum ParseError: LocalizedError {
        case notJSON, noSound, badFile(String)
        var errorDescription: String? {
            switch self {
            case .notJSON: return "config.json okunamadı"
            case .noSound: return "pakette tuş sesi tanımı yok"
            case .badFile(let f): return "güvenli olmayan dosya adı: \(f)"
            }
        }
    }

    static func parse(_ data: Data, fallbackID: String) throws -> SoundPackConfig {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notJSON }
        let options = o["options"] as? [String: Any] ?? [:]
        var c = SoundPackConfig(id: (o["id"] as? String) ?? fallbackID, name: (o["name"] as? String) ?? fallbackID,
                                author: (o["author"] as? String) ?? "", description: (o["description"] as? String) ?? "",
                                version: (o["version"] as? String) ?? "\(o["version"] as? Int ?? 1)",
                                volume: Float((options["recommended_volume"] as? Double) ?? 1),
                                randomPitch: (options["random_pitch"] as? Bool) ?? false, down: [:], up: [:])
        let mainFile = (o["audio_file"] as? String) ?? (o["sound"] as? String) ?? ""
        if let defs = o["definitions"] as? [String: Any] {
            // Sürüm 2: tuş adı → { timing: [[başla, bitir], [bırakma başla, bitir]], audio_file? }
            for (code, v) in defs {
                guard let d = v as? [String: Any], let timing = d["timing"] as? [[Double]] else { continue }
                let file = (d["audio_file"] as? String) ?? mainFile
                if let t = timing.first, t.count >= 2, t[1] > t[0] { c.down[code] = KeySlice(file: file, start: t[0], end: t[1]) }
                if timing.count > 1, timing[1].count >= 2, timing[1][1] > timing[1][0] {
                    c.up[code] = KeySlice(file: file, start: timing[1][0], end: timing[1][1])
                }
            }
        } else if let defs = o["defines"] as? [String: Any] {
            // Sürüm 1: tuş numarası → [başla, süre] ya da (çok dosyalı) dosya adı.
            let multi = (o["key_define_type"] as? String) == "multi"
            for (k, v) in defs {
                guard let n = Int(k), let code = KeyCodes.legacy[n] else { continue }
                if multi, let f = v as? String { c.down[code] = KeySlice(file: f, start: 0, end: 1500) }
                else if let a = v as? [Double], a.count >= 2, a[1] > 0 { c.down[code] = KeySlice(file: mainFile, start: a[0], end: a[0] + a[1]) }
            }
        }
        guard !c.down.isEmpty else { throw ParseError.noSound }
        for f in c.files where !safeFileName(f) { throw ParseError.badFile(f) }
        c.volume = min(2, max(0.05, c.volume))
        return c
    }
}

/// Panelde görünen paket bilgisi.
struct SoundPackInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var author: String
    var description: String
    var license: String?
    var keyCount: Int
    var hasRelease: Bool
    var builtin: Bool
    var folder: URL?
    var source: String?
    var baseID: String = ""
    var version: String = "1"

    /// "Personal use only. Original author: …" → "Kişisel kullanım"
    var licenseTitle: String? {
        guard let l = license?.lowercased() else { return nil }
        if l.contains("personal use") { return "Kişisel kullanım" }
        if l.contains("cc0") { return "CC0" }
        if l.contains("cc by") || l.contains("attribution") { return "CC BY" }
        if l.contains("mit") { return "MIT" }
        return "Özel lisans"
    }
}

/// Kaynak klasördeki zip'leri ve klasörleri okur, Deskling'in kendi klasörüne açar.
/// Kaynak klasöre hiçbir şey yazmaz, oradaki dosyaları değiştirmez ya da silmez.
final class SoundPackStore {
    let cache: URL
    static let maxZip: Int64 = 80 * 1_048_576
    static let maxFile: Int64 = 40 * 1_048_576

    init(cache: URL) { self.cache = cache }

    static func liveCache() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Deskling/KlavyeSesleri")
    }

    struct Result {
        var packs: [SoundPackInfo]
        var problems: [String]
        /// Aynı paketin atlanan kopyaları.
        var duplicates = 0
    }

    /// Klasörü ve alt klasörlerini (3 kata kadar) okur. Aynı paket birden çok yerde varsa yalnızca en yeni sürümü alınır.
    func sync(from folder: URL) -> Result {
        let fm = FileManager.default
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        var found: [SoundPackInfo] = []
        var problems: [String] = []
        let base = folder.resolvingSymlinksInPath().path + "/"
        func rel(_ u: URL) -> String {
            let p = u.resolvingSymlinksInPath().path
            return p.hasPrefix(base) ? String(p.dropFirst(base.count)) : u.lastPathComponent
        }
        for item in Self.candidates(in: folder) {
            do {
                let dir = item.pathExtension.lowercased() == "zip" ? try unpack(item) : try packRoot(item)
                var info = try Self.info(at: dir)
                info.source = rel(item)
                found.append(info)
            } catch {
                problems.append("\(rel(item)): \(error.localizedDescription)")
            }
        }
        let (unique, dup) = Self.dedupe(found)
        return Result(packs: unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                      problems: problems, duplicates: dup)
    }

    /// Zip'ler ve içinde config.json olan klasörler; diğer klasörlerin içine bakılır.
    static func candidates(in folder: URL, depth: Int = 0) -> [URL] {
        let fm = FileManager.default
        let items = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                   options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var out: [URL] = []
        for item in items {
            let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v?.isSymbolicLink == true { continue }
            if item.pathExtension.lowercased() == "zip" { out.append(item); continue }
            guard v?.isDirectory == true else { continue }
            if fm.fileExists(atPath: item.appendingPathComponent("config.json").path) { out.append(item) }
            else if depth < 3 { out += candidates(in: item, depth: depth + 1) }
        }
        return out
    }

    /// Aynı paket: aynı kimlik ya da aynı ad ve yapımcı. Sürüm numarası büyük olan kalır.
    static func dedupe(_ list: [SoundPackInfo]) -> ([SoundPackInfo], Int) {
        var keep: [SoundPackInfo] = []
        var dup = 0
        func same(_ a: SoundPackInfo, _ b: SoundPackInfo) -> Bool {
            a.baseID == b.baseID || (a.name.lowercased() == b.name.lowercased() && a.author.lowercased() == b.author.lowercased())
        }
        for p in list {
            if let i = keep.firstIndex(where: { same($0, p) }) {
                dup += 1
                if p.version.compare(keep[i].version, options: .numeric) == .orderedDescending { keep[i] = p }
            } else {
                keep.append(p)
            }
        }
        return (keep, dup)
    }

    enum ImportError: LocalizedError {
        case tooBig, unzip, unsafe, noConfig
        var errorDescription: String? {
            switch self {
            case .tooBig: return "dosya çok büyük"
            case .unzip: return "zip açılamadı"
            case .unsafe: return "pakette güvenli olmayan bir şey var"
            case .noConfig: return "config.json bulunamadı"
            }
        }
    }

    /// Zip'i bir kez açar; aynı zip (ad, boyut, tarih) yeniden açılmaz.
    func unpack(_ zip: URL) throws -> URL {
        let fm = FileManager.default
        let v = try zip.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(v.fileSize ?? 0)
        guard size <= Self.maxZip else { throw ImportError.tooBig }
        let stamp = Int(v.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let key = Self.slug(zip.deletingPathExtension().lastPathComponent) + "-\(size)-\(stamp)"
        let target = cache.appendingPathComponent(key)
        if fm.fileExists(atPath: target.appendingPathComponent("config.json").path) { return target }
        if let r = try? packRoot(target) { return r }

        try Self.checkEntries(zip)
        let tmp = cache.appendingPathComponent(".acılıyor-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, tmp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.unzip }
        try Self.checkSafe(tmp)
        let root = try packRoot(tmp)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: root, to: target)
        return target
    }

    /// Açmadan önce içindekilere bakar: klasörün dışına çıkan ("../") ya da mutlak yollu girdiler reddedilir.
    static func checkEntries(_ zip: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        p.arguments = ["-1", zip.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.unzip }
        let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard names.count <= 2000 else { throw ImportError.unsafe }
        for n in names where n.hasPrefix("/") || n.split(separator: "/").contains("..") || n.contains("\\") {
            throw ImportError.unsafe
        }
    }

    /// config.json en üstte ya da tek bir alt klasörde olabilir.
    func packRoot(_ dir: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) { return dir }
        let subs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && $0.lastPathComponent != "__MACOSX" }
        if subs.count == 1, fm.fileExists(atPath: subs[0].appendingPathComponent("config.json").path) { return subs[0] }
        throw ImportError.noConfig
    }

    /// Bağlantı (symlink), çok büyük dosya ya da çok fazla dosya varsa paketi reddeder.
    static func checkSafe(_ dir: URL) throws {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey],
                                                     options: []) else { throw ImportError.unsafe }
        var n = 0
        let base = dir.resolvingSymlinksInPath().path
        for case let f as URL in e {
            n += 1
            let v = try f.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
            if v.isSymbolicLink == true || n > 2000 || Int64(v.fileSize ?? 0) > maxFile { throw ImportError.unsafe }
            guard f.resolvingSymlinksInPath().path.hasPrefix(base) else { throw ImportError.unsafe }
        }
    }

    static func info(at dir: URL) throws -> SoundPackInfo {
        let data = try Data(contentsOf: dir.appendingPathComponent("config.json"))
        let c = try SoundPackConfig.parse(data, fallbackID: dir.lastPathComponent)
        for f in c.files where !FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path) {
            throw SoundPackConfig.ParseError.badFile(f + " eksik")
        }
        let license = (try? String(contentsOf: dir.appendingPathComponent("LICENSE.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SoundPackInfo(id: c.id + "@" + c.version, name: c.name, author: c.author, description: c.description,
                             license: license?.isEmpty == false ? license : nil, keyCount: c.down.count,
                             hasRelease: !c.up.isEmpty, builtin: false, folder: dir, baseID: c.id, version: c.version)
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let t = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return String(t.prefix(60))
    }
}

import AppKit
import SwiftUI

/// Diskte incelenen bölümler.
enum DiskKind: String, CaseIterable, Identifiable {
    case apps, caches, logs, developer, downloads, large, backups, trash
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Uygulamalar"
        case .caches: return "Önbellekler"
        case .logs: return "Günlükler"
        case .developer: return "Geliştirici"
        case .downloads: return "İndirilenler"
        case .large: return "Büyük dosyalar"
        case .backups: return "iPhone yedekleri"
        case .trash: return "Çöp Kutusu"
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2.fill"
        case .caches: return "shippingbox.fill"
        case .logs: return "doc.text.fill"
        case .developer: return "hammer.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .large: return "film.stack.fill"
        case .backups: return "iphone"
        case .trash: return "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .apps: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .caches: return Color(red: 0.98, green: 0.62, blue: 0.18)
        case .logs: return Color(red: 0.55, green: 0.58, blue: 0.64)
        case .developer: return Color(red: 0.62, green: 0.38, blue: 0.92)
        case .downloads: return Color(red: 0.16, green: 0.72, blue: 0.70)
        case .large: return Color(red: 0.93, green: 0.33, blue: 0.55)
        case .backups: return Color(red: 0.36, green: 0.42, blue: 0.86)
        case .trash: return Color(red: 0.62, green: 0.48, blue: 0.36)
        }
    }

    var detail: String {
        switch self {
        case .apps: return "Ne zaman açıldığı, kaç kez kullanıldığı ve ne zamandır yüklü olduğuna bakılır."
        case .caches: return "Uygulamaların geçici dosyaları. Silinirse gerektiğinde yeniden oluşturulur."
        case .logs: return "Uygulama ve çökme günlükleri. Eskileri güvenle silinebilir."
        case .developer: return "Xcode derleme artıkları, simülatör önbellekleri ve paket yöneticisi önbellekleri."
        case .downloads: return "Kurulum dosyaları ve uzun süredir açılmayan indirmeler."
        case .large: return "Belgeler, Masaüstü, Filmler, Müzik ve Resimler'deki 500 MB'tan büyük dosyalar."
        case .backups: return "Finder ile alınmış iPhone ve iPad yedekleri. En yenisi korunur."
        case .trash: return "Çöp Kutusu'ndakiler yer kaplamaya devam eder; Finder'dan boşaltınca yer açılır."
        }
    }
}

/// Bir öğe için verilen karar.
enum DiskVerdict: Int, Comparable, CaseIterable {
    case keep = 0, review = 1, remove = 2
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .keep: return "Gerekli"
        case .review: return "Gözden geçir"
        case .remove: return "Silinebilir"
        }
    }

    var color: Color {
        switch self {
        case .keep: return Color(red: 0.20, green: 0.70, blue: 0.40)
        case .review: return Color(red: 0.96, green: 0.66, blue: 0.16)
        case .remove: return Color(red: 0.93, green: 0.30, blue: 0.28)
        }
    }

    var symbol: String {
        switch self {
        case .keep: return "checkmark.shield.fill"
        case .review: return "eye.fill"
        case .remove: return "trash.fill"
        }
    }
}

/// Diskteki bir öğe: bir uygulama, bir önbellek klasörü, bir dosya…
struct DiskItem: Identifiable, Equatable {
    let url: URL
    let kind: DiskKind
    var name: String
    var size: Int64
    var lastUsed: Date? = nil
    var added: Date? = nil
    var modified: Date? = nil
    var useCount: Int? = nil
    var bundleID: String? = nil
    /// Kendisi ya da sahibi olan uygulama şu an açık.
    var running = false
    /// Hiçbir koşulda silinmesi önerilmez (Apple uygulaması, Deskling, kilitli dosya, fotoğraf arşivi…).
    var protected = false
    /// Aynı türün en yenisi (ör. en son iPhone yedeği).
    var newest = false
    var verdict: DiskVerdict = .review
    var reasons: [String] = []

    var id: String { url.path }
    /// Yalnızca gerekli olmayanlar Çöp Kutusu'na taşınabilir; Çöp Kutusu'nun kendisi taşınmaz.
    var canTrash: Bool { verdict != .keep && kind != .trash && !protected }
}

/// Spotlight'tan gelen kullanım bilgisi.
struct FileMeta: Equatable {
    var lastUsed: Date?
    var added: Date?
    var useCount: Int?
}

/// Diskin genel durumu.
struct VolumeInfo: Equatable {
    var total: Int64
    var available: Int64        // önemli işler için kullanılabilir (temizlenebilir alan dahil)
    var free: Int64             // gerçekten boş
    var used: Int64 { max(0, total - available) }
    var purgeable: Int64 { max(0, available - free) }

    static func read(_ url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity else { return nil }
        let free = Int64(v.volumeAvailableCapacity ?? 0)
        let important = v.volumeAvailableCapacityForImportantUsage ?? free
        return VolumeInfo(total: Int64(total), available: max(free, important), free: free)
    }
}

// MARK: - Kurallar

/// Bir öğenin gerekli mi gereksiz mi olduğuna karar verir. Saf: tarih ve öğe dışında hiçbir şeye bakmaz.
///
/// Ölçütler:
/// - **Son kullanım** (Spotlight'ın "son açılma" tarihi, yoksa son değişiklik): yakın zamanda kullanılan hiçbir şey silinebilir sayılmaz.
/// - **Ne zamandır duruyor** (eklenme tarihi): yeni yüklenmiş bir uygulama "hiç açılmadı" diye silinmeye önerilmez.
/// - **Kullanım sıklığı** (açılma sayısı): sık kullanılmış uygulamalar en fazla "gözden geçir" olur.
/// - **Yeniden oluşabilir mi**: önbellek, günlük ve derleme artıkları silinse de kayıp olmaz.
/// - **Şu an kullanılıyor mu**: açık uygulama ve onun önbelleği silinmeye önerilmez.
/// - **Korunanlar**: Apple uygulamaları, Deskling'in kendisi ve klasörleri, kilitli dosyalar, fotoğraf/müzik arşivleri.
enum DiskAdvisor {
    static let day: TimeInterval = 86_400
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip"]
    static let libraryExtensions: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "fcpbundle"]

    static func judge(_ item: DiskItem, now: Date) -> DiskItem {
        var i = item
        var r: [String] = []
        let used = i.lastUsed ?? i.modified
        let usedDays = used.map { days(now.timeIntervalSince($0)) }
        let addedDays = i.added.map { days(now.timeIntervalSince($0)) }
        func set(_ v: DiskVerdict) { i.verdict = v }

        if i.protected {
            set(.keep)
            r.append(protectionReason(i))
            i.reasons = r
            return i
        }

        switch i.kind {
        case .apps:
            if i.running {
                set(.keep); r.append("Şu an açık")
            } else if let d = usedDays, i.lastUsed != nil {
                r.append(d == 0 ? "Bugün kullanıldı" : "\(span(d)) önce kullanıldı")
                if d <= 30 { set(.keep) }
                else if d < 180 { set(.review) }
                else { set((i.useCount ?? 0) >= 50 ? .review : .remove) }
            } else {
                // Hiç açılmamış: yeni yüklendiyse dokunma.
                // Spotlight bazen kaydı tutmaz (ör. taşıma sonrası); bu yüzden yalnızca uzun süredir yüklüyse "silinebilir".
                if let a = addedDays, a < 60 { set(.keep); r.append("Yeni yüklendi, henüz açılmadı") }
                else if let a = addedDays, a < 180 { set(.review); r.append("Açıldığına dair kayıt yok") }
                else { set(.remove); r.append("Hiç açılmadı") }
            }
            if let c = i.useCount, c > 0 { r.append("\(c) kez açıldı") }
            if let a = addedDays { r.append("\(since(a)) yüklü") }

        case .caches:
            if i.running { set(.review); r.append("Sahibi olan uygulama açık; silinirse hemen yeniden oluşur") }
            else if let d = usedDays, d < 2 { set(.review); r.append("Şu sıralar kullanılıyor") }
            else if i.bundleID?.hasPrefix("com.apple.") == true { set(.review); r.append("macOS önbelleği") }
            else { set(.remove); r.append("Yeniden oluşturulabilir") }
            if let d = usedDays, d >= 2 { r.append("\(since(d)) dokunulmadı") }

        case .logs:
            if let d = usedDays, d < 7 { set(.review); r.append("Son \(max(d, 1)) günde yazıldı") }
            else { set(.remove); r.append("Eski günlük"); if let d = usedDays { r.append("\(span(d)) önce") } }

        case .developer:
            let name = i.url.path
            if i.url.lastPathComponent == ".cache" {
                set(.review); r.append("Çeşitli araçların indirdikleri; içine bakıp karar ver")
            } else if name.contains("/Archives") {
                set(.review); r.append("Yayımlanan sürümlerin hata ayıklama bilgisi bunda")
            } else if let d = usedDays, d < 14 {
                set(.review); r.append("Son \(max(d, 1)) günde kullanıldı")
            } else {
                set(.remove); r.append("Derleme artığı ya da önbellek; yeniden oluşturulur")
            }
            if let d = usedDays, d >= 14 { r.append("\(since(d)) kullanılmadı") }

        case .downloads:
            let ext = i.url.pathExtension.lowercased()
            if installerExtensions.contains(ext) {
                if let d = usedDays, d < 7 { set(.review); r.append("Yeni indirilen kurulum dosyası") }
                else { set(.remove); r.append("Kurulum dosyası; uygulama zaten kurulduysa gerekmez") }
            } else if let d = usedDays {
                if d <= 30 { set(.keep) } else if d < 365 { set(.review) } else { set(.remove) }
                r.append(d == 0 ? "Bugün açıldı" : "\(since(d)) açılmadı")
            } else {
                set(.review)
            }

        case .large:
            if let d = usedDays, d <= 90 { set(.keep); r.append(d == 0 ? "Bugün açıldı" : "\(span(d)) önce açıldı") }
            else { set(.review); if let d = usedDays { r.append("\(since(d)) açılmadı") }; r.append("Kişisel dosya; kendin karar ver") }

        case .backups:
            if i.newest { set(.keep); r.append("En yeni yedek") }
            else if let d = usedDays, d >= 180 { set(.remove); r.append("\(span(d)) önce alınmış eski yedek") }
            else { set(.review); if let d = usedDays { r.append("\(span(d)) önce alındı") } }

        case .trash:
            set(.review); r.append("Finder'da Çöp Kutusu'nu boşaltınca yer açılır")
        }
        i.reasons = r
        return i
    }

    static func protectionReason(_ i: DiskItem) -> String {
        if i.bundleID?.hasPrefix("com.apple.") == true || i.url.path.hasPrefix("/System/") { return "macOS'un parçası" }
        if libraryExtensions.contains(i.url.pathExtension.lowercased()) { return "Fotoğraf ya da müzik arşivi" }
        if i.bundleID == Bundle.main.bundleIdentifier || i.name.hasPrefix("Deskling") { return "Deskling'in kendisi" }
        return "Korunuyor"
    }

    static func days(_ t: TimeInterval) -> Int { max(0, Int(t / day)) }

    /// 3 → "3 gün", 45 → "1 ay", 800 → "2 yıl"
    static func span(_ days: Int) -> String {
        if days < 30 { return "\(max(days, 1)) gün" }
        if days < 365 { return "\(days / 30) ay" }
        return "\(days / 365) yıl"
    }

    /// 3 → "3 gündür", 45 → "1 aydır", 800 → "2 yıldır"
    static func since(_ days: Int) -> String {
        if days < 30 { return "\(max(days, 1)) gündür" }
        if days < 365 { return "\(days / 30) aydır" }
        return "\(days / 365) yıldır"
    }

    /// Sıralama: önce silinebilirler, sonra büyükler.
    static func sort(_ a: DiskItem, _ b: DiskItem) -> Bool {
        a.verdict != b.verdict ? a.verdict > b.verdict : a.size > b.size
    }
}

enum DiskFormat {
    static func bytes(_ n: Int64) -> String {
        if n <= 0 { return "0 MB" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: n)
    }
}

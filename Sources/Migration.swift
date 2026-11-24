import Foundation

/// Uygulamanın adı ve verilerinin durduğu yer.
enum AppInfo {
    static let name = "Deskling"
    static let bundleID = "local.deskling.app"

    static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }
}

/// Robo Süpürge'den Deskling'e geçiş: ayarlar, toz haznesi, halı altındaki dosyalar, geçmiş ve pano kayıtları
/// kaybolmadan yeni yerlerine taşınır. Eski veriler silinmez; klasör yalnızca yeni klasör yoksa taşınır.
enum Migration {
    static let oldBundleID = "local.robosupurge.app"
    static let oldFolderName = "RoboSupurge"
    static let doneKey = "migratedFromRoboSupurge"

    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        migrateDefaults(from: oldBundleID, to: Bundle.main.bundleIdentifier ?? AppInfo.bundleID, in: d)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateFolder(from: support.appendingPathComponent(oldFolderName, isDirectory: true), to: AppInfo.supportFolder)
        d.set(true, forKey: doneKey)
    }

    /// Eski uygulamanın ayarları, yeni uygulamada henüz kaydedilmemiş anahtarlar için kopyalanır.
    /// Eski ayarlar yerinde kalır.
    @discardableResult
    static func migrateDefaults(from oldDomain: String, to newDomain: String, in d: UserDefaults = .standard) -> Int {
        guard let old = d.persistentDomain(forName: oldDomain) else { return 0 }
        var own = d.persistentDomain(forName: newDomain) ?? [:]
        var copied = 0
        for (key, value) in old where own[key] == nil {
            own[key] = value
            copied += 1
        }
        d.setPersistentDomain(own, forName: newDomain)
        return copied
    }

    /// Klasör taşınır; geçmişteki "toz haznesindeki yer" yolları yeni klasöre göre düzeltilir.
    @discardableResult
    static func migrateFolder(from old: URL, to new: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return false }
        do {
            try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: new)
        } catch {
            return false
        }
        let history = new.appendingPathComponent("gecmis.json")
        if let data = try? Data(contentsOf: history),
           var records = try? JSONDecoder().decode([CleanRecord].self, from: data) {
            let oldPrefix = old.standardizedFileURL.path + "/", newPrefix = new.standardizedFileURL.path + "/"
            records = records.map { r in
                guard r.trashPath.hasPrefix(oldPrefix) else { return r }
                return CleanRecord(id: r.id, name: r.name, originalPath: r.originalPath,
                                   trashPath: newPrefix + r.trashPath.dropFirst(oldPrefix.count), date: r.date, restored: r.restored)
            }
            if let out = try? JSONEncoder().encode(records) { try? out.write(to: history, options: .atomic) }
        }
        return true
    }
}

import Foundation

/// Robo Süpürge'den Deskling'e geçişi sahte klasör ve sahte ayar alanlarıyla dener; gerçek verilere dokunmaz.
enum MigrationCheck {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("deskling-gecis-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("RoboSupurge"), new = root.appendingPathComponent("Deskling")
        try? fm.createDirectory(at: old.appendingPathComponent("Toz Haznesi"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: old.appendingPathComponent("Halı Altı"), withIntermediateDirectories: true)
        try? "ekran".write(to: old.appendingPathComponent("Toz Haznesi/ekran.png"), atomically: true, encoding: .utf8)
        try? "gizli".write(to: old.appendingPathComponent("Halı Altı/not.txt"), atomically: true, encoding: .utf8)
        try? "[]".write(to: old.appendingPathComponent("pano.json"), atomically: true, encoding: .utf8)
        let record = CleanRecord(name: "ekran.png", originalPath: "/Masaustu/ekran.png",
                                 trashPath: old.path + "/Toz Haznesi/ekran.png", date: Date())
        let outside = CleanRecord(name: "baska.png", originalPath: "/x", trashPath: "/baska/yer/baska.png", date: Date())
        try? JSONEncoder().encode([record, outside]).write(to: old.appendingPathComponent("gecmis.json"))

        check("eski klasör yeni isme taşınır", Migration.migrateFolder(from: old, to: new) && !fm.fileExists(atPath: old.path))
        check("toz haznesi, halı altı ve pano geçmişi taşınır",
              fm.fileExists(atPath: new.appendingPathComponent("Toz Haznesi/ekran.png").path)
                && fm.fileExists(atPath: new.appendingPathComponent("Halı Altı/not.txt").path)
                && fm.fileExists(atPath: new.appendingPathComponent("pano.json").path))
        let records = (try? JSONDecoder().decode([CleanRecord].self, from: Data(contentsOf: new.appendingPathComponent("gecmis.json")))) ?? []
        check("geçmişteki dosya yolları yeni klasöre göre düzelir", records.first?.trashPath == new.path + "/Toz Haznesi/ekran.png"
              && records.first?.id == record.id && fm.fileExists(atPath: records.first?.trashPath ?? ""))
        check("başka yerdeki kayıtlara dokunulmaz", records.last?.trashPath == "/baska/yer/baska.png")
        try? fm.createDirectory(at: old, withIntermediateDirectories: true)
        check("yeni klasör varsa üzerine yazılmaz", !Migration.migrateFolder(from: old, to: new) && fm.fileExists(atPath: old.path))

        let d = UserDefaults.standard
        let oldDomain = "deskling.test.eski.\(UUID().uuidString)", newDomain = "deskling.test.yeni.\(UUID().uuidString)"
        defer { d.removePersistentDomain(forName: oldDomain); d.removePersistentDomain(forName: newDomain) }
        d.setPersistentDomain(["snowEnabled": false, "speed": 300.0, "holeCenterX": 265.0], forName: oldDomain)
        d.setPersistentDomain(["speed": 180.0], forName: newDomain)
        let copied = Migration.migrateDefaults(from: oldDomain, to: newDomain, in: d)
        let merged = d.persistentDomain(forName: newDomain) ?? [:]
        check("eski ayarlar yeni uygulamaya kopyalanır", copied == 2 && merged["snowEnabled"] as? Bool == false && merged["holeCenterX"] as? Double == 265)
        check("yeni uygulamada değiştirilmiş ayar ezilmez", merged["speed"] as? Double == 180)
        check("eski ayarlar yerinde kalır", d.persistentDomain(forName: oldDomain)?.count == 3)
        check("eski uygulama yoksa geçiş bir şey yapmaz", Migration.migrateDefaults(from: "yok.\(UUID().uuidString)", to: newDomain, in: d) == 0)

        print(failures == 0 ? "GECIS_GECTI" : "GECIS_KALDI \(failures)")
        return failures == 0 ? 0 : 1
    }
}

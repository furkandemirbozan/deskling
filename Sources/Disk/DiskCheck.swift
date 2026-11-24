import AppKit
import SwiftUI

/// `--disk-check`: disk kuralları, sahte bir ev klasöründe tarama, Çöp Kutusu'na taşıma (sahte) ve bellek kuralları.
/// Gerçek Masaüstü'ne, İndirilenler'e, Çöp Kutusu'na ya da uygulamalara dokunmaz; hiçbir uygulamayı kapatmaz.
enum DiskCheck {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ info: String = "") {
            print((ok ? "GEÇTİ  " : "KALDI  ") + name + (ok || info.isEmpty ? "" : "  [\(info)]"))
            if !ok { failures += 1 }
        }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func ago(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        func judge(_ i: DiskItem) -> DiskItem { DiskAdvisor.judge(i, now: now) }
        let u = URL(fileURLWithPath: "/tmp/x")
        func app(_ used: Double?, count: Int? = nil, added: Double = 500, id: String = "com.example.a") -> DiskItem {
            judge(DiskItem(url: u.appendingPathComponent("A.app"), kind: .apps, name: "A", size: 1 << 30,
                           lastUsed: used.map(ago), added: ago(added), useCount: count, bundleID: id))
        }

        // Uygulamalar
        check("yakında kullanılan uygulama gerekli", app(5).verdict == .keep && !app(5).canTrash)
        check("200 gündür açılmayan uygulama silinebilir", app(200, count: 3).verdict == .remove)
        check("sık kullanılmış eski uygulama yalnızca gözden geçir", app(200, count: 80).verdict == .review)
        check("90 gündür açılmayan uygulama gözden geçir", app(90).verdict == .review)
        check("yeni yüklenmiş hiç açılmamış uygulama gerekli", app(nil, added: 10).verdict == .keep)
        check("uzun süredir yüklü hiç açılmamış uygulama silinebilir", app(nil, added: 400).verdict == .remove)
        check("kaydı olmayan 3 aylık uygulama yalnızca gözden geçir", app(nil, added: 90).verdict == .review)
        check("~/.cache gözden geçir", judge(DiskItem(url: URL(fileURLWithPath: "/h/.cache"), kind: .developer, name: "c", size: 1, modified: ago(90))).verdict == .review)
        var running = DiskItem(url: u, kind: .apps, name: "R", size: 1, lastUsed: ago(400)); running.running = true
        check("açık uygulama gerekli", judge(running).verdict == .keep)
        var apple = DiskItem(url: u, kind: .apps, name: "Safari", size: 1, lastUsed: ago(900), bundleID: "com.apple.Safari"); apple.protected = true
        check("Apple uygulaması korunur", judge(apple).verdict == .keep && !judge(apple).canTrash && judge(apple).reasons == ["macOS'un parçası"])
        check("gerekçeler yazılır", app(200, count: 3).reasons.contains("6 ay önce kullanıldı") && app(200, count: 3).reasons.contains("3 kez açıldı")
              && app(200, count: 3).reasons.contains("1 yıldır yüklü"), app(200, count: 3).reasons.joined(separator: "|"))

        // Önbellek, günlük, geliştirici
        var cache = DiskItem(url: u, kind: .caches, name: "c", size: 1, modified: ago(20), bundleID: "com.example.c")
        check("eski önbellek silinebilir", judge(cache).verdict == .remove)
        cache.running = true
        check("açık uygulamanın önbelleği gözden geçir", judge(cache).verdict == .review)
        check("macOS önbelleği gözden geçir", judge(DiskItem(url: u, kind: .caches, name: "c", size: 1, modified: ago(20), bundleID: "com.apple.x")).verdict == .review)
        check("şu an yazılan önbellek gözden geçir", judge(DiskItem(url: u, kind: .caches, name: "c", size: 1, modified: ago(0.5))).verdict == .review)
        check("eski günlük silinebilir", judge(DiskItem(url: u, kind: .logs, name: "l", size: 1, modified: ago(30))).verdict == .remove)
        check("yeni günlük gözden geçir", judge(DiskItem(url: u, kind: .logs, name: "l", size: 1, modified: ago(1))).verdict == .review)
        check("eski DerivedData silinebilir", judge(DiskItem(url: u.appendingPathComponent("DerivedData/X"), kind: .developer, name: "d", size: 1, modified: ago(40))).verdict == .remove)
        check("Xcode arşivleri hep gözden geçir", judge(DiskItem(url: URL(fileURLWithPath: "/h/Library/Developer/Xcode/Archives"), kind: .developer, name: "a", size: 1, modified: ago(900))).verdict == .review)

        // İndirilenler, büyük dosyalar, yedekler, çöp
        check("eski kurulum dosyası silinebilir", judge(DiskItem(url: u.appendingPathComponent("Setup.dmg"), kind: .downloads, name: "s", size: 1, modified: ago(20))).verdict == .remove)
        check("yeni kurulum dosyası gözden geçir", judge(DiskItem(url: u.appendingPathComponent("Setup.dmg"), kind: .downloads, name: "s", size: 1, modified: ago(2))).verdict == .review)
        check("yakında açılan indirme gerekli", judge(DiskItem(url: u.appendingPathComponent("r.pdf"), kind: .downloads, name: "r", size: 1, lastUsed: ago(3))).verdict == .keep)
        check("bir yıldır açılmayan indirme silinebilir", judge(DiskItem(url: u.appendingPathComponent("r.pdf"), kind: .downloads, name: "r", size: 1, lastUsed: ago(400))).verdict == .remove)
        check("büyük kişisel dosya hiçbir zaman 'silinebilir' olmaz",
              judge(DiskItem(url: u.appendingPathComponent("v.mov"), kind: .large, name: "v", size: 1, lastUsed: ago(3000))).verdict == .review
              && judge(DiskItem(url: u.appendingPathComponent("v.mov"), kind: .large, name: "v", size: 1, lastUsed: ago(10))).verdict == .keep)
        var newest = DiskItem(url: u, kind: .backups, name: "b", size: 1, modified: ago(400)); newest.newest = true
        check("en yeni yedek korunur, eskisi silinebilir", judge(newest).verdict == .keep
              && judge(DiskItem(url: u, kind: .backups, name: "b", size: 1, modified: ago(400))).verdict == .remove)
        check("Çöp Kutusu'nun kendisi taşınamaz", !judge(DiskItem(url: u, kind: .trash, name: "t", size: 1)).canTrash)
        check("süre yazımı", DiskFormat.bytes(0) == "0 MB" && DiskAdvisor.span(3) == "3 gün" && DiskAdvisor.span(65) == "2 ay" && DiskAdvisor.since(800) == "2 yıldır"
              && DiskAdvisor.since(10) == "10 gündür" && DiskAdvisor.since(40) == "1 aydır")

        // Sahte ev klasöründe gerçek tarama
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("deskling-disk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("ev"), apps = root.appendingPathComponent("Uygulamalar")
        let mb = 1_048_576
        func file(_ path: String, _ size: Int, age: Double? = nil) {
            let url = home.appendingPathComponent(path)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data(count: size))
            if let age { try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age * 86_400)], ofItemAtPath: url.path) }
        }
        func dirAge(_ path: String, _ age: Double) {
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age * 86_400)], ofItemAtPath: home.appendingPathComponent(path).path)
        }
        func makeApp(_ name: String, _ id: String) {
            let c = apps.appendingPathComponent("\(name).app/Contents")
            try? fm.createDirectory(at: c.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            (["CFBundleIdentifier": id, "CFBundleName": name] as NSDictionary).write(to: c.appendingPathComponent("Info.plist"), atomically: true)
            fm.createFile(atPath: c.appendingPathComponent("MacOS/\(name)").path, contents: Data(count: 3 * mb))
        }
        file("Library/Caches/com.example.old/blob", 2 * mb, age: 30); dirAge("Library/Caches/com.example.old", 30)
        file("Library/Caches/com.example.run/blob", 2 * mb, age: 30); dirAge("Library/Caches/com.example.run", 30)
        file("Library/Caches/tiny/x", 1000, age: 30)
        file("Library/Logs/Eski/app.log", 2 * mb, age: 40); dirAge("Library/Logs/Eski", 40)
        file("Library/Application Support/Deskling/Halı Altı/gizli.bin", 5 * mb)
        file("Library/Developer/Xcode/DerivedData/Proje-abc/Build/x.o", 4 * mb, age: 60); dirAge("Library/Developer/Xcode/DerivedData/Proje-abc/Build", 60); dirAge("Library/Developer/Xcode/DerivedData/Proje-abc", 60)
        file("Downloads/Setup.dmg", 2 * mb, age: 20)
        file("Downloads/rapor.pdf", 2 * mb, age: 200)
        file("Downloads/not.txt", 100)
        file("Movies/film.mov", 3 * mb, age: 200)
        file("Desktop/kilitli.mov", 3 * mb)
        try? fm.setAttributes([.immutable: true], ofItemAtPath: home.appendingPathComponent("Desktop/kilitli.mov").path)
        file(".Trash/eski.zip", 2 * mb)
        makeApp("Eski", "com.example.eski")
        makeApp("Yeni", "com.example.yeni")
        makeApp("Apple", "com.apple.deneme")
        defer { try? fm.setAttributes([.immutable: false], ofItemAtPath: home.appendingPathComponent("Desktop/kilitli.mov").path) }

        var scanner = DiskScanner(home: home, appDirs: [apps])
        scanner.meta = { url in
            switch url.lastPathComponent {
            case "Eski.app": return FileMeta(lastUsed: Date().addingTimeInterval(-300 * 86_400), added: Date().addingTimeInterval(-900 * 86_400), useCount: 4)
            case "Yeni.app": return FileMeta(lastUsed: Date().addingTimeInterval(-86_400), added: nil, useCount: 30)
            default: return url.lastPathComponent == "rapor.pdf" ? FileMeta(lastUsed: Date().addingTimeInterval(-2 * 86_400)) : FileMeta()
            }
        }
        scanner.runningBundles = { ["com.example.run"] }
        scanner.protectedPaths = [home.appendingPathComponent("Library/Application Support/Deskling").path]
        scanner.largeThreshold = 2 * Int64(mb)
        // Sahte Docker: gerçek Docker'a asla bakılmaz.
        let dockerFake = """
        {"Images":[{"Containers":"0","Repository":"<none>","UniqueSize":"1.5GB","Size":"1.5GB"},{"Containers":"0","Repository":"eski","UniqueSize":"700MB"},{"Containers":"2","Repository":"postgres","UniqueSize":"600MB"}],
         "Containers":[{"State":"exited","Status":"Exited (0) 3 days ago","Size":"12MB"},{"State":"running","Status":"Up 2 hours","Size":"5MB"}],
         "Volumes":[{"Name":"proje_pgdata","Links":"0","Size":"800MB"},{"Name":"kullanilan","Links":"1","Size":"2GB"}],
         "BuildCache":[{"InUse":false,"Size":"2.1GB"},{"InUse":true,"Size":"300MB"},{"InUse":"true","Size":"1GB"}]}
        """
        scanner.dockerJSON = { dockerFake }
        file("Projeler/Api/Api.csproj", 10, age: 40)
        file("Projeler/Api/bin/Debug/api.dll", 2 * mb, age: 40); dirAge("Projeler/Api/bin/Debug", 40); dirAge("Projeler/Api/bin", 40)
        file("Projeler/Api/obj/project.assets.json", 2 * mb, age: 2)
        file("Projeler/Web/package.json", 10, age: 200); dirAge("Projeler/Web", 200)
        file("Projeler/Web/node_modules/lib/index.js", 2 * mb, age: 200); dirAge("Projeler/Web/node_modules/lib", 200); dirAge("Projeler/Web/node_modules", 200)
        file("Projeler/Bos/bin/x", 2 * mb, age: 90)   // .csproj yok: dokunulmaz
        file(".nuget/packages/newtonsoft/x.nupkg", 2 * mb, age: 30); dirAge(".nuget/packages/newtonsoft", 30); dirAge(".nuget/packages", 30)

        func find(_ items: [DiskItem], _ name: String) -> DiskItem? { items.first { $0.name == name || $0.url.lastPathComponent == name } }
        let caches = scanner.scan(.caches)
        check("eski önbellek bulunur ve silinebilir", find(caches, "com.example.old")?.verdict == .remove, caches.map(\.name).joined(separator: ","))
        check("açık uygulamanın önbelleği gözden geçir", find(caches, "com.example.run")?.verdict == .review)
        check("1 MB'tan küçükler listelenmez", find(caches, "tiny") == nil)
        check("boyut diskte kaplanan yerden okunur", (find(caches, "com.example.old")?.size ?? 0) >= Int64(2 * mb))
        check("eski günlük bulunur", scanner.scan(.logs).first?.verdict == .remove)
        let dev = scanner.scan(.developer)
        check("DerivedData projesi bulunur", find(dev, "DerivedData · Proje")?.verdict == .remove, dev.map(\.name).joined(separator: ","))
        check("Docker boyutları okunur", DevCleanup.size("661.4MB") == 661_400_000 && DevCleanup.size("24.58kB") == 24_580
              && DevCleanup.size("-1.463e+09B") == 0 && DevCleanup.size("0B") == 0 && DevCleanup.size("12MB (45%)") == 12_000_000)
        func dk(_ key: String) -> DiskItem? { dev.first { $0.url.absoluteString == "docker://" + key } }
        check("etiketsiz imajlar silinebilir", dk("images-dangling")?.verdict == .remove && dk("images-dangling")?.size == 1_500_000_000
              && dk("images-dangling")?.dockerArgs == ["image", "prune", "-f"])
        check("Docker derleme önbelleği silinebilir, kullanılan hariç", dk("build-cache")?.verdict == .remove && dk("build-cache")?.size == 2_100_000_000)
        check("kullanılmayan imajlar ve durmuş konteynerler gözden geçir", dk("images-unused")?.verdict == .review && dk("containers-stopped")?.verdict == .review
              && dk("containers-stopped")?.dockerCount == 1)
        check("bağlı olmayan birim gözden geçir, bağlı birim listelenmez", dk("volume-proje_pgdata")?.verdict == .review
              && dk("volume-proje_pgdata")?.dockerArgs == ["volume", "rm", "proje_pgdata"] && dk("volume-kullanilan") == nil)
        check("Docker öğesi kalıcı silindiğini söyler", dk("build-cache")?.reasons.contains("Kalıcı silinir, Çöp Kutusu'na gitmez") == true)
        check("eski .NET bin klasörü silinebilir", find(dev, "Api · bin")?.verdict == .remove, dev.map(\.name).joined(separator: ","))
        check("yeni derlenmiş obj gözden geçir", find(dev, "Api · obj")?.verdict == .review)
        check("eski projenin node_modules'ü silinebilir", find(dev, "Web · node_modules")?.verdict == .remove)
        check(".csproj olmayan klasörün bin'ine dokunulmaz", find(dev, "Bos · bin") == nil)
        check("NuGet paketleri bulunur", find(dev, "NuGet paketleri")?.verdict == .remove)
        let downloads = scanner.scan(.downloads)
        check("kurulum dosyası silinebilir", find(downloads, "Setup.dmg")?.verdict == .remove)
        check("iki gün önce açılan indirme gerekli", find(downloads, "rapor.pdf")?.verdict == .keep, find(downloads, "rapor.pdf")?.reasons.joined() ?? "yok")
        let appsFound = scanner.scan(.apps)
        check("eski uygulama silinebilir", find(appsFound, "Eski")?.verdict == .remove && find(appsFound, "Eski")?.bundleID == "com.example.eski")
        check("dün kullanılan uygulama gerekli", find(appsFound, "Yeni")?.verdict == .keep)
        check("Apple uygulaması korunur", find(appsFound, "Apple")?.verdict == .keep && find(appsFound, "Apple")?.canTrash == false)
        let large = scanner.scan(.large)
        check("büyük dosya bulunur, gözden geçir", find(large, "film.mov")?.verdict == .review, large.map(\.name).joined(separator: ","))
        check("kilitli dosya korunur", find(large, "kilitli.mov")?.canTrash == false)
        check("Çöp Kutusu ölçülür", scanner.scan(.trash).first.map { $0.size >= Int64(2 * mb) && !$0.canTrash } == true)
        let everything = DiskKind.allCases.flatMap { scanner.scan($0) }
        check("halının altı ve Deskling klasörü hiç listelenmez", !everything.contains { $0.url.path.contains("Deskling") })

        // Çöp Kutusu'na taşıma (sahte): yalnızca seçilen ve gerekli olmayanlar gider.
        let center = DiskCenter(scanner: scanner)
        center.readVolume = { VolumeInfo(total: 100 << 30, available: 40 << 30, free: 30 << 30) }
        let fakeTrash = root.appendingPathComponent("SahteÇöp")
        try? fm.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        var recycled: [URL] = []
        center.recycle = { urls, done in
            recycled += urls
            let moved = urls.compactMap { url -> URL? in
                let to = fakeTrash.appendingPathComponent(url.lastPathComponent)
                return (try? fm.moveItem(at: url, to: to)) != nil ? url : nil
            }
            done(moved, nil)
        }
        center.isRunning = { _ in false }
        var dockerRuns: [[String]] = []
        center.runDocker = { dockerRuns.append($0); return (true, "") }
        center.scan()
        let end = Date().addingTimeInterval(10)
        while center.scannedAt == nil, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check("tarama bitince en çok yer açılacak bölüm seçilir", center.scannedAt != nil && center.selectedKind != nil)
        check("silinebilir toplamı hesaplanır", center.totalRemovable >= Int64(13 * mb), DiskFormat.bytes(center.totalRemovable))
        center.selectRecommended()
        let keepIDs = Set(center.allItems.filter { $0.verdict != .remove }.map(\.id))
        check("önerilenler seçilir, gerekliler seçilmez", !center.selection.isEmpty && center.selection.isDisjoint(with: keepIDs))
        let yeni = center.allItems.first { $0.name == "Yeni" }!
        center.toggle(yeni)
        check("gerekli öğe seçilemez", !center.selection.contains(yeni.id))
        var finished = false
        center.moveToTrash(center.selectedItems + [yeni]) { finished = true }
        let end2 = Date().addingTimeInterval(5)
        while !finished, Date() < end2 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check("yalnızca silinebilirler Çöp Kutusu'na gider", !recycled.isEmpty && !recycled.contains(yeni.url)
              && recycled.allSatisfy { url in !keepIDs.contains(url.path) })
        check("taşınanlar listeden çıkar", center.allItems.allSatisfy { !recycled.contains($0.url) } && center.selection.isEmpty)
        check("taşınan dosya sahte çöpe gitti, gerçek çöpe değil", fm.fileExists(atPath: fakeTrash.appendingPathComponent("Setup.dmg").path)
              && !fm.fileExists(atPath: home.appendingPathComponent("Downloads/Setup.dmg").path))
        check("gerekli öğe yerinde kalır", fm.fileExists(atPath: yeni.url.path))
        check("Docker öğeleri Çöp Kutusu'na değil, docker komutuna gider", dockerRuns.contains(["image", "prune", "-f"]) && dockerRuns.contains(["builder", "prune", "-f"])
              && !dockerRuns.contains(["volume", "rm", "proje_pgdata"]) && !recycled.contains { !$0.isFileURL }, "\(dockerRuns)")
        check("taşınan bin klasörü sahte çöpe gitti", fm.fileExists(atPath: fakeTrash.appendingPathComponent("bin").path))
        check("bilgi notu Docker ve Çöp Kutusu'nu ayrı söyler", center.note?.contains("Docker'dan") == true && center.note?.contains("Çöp Kutusu boşaltılınca") == true && center.note?.contains("Taşınmadı: Yeni") == true, center.note ?? "")
        let eskiApp = DiskItem(url: apps.appendingPathComponent("X.app"), kind: .apps, name: "X", size: 1, lastUsed: ago(400), bundleID: "com.example.x")
        center.isRunning = { $0 == "com.example.x" }
        recycled = []
        var fin2 = false
        center.moveToTrash([judge(eskiApp)]) { fin2 = true }
        check("varsayılan DiskCenter Docker'ı çalıştırmaz", DiskCenter(scanner: scanner).runDocker(["version"]).0 == false
              && DiskScanner(home: home, appDirs: []).dockerJSON() == nil)
        check("taşıma anında açık olan uygulama taşınmaz", fin2 && recycled.isEmpty && center.note?.contains("açık") == true)

        // Bellek kuralları
        func mem(_ mb: UInt64, idle: Double?, front: Bool = false, audio: Bool = false, id: String = "com.example.m") -> AppMemory {
            var a = AppMemory(pid: 1, name: "M", bundleID: id, footprint: mb * 1_048_576)
            a.frontmost = front; a.playingAudio = audio
            a.lastActive = idle.map { now.addingTimeInterval(-$0 * 60) }
            return MemoryAdvisor.judge(a, now: now, selfID: "com.deskling.app")
        }
        check("uzun süredir arka plandaki ağır uygulama kapatılabilir", mem(900, idle: 120).verdict == .remove)
        check("öndeki uygulama gerekli", mem(900, idle: 120, front: true).verdict == .keep)
        check("ses çalan uygulama gerekli", mem(900, idle: 120, audio: true).verdict == .keep)
        check("az önce kullanılan gerekli", mem(900, idle: 3).verdict == .keep)
        check("hafif uygulama gerekli", mem(80, idle: 600).verdict == .keep)
        check("Deskling ve Finder asla kapatılmaz", mem(900, idle: 600, id: "com.deskling.app").verdict == .keep && mem(900, idle: 600, id: "com.apple.finder").verdict == .keep)
        check("Apple uygulaması en fazla gözden geçir", mem(900, idle: 600, id: "com.apple.mail").verdict == .review)
        check("arka plan süresi yazılır", mem(900, idle: 120).reasons.contains("2 saattir arka planda"), mem(900, idle: 120).reasons.joined(separator: "|"))

        let mc = MemoryCenter()
        mc.now = { now }
        var terminated: [pid_t] = []
        mc.terminate = { terminated.append($0); return true }
        var heavy = AppMemory(pid: 10, name: "Ağır", bundleID: "com.example.heavy", footprint: 2 << 30)
        heavy.lastActive = nil
        var front = AppMemory(pid: 11, name: "Ön", bundleID: "com.example.front", footprint: 2 << 30); front.frontmost = true
        mc.apply(stats: nil, apps: [front, heavy], playing: [])
        check("izleme başlamadıysa bilinmeyen süre ağır uygulamayı önerir", mc.suggested.map(\.pid) == [10])
        mc.quit(mc.apps)
        check("kapat yalnızca gerekli olmayanlara gider", terminated == [10] && mc.note?.contains("1 gerekli uygulamaya dokunulmadı") == true, mc.note ?? "")

        let s = MemoryStats.read()
        check("bellek sayaçları okunur", (s?.total ?? 0) > 0 && (s?.used ?? 0) > 0 && (s?.used ?? 0) <= (s?.total ?? 0))
        let live = MemoryCenter.liveApps()
        check("açık uygulamaların belleği okunur", !live.isEmpty && live.allSatisfy { $0.footprint > 0 }, "\(live.count)")
        check("disk bilgisi okunur", (VolumeInfo.read()?.total ?? 0) > 0)

        print(failures == 0 ? "DISK_GECTI" : "DISK_KALDI hata=\(failures)")
        return failures == 0 ? 0 : 1
    }
}

/// `--disk-report`: gerçek diskte yalnızca okuyarak uygulamalar, önbellekler, günlükler ve geliştirici bölümünü özetler.
/// Kişisel klasörlere (İndirilenler, Belgeler) bakmaz, hiçbir şeyi değiştirmez.
enum DiskReport {
    static func run() -> Int32 {
        let s = DiskScanner.live()
        for k in [DiskKind.apps, .caches, .logs, .developer] {
            let t0 = Date()
            let items = s.scan(k)
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            print("\n== \(k.title): \(items.count) öğe, \(DiskFormat.bytes(total)), \(String(format: "%.1f", Date().timeIntervalSince(t0))) sn")
            for v in DiskVerdict.allCases.reversed() {
                let l = items.filter { $0.verdict == v }
                print("   \(v.title): \(l.count) öğe, \(DiskFormat.bytes(l.reduce(0) { $0 + $1.size }))")
            }
            for i in items.prefix(6) { print("   - [\(i.verdict.title)] \(i.name) \(DiskFormat.bytes(i.size)) — \(i.reasons.joined(separator: " · "))") }
        }
        if let m = MemoryStats.read() { print("\n== Bellek: \(DiskFormat.bytes(Int64(m.used))) / \(DiskFormat.bytes(Int64(m.total))), baskı \(m.pressureTitle)") }
        let mc = MemoryCenter()
        mc.apply(stats: nil, apps: MemoryCenter.liveApps(), playing: AudioActivity.playingBundles() ?? [])
        for a in mc.apps.prefix(8) { print("   - [\(a.verdict.title)] \(a.name) \(DiskFormat.bytes(Int64(a.footprint))) — \(a.reasons.joined(separator: " · "))") }
        return 0
    }
}

/// `--disk-gallery <png>`: sahte verilerle Disk ve Bellek sayfalarının görüntüsü.
enum DiskGallery {
    @MainActor static func run(output: String) -> Int32 {
        let now = Date()
        func ago(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        let gb: Int64 = 1 << 30, mb: Int64 = 1 << 20
        func it(_ k: DiskKind, _ name: String, _ size: Int64, used: Double? = nil, mod: Double? = nil, count: Int? = nil, added: Double? = nil, ext: String = "") -> DiskItem {
            DiskAdvisor.judge(DiskItem(url: URL(fileURLWithPath: "/örnek/\(name)\(ext)"), kind: k, name: name, size: size, lastUsed: used.map(ago),
                                       added: added.map(ago), modified: mod.map(ago), useCount: count, bundleID: "com.example." + name), now: now)
        }
        let disk = DiskCenter(scanner: DiskScanner(home: URL(fileURLWithPath: "/örnek"), appDirs: []))
        disk.readVolume = { VolumeInfo(total: 494 * gb, available: 142 * gb, free: 120 * gb) }
        disk.refreshVolume()
        disk.load([
            .apps: [it(.apps, "Video Kurgu", 6 * gb, used: 300, count: 4, added: 700, ext: ".app"), it(.apps, "Kod Düzenleyici", 2 * gb, used: 0, count: 900, added: 600, ext: ".app"),
                    it(.apps, "Oyun", 9 * gb, used: 120, count: 20, added: 400, ext: ".app"), it(.apps, "Not Defteri", 500 * mb, added: 400, ext: ".app"),
                    it(.apps, "Tasarım", 3 * gb, used: 3, count: 150, added: 500, ext: ".app")],
            .caches: [it(.caches, "tarayıcı", 2 * gb, mod: 40), it(.caches, "paketler", 900 * mb, mod: 1), it(.caches, "müzik", 700 * mb, mod: 60)],
            .logs: [it(.logs, "Çökme raporları", 300 * mb, mod: 50)],
            .developer: [it(.developer, "DerivedData · Uygulama", 7 * gb, mod: 45), it(.developer, "Simülatör önbellekleri", 4 * gb, mod: 100)],
            .downloads: [it(.downloads, "Kurulum", 1 * gb, mod: 40, ext: ".dmg"), it(.downloads, "Sunum", 400 * mb, used: 2, ext: ".key"), it(.downloads, "Arşiv", 3 * gb, used: 500, ext: ".zip")],
            .large: [it(.large, "Tatil", 12 * gb, used: 400, ext: ".mov")],
            .trash: [DiskAdvisor.judge(DiskItem(url: URL(fileURLWithPath: "/örnek/.Trash"), kind: .trash, name: "Çöp Kutusu", size: 2 * gb), now: now)],
        ], at: now)
        disk.selectedKind = .apps
        disk.selectRecommended(in: .apps)

        let mem = MemoryCenter()
        mem.now = { now }
        func app(_ pid: pid_t, _ name: String, _ size: UInt64, idle: Double?, front: Bool = false, audio: Bool = false) -> AppMemory {
            var a = AppMemory(pid: pid, name: name, bundleID: "com.example.\(pid)", footprint: size << 20, processes: Int(pid % 7) + 1)
            a.frontmost = front; a.playingAudio = audio
            return a
        }
        mem.apply(stats: MemoryStats(total: 16 << 30, app: 7 << 30, wired: 2 << 30, compressed: 3 << 30, cached: 3 << 30, swapUsed: 1 << 30, pressure: 2),
                  apps: [app(1, "Tarayıcı", 3200, idle: nil), app(2, "Kod Düzenleyici", 2100, idle: nil, front: true),
                         app(3, "Müzik", 400, idle: nil, audio: true), app(4, "Not Defteri", 90, idle: nil)], playing: [])

        let view = HStack(alignment: .top, spacing: 0) {
            DiskPage(disk: disk, scrolls: false).frame(width: 500)
            Divider()
            MemoryPage(memory: mem, scrolls: false).frame(width: 500)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        try? png.write(to: URL(fileURLWithPath: output))
        print("yazıldı \(output)")
        return 0
    }
}

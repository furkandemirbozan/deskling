import AppKit

/// Diski tarar. Hiçbir şeyi silmez, değiştirmez; yalnızca okur.
/// Kökler ve kullanım bilgisi dışarıdan verilebilir; testler sahte bir ev klasöründe çalışır.
struct DiskScanner {
    var home: URL
    var appDirs: [URL]
    var meta: (URL) -> FileMeta = DiskScanner.spotlight
    var runningBundles: () -> Set<String> = DiskScanner.running
    /// Bunların içi ve kendisi korunur (Deskling'in klasörleri, halının altı…).
    var protectedPaths: [String] = []
    /// Çalışırken yeri değişebilen korunan klasörler (ör. klavye ses paketleri).
    var liveProtected: () -> [String] = { [] }
    var largeThreshold: Int64 = 500 * 1_048_576
    var minimumSize: Int64 = 1_048_576
    var now: () -> Date = Date.init
    /// `docker system df -v` JSON'u; Docker yoksa ya da çalışmıyorsa nil. Yalnızca `live()` gerçek Docker'a bakar.
    var dockerJSON: () -> String? = { nil }
    /// bin/obj ve node_modules aranacak klasörler; nil ise ev klasörünün doğrudan alt klasörleri.
    var projectRoots: [URL]? = nil

    static func live() -> DiskScanner {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var prot = [home.appendingPathComponent("Library/Application Support/Deskling").path]
        prot.append(Bundle.main.bundleURL.path)
        var s = DiskScanner(home: home, appDirs: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")],
                            protectedPaths: prot)
        s.dockerJSON = { DevCleanup.dockerJSON() }
        // Klavye ses paketleri hiçbir zaman silinmeye önerilmez; klasör panelden değiştirilse de.
        s.liveProtected = { [KeySoundCenter.currentFolder().standardizedFileURL.path] }
        return s
    }

    func scan(_ kind: DiskKind, cancelled: () -> Bool = { false }) -> [DiskItem] {
        let running = runningBundles()
        var items: [DiskItem]
        switch kind {
        case .apps: items = apps(running: running, cancelled: cancelled)
        case .caches: items = children(of: lib("Caches"), kind: .caches, running: running, cancelled: cancelled)
        case .logs:
            items = children(of: lib("Logs"), kind: .logs, running: running, cancelled: cancelled)
        case .developer: items = developer(cancelled: cancelled)
        case .downloads: items = children(of: home.appendingPathComponent("Downloads"), kind: .downloads, running: running, cancelled: cancelled, useMeta: true)
        case .large: items = large(cancelled: cancelled)
        case .backups: items = backups(cancelled: cancelled)
        case .trash:
            let t = home.appendingPathComponent(".Trash")
            let s = Self.size(of: t, cancelled: cancelled)
            items = s > 0 ? [DiskItem(url: t, kind: .trash, name: "Çöp Kutusu", size: s)] : []
        }
        let n = now()
        return items.filter { $0.size >= minimumSize || $0.kind == .apps || ($0.isDocker && $0.dockerCount > 0 && $0.size > 0) }
            .map { DiskAdvisor.judge($0, now: n) }
            .sorted(by: DiskAdvisor.sort)
    }

    private func lib(_ p: String) -> URL { home.appendingPathComponent("Library").appendingPathComponent(p) }

    /// Korunan klasörün kendisi ya da içinde: taramada hiç bakılmaz.
    func isProtected(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let p = url.standardizedFileURL.path
        return (protectedPaths + liveProtected()).contains { p == $0 || p.hasPrefix($0 + "/") }
    }

    /// Korunan bir şeyi içeren klasör de Çöp Kutusu'na gidemez (ör. paket klasörünü taşıyan Belgeler).
    func touchesProtected(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let p = url.standardizedFileURL.path
        return isProtected(url) || (protectedPaths + liveProtected()).contains { $0.hasPrefix(p + "/") }
    }

    // MARK: Bölümler

    private func apps(running: Set<String>, cancelled: () -> Bool) -> [DiskItem] {
        var out: [DiskItem] = []
        for dir in appDirs {
            for url in list(dir) where url.pathExtension == "app" {
                if cancelled() { break }
                let b = Bundle(url: url)
                let id = b?.bundleIdentifier
                let m = meta(url)
                let v = try? url.resourceValues(forKeys: [.creationDateKey, .addedToDirectoryDateKey])
                var item = DiskItem(url: url, kind: .apps, name: url.deletingPathExtension().lastPathComponent,
                                    size: Self.size(of: url, cancelled: cancelled),
                                    lastUsed: m.lastUsed, added: m.added ?? v?.addedToDirectoryDate ?? v?.creationDate,
                                    useCount: m.useCount, bundleID: id)
                item.running = id.map(running.contains) ?? false
                item.protected = touchesProtected(url) || id?.hasPrefix("com.apple.") == true || Self.isLocked(url)
                out.append(item)
            }
        }
        return out
    }

    /// Bir klasörün doğrudan altındakiler, her biri bir öğe.
    private func children(of dir: URL, kind: DiskKind, running: Set<String>, cancelled: () -> Bool, useMeta: Bool = false) -> [DiskItem] {
        var out: [DiskItem] = []
        for url in list(dir) {
            if cancelled() { break }
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey, .creationDateKey])
            let m = useMeta ? meta(url) : FileMeta()
            let name = url.lastPathComponent
            // Önbellek klasörleri çoğunlukla uygulamanın paket kimliğiyle adlandırılır.
            let owner = name.contains(".") ? name : nil
            var item = DiskItem(url: url, kind: kind, name: name, size: Self.size(of: url, cancelled: cancelled),
                                lastUsed: m.lastUsed, added: m.added ?? v?.addedToDirectoryDate ?? v?.creationDate,
                                modified: Self.newestChange(in: url, fallback: v?.contentModificationDate), bundleID: owner)
            item.running = owner.map(running.contains) ?? false
            item.protected = touchesProtected(url) || Self.isLocked(url)
            out.append(item)
        }
        return out
    }

    private func developer(cancelled: () -> Bool) -> [DiskItem] {
        var out: [DiskItem] = []
        let derived = lib("Developer/Xcode/DerivedData")
        for url in list(derived) {
            if cancelled() { break }
            out.append(single(url, name: "DerivedData · " + url.lastPathComponent.components(separatedBy: "-").first!, cancelled: cancelled))
        }
        let singles: [(String, String)] = [
            ("Library/Developer/Xcode/Archives", "Xcode arşivleri"),
            ("Library/Developer/Xcode/iOS DeviceSupport", "iOS cihaz destek dosyaları"),
            ("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS cihaz destek dosyaları"),
            ("Library/Developer/CoreSimulator/Caches", "Simülatör önbellekleri"),
            (".npm/_cacache", "npm önbelleği"),
            (".nuget/packages", "NuGet paketleri"),
            (".local/share/NuGet/http-cache", "NuGet indirme önbelleği"),
            (".local/share/NuGet/v3-cache", "NuGet v3 önbelleği"),
            ("Library/pnpm/store", "pnpm deposu"),
            (".yarn/berry/cache", "Yarn önbelleği"),
            (".gradle/caches", "Gradle önbelleği"),
            (".cocoapods/repos", "CocoaPods depoları"),
            (".cache", "Komut satırı araç önbellekleri"),
        ]
        for (p, name) in singles {
            if cancelled() { break }
            let url = home.appendingPathComponent(p)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            out.append(single(url, name: name, cancelled: cancelled))
        }
        if !cancelled() {
            let roots = projectRoots ?? list(home).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && !DevCleanup.skipNames.contains($0.lastPathComponent)
            }
            out += DevCleanup.projectLeftovers(roots: roots, isProtected: isProtected, cancelled: cancelled)
        }
        if !cancelled(), let json = dockerJSON() { out += DevCleanup.dockerItems(json) }
        return out
    }

    private func single(_ url: URL, name: String, cancelled: () -> Bool) -> DiskItem {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        var item = DiskItem(url: url, kind: .developer, name: name, size: Self.size(of: url, cancelled: cancelled),
                            modified: Self.newestChange(in: url, fallback: v?.contentModificationDate))
        item.protected = touchesProtected(url)
        return item
    }

    private func large(cancelled: () -> Bool) -> [DiskItem] {
        var out: [DiskItem] = []
        let roots = ["Documents", "Desktop", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                if cancelled() { return out }
                if isProtected(url) { e.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                var size: Int64 = 0
                if v.isPackage == true {
                    e.skipDescendants()
                    size = Self.size(of: url, cancelled: cancelled)
                } else if v.isRegularFile == true {
                    size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                } else { continue }
                guard size >= largeThreshold else { continue }
                let m = meta(url)
                var item = DiskItem(url: url, kind: .large, name: url.lastPathComponent, size: size,
                                    lastUsed: m.lastUsed, added: m.added, modified: v.contentModificationDate)
                item.protected = Self.isLocked(url) || DiskAdvisor.libraryExtensions.contains(url.pathExtension.lowercased())
                out.append(item)
            }
        }
        return out
    }

    private func backups(cancelled: () -> Bool) -> [DiskItem] {
        var out = list(lib("Application Support/MobileSync/Backup")).map { url -> DiskItem in
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return DiskItem(url: url, kind: .backups, name: Self.backupName(url), size: Self.size(of: url, cancelled: cancelled),
                            modified: v?.contentModificationDate)
        }
        if let newest = out.indices.max(by: { (out[$0].modified ?? .distantPast) < (out[$1].modified ?? .distantPast) }) {
            out[newest].newest = true
        }
        return out
    }

    static func backupName(_ url: URL) -> String {
        if let d = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")),
           let n = d["Device Name"] as? String ?? d["Display Name"] as? String { return n + " yedeği" }
        return "Yedek " + url.lastPathComponent.prefix(8)
    }

    // MARK: Yardımcılar

    private func list(_ dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { !isProtected($0) }
    }

    /// Bir klasörün diskte kapladığı yer (gerçekten ayrılan bloklar).
    static func size(of url: URL, cancelled: () -> Bool = { false }) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var n = 0
        for case let f as URL in e {
            n += 1
            if n & 1023 == 0, cancelled() { break }
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Klasörün içinde en son ne zaman bir şey değişti? (ilk iki kat, hızlı olsun diye)
    static func newestChange(in url: URL, fallback: Date?) -> Date? {
        var best = fallback
        let fm = FileManager.default
        let first = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in first.prefix(400) {
            if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > (best ?? .distantPast) { best = d }
        }
        return best
    }

    static func isLocked(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable) == true
    }

    static func spotlight(_ url: URL) -> FileMeta {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return FileMeta() }
        let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue
        return FileMeta(lastUsed: used, added: added, useCount: count)
    }

    static func running() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

/// Disk sekmesinin durumu. Tarama yalnızca istenince ve arka planda yapılır.
final class DiskCenter: ObservableObject {
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var items: [DiskKind: [DiskItem]] = [:]
    @Published private(set) var scanning: DiskKind?
    @Published private(set) var scannedAt: Date?
    @Published private(set) var working = false
    @Published var selectedKind: DiskKind?
    @Published var selection: Set<String> = []
    @Published var note: String?

    var scanner: DiskScanner
    var readVolume: () -> VolumeInfo? = { VolumeInfo.read() }
    /// Gerçekte Finder'ın yaptığı gibi Çöp Kutusu'na taşır (gerekirse yönetici izni sorar). Asla kalıcı silmez.
    var recycle: ([URL], @escaping ([URL], Error?) -> Void) -> Void = { urls, done in
        NSWorkspace.shared.recycle(urls) { moved, err in done(Array(moved.keys), err) }
    }
    var reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    var isRunning: (String) -> Bool = { id in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
    /// Docker temizliği; kalıcıdır, onay arayüzde alınır. Yalnızca `live()` gerçek Docker'ı çalıştırır.
    var runDocker: ([String]) -> (Bool, String) = { _ in (false, "Docker temizliği kapalı") }

    static func live() -> DiskCenter {
        let c = DiskCenter(scanner: .live())
        c.runDocker = { DevCleanup.runDocker($0) }
        return c
    }

    private let queue = DispatchQueue(label: "deskling.disk", qos: .utility)
    private var generation = 0
    /// Arka plandaki taramanın okuduğu güncel tarama numarası.
    private let current = Counter()

    private final class Counter {
        private let lock = NSLock()
        private var v = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return v }
        func set(_ n: Int) { lock.lock(); v = n; lock.unlock() }
    }

    init(scanner: DiskScanner) {
        self.scanner = scanner
    }

    var scanned: Bool { scannedAt != nil }
    var kinds: [DiskKind] { DiskKind.allCases.filter { (items[$0]?.isEmpty == false) } }

    func total(_ k: DiskKind) -> Int64 { items[k]?.reduce(0) { $0 + $1.size } ?? 0 }
    func removable(_ k: DiskKind) -> Int64 { items[k]?.filter { $0.verdict == .remove && $0.canTrash }.reduce(0) { $0 + $1.size } ?? 0 }
    var scannedTotal: Int64 { DiskKind.allCases.reduce(0) { $0 + total($1) } }
    var totalRemovable: Int64 { DiskKind.allCases.reduce(0) { $0 + removable($1) } }
    var allItems: [DiskItem] { DiskKind.allCases.flatMap { items[$0] ?? [] } }
    var selectedItems: [DiskItem] { allItems.filter { selection.contains($0.id) && $0.canTrash } }

    func refreshVolume() { volume = readVolume() }

    /// Önizleme ve testler için hazır sonuç yükler.
    func load(_ found: [DiskKind: [DiskItem]], at date: Date = Date()) {
        items = found
        scannedAt = date
        scanning = nil
        if selectedKind == nil { selectedKind = kinds.max { removable($0) < removable($1) } }
    }

    func scan() {
        generation += 1
        let gen = generation
        current.set(gen)
        let current = self.current
        refreshVolume()
        items = [:]
        selection = []
        note = nil
        scannedAt = nil
        let scanner = self.scanner
        queue.async { [weak self] in
            for k in DiskKind.allCases {
                let stop = { current.value != gen }
                DispatchQueue.main.async { if self?.generation == gen { self?.scanning = k } }
                let found = scanner.scan(k, cancelled: stop)
                if stop() { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == gen else { return }
                    self.items[k] = found
                }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.scanning = nil
                self.scannedAt = Date()
                if self.selectedKind == nil { self.selectedKind = self.kinds.max { self.removable($0) < self.removable($1) } }
            }
        }
    }

    func cancel() {
        generation += 1
        current.set(generation)
        scanning = nil
    }

    func selectRecommended(in kind: DiskKind? = nil) {
        let pool = kind.map { items[$0] ?? [] } ?? allItems
        selection.formUnion(pool.filter { $0.verdict == .remove && $0.canTrash }.map(\.id))
    }

    func toggle(_ item: DiskItem) {
        guard item.canTrash else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func show(_ list: [DiskItem]) { reveal(list.filter { !$0.isDocker }.map(\.url)) }

    /// Geliştirici bölümünde güvenle silinebilenler (tek tıkla temizlik).
    var developerCleanup: [DiskItem] { (items[.developer] ?? []).filter { $0.verdict == .remove && $0.canTrash } }

    /// Seçilenleri Çöp Kutusu'na taşır. Gerekli, korunan ya da şu an açık uygulamalar asla taşınmaz.
    func moveToTrash(_ list: [DiskItem], done: (() -> Void)? = nil) {
        var refused: [String] = []
        let ok = list.filter { item in
            guard item.canTrash else { refused.append(item.name); return false }
            if item.kind == .apps, let id = item.bundleID, isRunning(id) { refused.append(item.name + " (açık)"); return false }
            return !scanner.touchesProtected(item.url)
        }
        let docker = ok.filter(\.isDocker)
        let files = ok.filter { !$0.isDocker }
        guard !ok.isEmpty else {
            note = refused.isEmpty ? nil : "Taşınmadı: " + refused.joined(separator: ", ")
            done?()
            return
        }
        working = true
        let runDocker = self.runDocker
        let finishFiles: ([URL], Error?, [DiskItem], [String]) -> Void = { [weak self] moved, err, dockerGone, dockerErrors in
            DispatchQueue.main.async {
                guard let self else { return }
                let movedPaths = Set(moved.map { $0.standardizedFileURL.path })
                let gone = files.filter { movedPaths.contains($0.url.standardizedFileURL.path) } + dockerGone
                let goneIDs = Set(gone.map(\.id))
                for k in DiskKind.allCases { self.items[k]?.removeAll { goneIDs.contains($0.id) } }
                self.selection.subtract(goneIDs)
                var parts: [String] = []
                let trashed = gone.filter { !$0.isDocker }
                if !dockerGone.isEmpty {
                    parts.append("Docker'dan \(DiskFormat.bytes(dockerGone.reduce(0) { $0 + $1.size })) silindi.")
                }
                if !trashed.isEmpty {
                    parts.append("\(trashed.count) öğe (\(DiskFormat.bytes(trashed.reduce(0) { $0 + $1.size }))) Çöp Kutusu'na taşındı. Yer, Çöp Kutusu boşaltılınca açılır; o zamana kadar geri alabilirsin.")
                    // Çöp Kutusu bölümünü arka planda güncelle.
                    let scanner = self.scanner
                    self.queue.async {
                        let trash = scanner.scan(.trash)
                        DispatchQueue.main.async { self.items[.trash] = trash }
                    }
                }
                let failed = files.count - trashed.count
                if failed > 0 { parts.append("\(failed) öğe taşınamadı" + (err.map { ": " + $0.localizedDescription } ?? ".")) }
                if !dockerErrors.isEmpty { parts.append("Docker: " + dockerErrors.joined(separator: "; ")) }
                if !refused.isEmpty { parts.append("Taşınmadı: " + refused.joined(separator: ", ")) }
                self.note = parts.joined(separator: " ")
                self.working = false
                self.refreshVolume()
                done?()
            }
        }
        // Önce Docker (kalıcı, arka planda), sonra dosyalar (Çöp Kutusu'na).
        queue.async { [weak self] in
            var dockerGone: [DiskItem] = [], dockerErrors: [String] = []
            for d in docker {
                let (ok, msg) = runDocker(d.dockerArgs ?? [])
                if ok { dockerGone.append(d) } else { dockerErrors.append("\(d.name): \(msg)") }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if files.isEmpty { finishFiles([], nil, dockerGone, dockerErrors); return }
                self.recycle(files.map(\.url)) { moved, err in finishFiles(moved, err, dockerGone, dockerErrors) }
            }
        }
    }
}

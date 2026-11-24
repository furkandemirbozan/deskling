import Foundation

/// Geliştirme yaparken diski sessizce dolduranlar: Docker artıkları, .NET bin/obj klasörleri, eski node_modules.
enum DevCleanup {

    // MARK: Docker

    /// `docker system df -v` çıktısından temizlenebilir parçaları çıkarır.
    /// Docker'ın kendi verisi Çöp Kutusu'na taşınamaz; bu öğeler silinince kalıcı olarak gider.
    static func dockerItems(_ json: String, now: Date = Date()) -> [DiskItem] {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [DiskItem] = []
        func item(_ key: String, _ name: String, _ size: Int64, _ args: [String], count: Int) -> DiskItem? {
            guard size > 0 || count > 0 else { return nil }
            var i = DiskItem(url: URL(string: "docker://\(key)")!, kind: .developer, name: name, size: max(0, size))
            i.dockerArgs = args
            i.dockerCount = count
            return i
        }
        let images = (o["Images"] as? [[String: Any]]) ?? []
        let unused = images.filter { (($0["Containers"] as? String) ?? "0") == "0" }
        let dangling = unused.filter { (($0["Repository"] as? String) ?? "") == "<none>" }
        let tagged = unused.filter { (($0["Repository"] as? String) ?? "") != "<none>" }
        func imgSize(_ l: [[String: Any]]) -> Int64 { l.reduce(0) { $0 + size(($1["UniqueSize"] as? String) ?? ($1["Size"] as? String) ?? "0B") } }
        if let i = item("images-dangling", "Docker · etiketsiz imajlar", imgSize(dangling), ["image", "prune", "-f"], count: dangling.count) { out.append(i) }
        if !tagged.isEmpty, let i = item("images-unused", "Docker · kullanılmayan imajlar", imgSize(tagged), ["image", "prune", "-a", "-f"], count: tagged.count) {
            out.append(i)
        }

        let containers = (o["Containers"] as? [[String: Any]]) ?? []
        let stopped = containers.filter { c in
            let state = ((c["State"] as? String) ?? "").lowercased()
            let status = ((c["Status"] as? String) ?? "").lowercased()
            return state == "exited" || state == "created" || status.hasPrefix("exited") || status.hasPrefix("created")
        }
        if let i = item("containers-stopped", "Docker · durmuş konteynerler", stopped.reduce(0) { $0 + size(($1["Size"] as? String) ?? "0B") },
                        ["container", "prune", "-f"], count: stopped.count) { out.append(i) }

        let cache = (o["BuildCache"] as? [[String: Any]]) ?? []
        let idle = cache.filter { !truthy($0["InUse"]) }
        if let i = item("build-cache", "Docker · derleme önbelleği", idle.reduce(0) { $0 + size(($1["Size"] as? String) ?? "0B") },
                        ["builder", "prune", "-f"], count: idle.count) { out.append(i) }

        // Birimler veri taşır: her biri ayrı gösterilir ve tek tek silinir.
        for v in (o["Volumes"] as? [[String: Any]]) ?? [] where ((v["Links"] as? String) ?? "1") == "0" {
            guard let name = v["Name"] as? String else { continue }
            let short = name.count > 24 && name.allSatisfy(\.isHexDigit) ? String(name.prefix(12)) + "…" : name
            if var i = item("volume-\(name)", "Docker birimi · \(short)", size((v["Size"] as? String) ?? "0B"), ["volume", "rm", name], count: 1) {
                i.dockerVolume = true
                out.append(i)
            }
        }
        return out
    }

    /// JSON'da true, 1 ya da "true" gelebilir.
    static func truthy(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["true", "1", "yes"].contains(s.lowercased()) }
        return false
    }

    /// "661.4MB", "24.58kB", "1.2GB", "0B", "-1.4e+09B" → bayt (Docker 1000'lik birim kullanır).
    static func size(_ s: String) -> Int64 {
        let t = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (u, m) in units where t.hasSuffix(u) {
            guard let n = Double(t.dropLast(u.count)) else { return 0 }
            return max(0, Int64(n * m))
        }
        return 0
    }

    static func dockerJSON(binary: String? = DockerService.binary) -> String? {
        guard let binary, let r = Shell.run(binary, ["system", "df", "-v", "--format", "{{json .}}"], timeout: 15), r.status == 0 else { return nil }
        return r.out
    }

    static func runDocker(_ args: [String], binary: String? = DockerService.binary) -> (Bool, String) {
        guard let binary else { return (false, "Docker bulunamadı") }
        guard let r = Shell.run(binary, args, timeout: 120) else { return (false, "Docker komutu çalıştırılamadı") }
        return (r.status == 0, r.status == 0 ? r.out : r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Proje klasörleri

    static let skipNames: Set<String> = ["node_modules", ".git", "Library", "Applications", "Pods", ".build", "DerivedData", "bin", "obj",
                                         "Music", "Movies", "Pictures", ".Trash", "vendor"]

    /// Proje klasörlerinde yeniden derlenince oluşan klasörler: .NET bin/obj, node_modules.
    static func projectLeftovers(roots: [URL], maxDepth: Int = 6, isProtected: (URL) -> Bool, cancelled: () -> Bool) -> [DiskItem] {
        var out: [DiskItem] = []
        let fm = FileManager.default
        func walk(_ dir: URL, _ depth: Int) {
            guard depth <= maxDepth, !cancelled(), !isProtected(dir) else { return }
            guard let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                                                         options: [.skipsHiddenFiles]) else { return }
            let names = Set(kids.map(\.lastPathComponent))
            let dotnet = kids.contains { ["csproj", "fsproj", "vbproj"].contains($0.pathExtension) }
            let node = names.contains("package.json")
            let project = dir.lastPathComponent
            if dotnet {
                for leftover in ["bin", "obj"] where names.contains(leftover) {
                    out.append(leftoverItem(dir.appendingPathComponent(leftover), name: "\(project) · \(leftover)", cancelled: cancelled))
                }
            }
            if node, names.contains("node_modules") {
                var i = leftoverItem(dir.appendingPathComponent("node_modules"), name: "\(project) · node_modules", cancelled: cancelled)
                // node_modules'ün içi kurulumda değişmez; projenin kendisine en son ne zaman dokunulduğuna bakılır.
                i.modified = DiskScanner.newestChange(in: dir, fallback: i.modified)
                out.append(i)
            }
            for k in kids {
                let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
                guard v?.isDirectory == true, v?.isPackage != true, v?.isSymbolicLink != true, !skipNames.contains(k.lastPathComponent) else { continue }
                walk(k, depth + 1)
            }
        }
        for r in roots { walk(r, 0) }
        return out.filter { $0.size > 0 }
    }

    private static func leftoverItem(_ url: URL, name: String, cancelled: () -> Bool) -> DiskItem {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        var i = DiskItem(url: url, kind: .developer, name: name, size: DiskScanner.size(of: url, cancelled: cancelled),
                         modified: DiskScanner.newestChange(in: url, fallback: v?.contentModificationDate))
        i.projectLeftover = true
        return i
    }
}

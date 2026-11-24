import AppKit
import Darwin

/// Belleğin anlık dağılımı (Etkinlik Monitörü'nün kullandığı aynı sayaçlar).
struct MemoryStats: Equatable {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var swapUsed: UInt64
    /// 1 normal, 2 uyarı, 4 kritik
    var pressure: Int

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    var pressureTitle: String {
        switch pressure {
        case 4: return "Kritik"
        case 2: return "Yüksek"
        default: return usedFraction > 0.85 ? "Dolu ama yönetiliyor" : "Normal"
        }
    }

    static func read() -> MemoryStats? {
        var s = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let inner = UInt64(s.internal_page_count), purgeable = UInt64(s.purgeable_count)
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0)
        return MemoryStats(total: ProcessInfo.processInfo.physicalMemory,
                           app: (inner > purgeable ? inner - purgeable : 0) * page,
                           wired: UInt64(s.wire_count) * page,
                           compressed: UInt64(s.compressor_page_count) * page,
                           cached: (UInt64(s.external_page_count) + purgeable) * page,
                           swapUsed: swap.xsu_used,
                           pressure: Int(level))
    }
}

/// Açık bir uygulama ve yardımcı süreçleriyle birlikte kullandığı bellek.
struct AppMemory: Identifiable, Equatable {
    let pid: pid_t
    var name: String
    var bundleID: String?
    var footprint: UInt64
    var processes: Int = 1
    var frontmost = false
    var hidden = false
    var playingAudio = false
    /// En son öne geldiği an; bilinmiyorsa Deskling'in izlemeye başladığı an.
    var lastActive: Date?
    /// `lastActive` gerçek değil, izlemenin başladığı an: süre "en az" bu kadar.
    var lastActiveIsLowerBound = false
    var verdict: DiskVerdict = .keep
    var reasons: [String] = []
    var id: pid_t { pid }
}

/// Hangi uygulamanın kapatılması belleği gerçekten rahatlatır?
///
/// Ölçütler: ne kadar bellek kullandığı, ne zamandır arka planda beklediği, şu an ses çalıp çalmadığı,
/// öndeki uygulama olup olmadığı. Öndeki, ses çalan, Deskling ve Finder asla kapatılmaya önerilmez.
enum MemoryAdvisor {
    static let heavy: UInt64 = 300 * 1_048_576
    static let light: UInt64 = 150 * 1_048_576
    static let idleLong: TimeInterval = 30 * 60
    static let idleShort: TimeInterval = 10 * 60
    static let neverQuit: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow"]

    static func judge(_ a: AppMemory, now: Date, selfID: String?) -> AppMemory {
        var x = a
        var r: [String] = []
        let idle = a.lastActive.map { now.timeIntervalSince($0) }
        if a.bundleID == selfID || a.bundleID.map(neverQuit.contains) == true {
            x.verdict = .keep; r.append("Sistem için gerekli")
        } else if a.frontmost {
            x.verdict = .keep; r.append("Şu an kullanıyorsun")
        } else if a.playingAudio {
            x.verdict = .keep; r.append("Şu an ses çalıyor")
        } else if let idle, idle < idleShort {
            x.verdict = .keep; r.append("Az önce kullanıldı")
        } else if a.footprint < light {
            x.verdict = .keep; r.append("Az bellek kullanıyor")
        } else if a.footprint >= heavy, (idle ?? .infinity) >= idleLong {
            // Apple'ın bildirim için açık tutulan uygulamaları en fazla "gözden geçir".
            x.verdict = a.bundleID?.hasPrefix("com.apple.") == true ? .review : .remove
            r.append("Çok bellek kullanıyor")
        } else {
            x.verdict = .review
        }
        if !a.frontmost, let idle, idle >= 60 { r.append((a.lastActiveIsLowerBound ? "en az " : "") + "\(minutes(idle)) arka planda") }
        if a.processes > 1 { r.append("\(a.processes) süreç") }
        x.reasons = r
        return x
    }

    static func minutes(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        if m < 60 { return "\(max(m, 1)) dakikadır" }
        let h = m / 60
        return h < 24 ? "\(h) saattir" : "\(h / 24) gündür"
    }
}

/// Bellek sekmesinin durumu: sayaçlar, uygulamaların bellek kullanımı ve kapatma.
final class MemoryCenter: ObservableObject {
    @Published private(set) var stats: MemoryStats?
    @Published private(set) var apps: [AppMemory] = []
    @Published private(set) var purging = false
    @Published var note: String?

    var readStats: () -> MemoryStats? = MemoryStats.read
    var listApps: () -> [AppMemory] = MemoryCenter.liveApps
    var playing: () -> Set<String> = { AudioActivity.playingBundles() ?? [] }
    var terminate: (pid_t) -> Bool = { NSRunningApplication(processIdentifier: $0)?.terminate() ?? false }
    var now: () -> Date = Date.init

    private var lastActive: [pid_t: Date] = [:]
    private var trackingSince: Date?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var views = 0
    private let queue = DispatchQueue(label: "deskling.memory", qos: .utility)

    /// Hangi uygulamanın en son ne zaman öne geldiğini izlemeye başlar (uygulama açılınca bir kez).
    func startTracking() {
        guard observer == nil else { return }
        trackingSince = now()
        if let f = NSWorkspace.shared.frontmostApplication { lastActive[f.processIdentifier] = now() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            // Öne gelen de, arkaya düşen de "şimdi" kullanılmış sayılır.
            if let f = self.apps.first(where: \.frontmost) { self.lastActive[f.pid] = self.now() }
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.lastActive[app.processIdentifier] = self.now()
            }
        }
    }

    func activate() {
        views += 1
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func deactivate() {
        views = max(0, views - 1)
        guard views == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let read = readStats, list = listApps, playing = self.playing
        queue.async { [weak self] in
            let s = read()
            let a = list()
            let p = playing()
            DispatchQueue.main.async { self?.apply(stats: s, apps: a, playing: p) }
        }
    }

    func apply(stats s: MemoryStats?, apps raw: [AppMemory], playing: Set<String>) {
        stats = s
        let n = now()
        let selfID = Bundle.main.bundleIdentifier
        apps = raw.map { a in
            var a = a
            if a.frontmost { lastActive[a.pid] = n }
            a.lastActive = lastActive[a.pid] ?? trackingSince
            a.lastActiveIsLowerBound = lastActive[a.pid] == nil
            if let b = a.bundleID { a.playingAudio = playing.contains { $0 == b || $0.hasPrefix(b + ".") } }
            return MemoryAdvisor.judge(a, now: n, selfID: selfID)
        }
        .sorted { $0.verdict != $1.verdict ? $0.verdict > $1.verdict : $0.footprint > $1.footprint }
    }

    var suggested: [AppMemory] { apps.filter { $0.verdict == .remove } }
    var suggestedBytes: UInt64 { suggested.reduce(0) { $0 + $1.footprint } }

    /// Uygulamayı nazikçe kapatır (kaydedilmemiş belge varsa uygulama kendisi sorar). Zorla kapatmaz.
    func quit(_ list: [AppMemory]) {
        let safe = list.filter { $0.verdict != .keep }
        let before = stats?.free ?? 0
        var asked = 0
        for a in safe where terminate(a.pid) { asked += 1 }
        let skipped = list.count - safe.count
        note = asked == 0 ? "Kapatılacak uygulama yok." :
            "\(asked) uygulamaya kapanması söylendi" + (skipped > 0 ? "; \(skipped) gerekli uygulamaya dokunulmadı." : ".")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let after = self.stats?.free ?? 0
                if asked > 0, after > before { self.note = (self.note ?? "") + " Yaklaşık \(DiskFormat.bytes(Int64(after - before))) bellek boşaldı." }
            }
        }
    }

    /// macOS'un `purge` aracıyla disk önbelleğini boşaltır. Yönetici parolasını macOS kendi penceresinde sorar.
    func purge() {
        guard !purging else { return }
        purging = true
        let before = readStats()?.free ?? 0
        queue.async { [weak self] in
            var err: NSDictionary?
            NSAppleScript(source: "do shell script \"/usr/sbin/purge\" with administrator privileges")?.executeAndReturnError(&err)
            let after = MemoryStats.read()?.free ?? 0
            DispatchQueue.main.async {
                guard let self else { return }
                self.purging = false
                if let err, (err[NSAppleScript.errorNumber] as? Int) == -128 { self.note = "Vazgeçildi."; return }
                if let err { self.note = "Önbellek boşaltılamadı: \((err[NSAppleScript.errorMessage] as? String) ?? "bilinmeyen hata")"; return }
                self.note = after > before ? "Önbellek boşaltıldı; \(DiskFormat.bytes(Int64(after - before))) boş bellek açıldı. macOS gerektikçe yeniden dolduracak."
                                           : "Önbellek boşaltıldı."
                self.refresh()
            }
        }
    }

    // MARK: Gerçek süreçler

    /// Normal uygulamaları ve yardımcı süreçlerini (tarayıcı sekmeleri gibi) toplar.
    static func liveApps() -> [AppMemory] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var byPid: [pid_t: AppMemory] = [:]
        var bundlePaths: [(String, pid_t)] = []
        for app in running {
            let pid = app.processIdentifier
            byPid[pid] = AppMemory(pid: pid, name: app.localizedName ?? app.bundleIdentifier ?? "?", bundleID: app.bundleIdentifier,
                                   footprint: 0, processes: 0, frontmost: app.isActive, hidden: app.isHidden)
            if let p = app.bundleURL?.path { bundlePaths.append((p + "/", pid)) }
        }
        for pid in allPids() {
            guard let fp = footprint(pid) else { continue }
            var owner: pid_t? = byPid[pid] != nil ? pid : nil
            if owner == nil, let r = responsible(pid), byPid[r] != nil { owner = r }
            if owner == nil, let path = path(pid) { owner = bundlePaths.first { path.hasPrefix($0.0) }?.1 }
            guard let o = owner else { continue }
            byPid[o]?.footprint += fp
            byPid[o]?.processes += 1
        }
        return byPid.values.filter { $0.footprint > 0 }
    }

    static func allPids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = buf.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        return Array(buf.prefix(Int(max(0, got)))).filter { $0 > 0 }
    }

    static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    private typealias Responsible = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: Responsible? = {
        guard let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(f, to: Responsible.self)
    }()

    /// Safari'nin sekmeleri gibi sistem yolunda çalışan yardımcıların sahibi.
    static func responsible(_ pid: pid_t) -> pid_t? {
        guard let f = responsibleFn else { return nil }
        let r = f(pid)
        return r > 0 && r != pid ? r : nil
    }
}

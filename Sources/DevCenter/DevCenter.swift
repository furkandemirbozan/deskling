import AppKit
import Combine

/// Portlar sekmesinin durumu. Tarama arka planda yapılır, sekme açıkken birkaç saniyede bir yenilenir.
final class DevCenter: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var docker: DockerState = .unknown
    @Published private(set) var updated: Date?
    @Published private(set) var loading = false
    @Published private(set) var working: Set<String> = []     // işlem süren port ya da konteyner
    @Published private(set) var stubborn: Set<String> = []    // kapatılmak istenip kapanmayan portlar
    @Published var note: String?
    @Published var showSystem = false

    var scanPorts: () -> [ListeningPort] = { PortScanner.scan() }
    var scanDocker: () -> (DockerState, [DockerContainer]) = { DockerService.list() }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private let queue = DispatchQueue(label: "robo.devcenter", qos: .userInitiated)
    private var timer: Timer?
    private var activeViews = 0
    private var refreshing = false

    var visiblePorts: [ListeningPort] { showSystem ? ports : ports.filter { !$0.isSystem } }
    var hiddenSystemCount: Int { ports.filter(\.isSystem).count }

    func activate() {
        activeViews += 1
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func deactivate() {
        activeViews = max(0, activeViews - 1)
        guard activeViews == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh(then done: (() -> Void)? = nil) {
        guard !refreshing else { done?(); return }
        refreshing = true
        loading = true
        let scanPorts = scanPorts, scanDocker = scanDocker
        queue.async { [weak self] in
            let ports = scanPorts()
            let (state, containers) = scanDocker()
            DispatchQueue.main.async {
                guard let self else { return }
                self.ports = ports.map(Self.withApp)
                self.docker = state
                self.containers = containers
                self.stubborn = self.stubborn.filter { id in ports.contains { $0.id == id } }
                self.updated = Date()
                self.loading = false
                self.refreshing = false
                done?()
            }
        }
    }

    /// Masaüstü uygulamasıysa adını ve simgesinin yolunu ekler (ana iş parçacığında).
    private static func withApp(_ p: ListeningPort) -> ListeningPort {
        var p = p
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            p.appName = app.localizedName
            p.appPath = app.bundleURL?.path
        }
        return p
    }

    func open(_ port: Int) {
        openURL(URL(string: "http://localhost:\(port)")!)
    }

    /// Önce kibarca kapatmasını ister (SIGTERM); kapanmazsa "Zorla kapat" (SIGKILL) seçeneği çıkar.
    func kill(_ p: ListeningPort, force: Bool = false) {
        guard p.killable else { note = "\(p.displayName) bu kullanıcıya ait değil, kapatılamaz."; return }
        if Darwin.kill(p.pid, force ? SIGKILL : SIGTERM) != 0 {
            note = "\(p.displayName) kapatılamadı: \(String(cString: strerror(errno)))"
            return
        }
        working.insert(p.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + (force ? 0.5 : 1.5)) { [weak self] in
            guard let self else { return }
            self.working.remove(p.id)
            let alive = Darwin.kill(p.pid, 0) == 0
            if alive, !force {
                self.stubborn.insert(p.id)
                self.note = "\(p.displayName) kapanmadı. İstersen zorla kapatabilirsin."
            } else {
                self.stubborn.remove(p.id)
                self.note = ":\(p.port) boşaltıldı (\(p.displayName) kapatıldı)."
            }
            self.refresh()
        }
    }

    func toggle(_ c: DockerContainer) {
        guard !working.contains(c.id) else { return }
        working.insert(c.id)
        let start = !c.running
        queue.async { [weak self] in
            let error = DockerService.setRunning(c, start)
            DispatchQueue.main.async {
                guard let self else { return }
                self.working.remove(c.id)
                self.note = error.map { "\(c.name): \($0)" } ?? "\(c.name) \(start ? "başlatıldı" : "durduruldu")."
                self.refresh()
            }
        }
    }

    func openDocker() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
        note = "Docker Desktop açılıyor, hazır olunca konteynerler burada görünür."
    }

    func reveal(_ p: ListeningPort) {
        guard let cwd = p.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    func copyURL(_ port: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port)", forType: .string)
        note = "http://localhost:\(port) kopyalandı."
    }
}

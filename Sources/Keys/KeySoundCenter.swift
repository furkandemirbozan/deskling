import AppKit
import AVFoundation
import Combine

/// Klavye seslerinin durumu: paketler, seçili paket, ayarlar ve tuşları dinleme.
final class KeySoundCenter: ObservableObject {
    @Published var enabled: Bool { didSet { put(enabled, "keysEnabled"); applyListening() } }
    @Published var volume: Double { didSet { put(volume, "keysVolume") } }
    @Published var release: Bool { didSet { put(release, "keysRelease") } }
    @Published var stereo: Bool { didSet { put(stereo, "keysStereo") } }
    @Published var variation: Bool { didSet { put(variation, "keysVariation") } }
    @Published var muteWithMic: Bool { didSet { put(muteWithMic, "keysMuteMic") } }
    @Published private(set) var selectedID: String
    @Published private(set) var folder: URL
    @Published private(set) var packs: [SoundPackInfo] = SynthPacks.all
    @Published private(set) var problems: [String] = []
    /// Klasörde aynı paketin kaç kopyası atlandı.
    @Published private(set) var duplicates = 0
    @Published private(set) var loading = false
    @Published private(set) var permission = false
    @Published private(set) var micActive = false
    @Published private(set) var listening = false

    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/KlavyeSesDosyaları")

    /// Paket klasörünün şu anki yeri (Disk sekmesi bunu korur).
    static func currentFolder(_ d: UserDefaults = .standard) -> URL {
        d.string(forKey: "keysFolder").map { URL(fileURLWithPath: $0) } ?? defaultFolder
    }
    static let defaults: [String: Any] = ["keysEnabled": false, "keysVolume": 0.7, "keysRelease": true, "keysStereo": true,
                                          "keysVariation": true, "keysMuteMic": true, "keysPack": "deskling.tok"]

    /// Paket değişince (ada için).
    var onPackChange: (String) -> Void = { _ in }
    var store: SoundPackStore
    let listener = KeyListener()
    private lazy var engine = KeySoundEngine()
    private let defaultsStore: UserDefaults?
    private let queue = DispatchQueue(label: "deskling.keys.load", qos: .userInitiated)
    private var loaded: LoadedPack?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var timer: Timer?
    private var rng = KeyRandom(seed: 42)

    init(store: SoundPackStore = SoundPackStore(cache: SoundPackStore.liveCache()), defaults: UserDefaults?) {
        self.store = store
        defaultsStore = defaults
        defaults?.register(defaults: Self.defaults)
        let d = Self.defaults
        func b(_ k: String) -> Bool { defaults?.bool(forKey: k) ?? (d[k] as! Bool) }
        enabled = b("keysEnabled")
        volume = defaults?.double(forKey: "keysVolume") ?? 0.7
        release = b("keysRelease")
        stereo = b("keysStereo")
        variation = b("keysVariation")
        muteWithMic = b("keysMuteMic")
        selectedID = defaults?.string(forKey: "keysPack") ?? "deskling.tok"
        folder = defaults?.string(forKey: "keysFolder").map { URL(fileURLWithPath: $0) } ?? Self.defaultFolder
    }

    var selected: SoundPackInfo? { packs.first { $0.id == selectedID } }

    // MARK: Açılış

    /// Uygulama açılınca: klasörü okur, seçili paketi yükler, izin varsa dinlemeye başlar.
    func start() {
        permission = KeyListener.hasPermission
        listener.onKey = { [weak self] code, down in self?.key(code, down: down) }
        rescan()
        watchFolder()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        applyListening()
    }

    /// İzin ve mikrofon durumunu yoklar (izin verilince kendiliğinden başlasın diye).
    private func poll() {
        let p = KeyListener.hasPermission
        if p != permission { permission = p; applyListening() }
        else if enabled, permission, !listening { applyListening() }   // izin yeni verildiyse ya da dinleme düştüyse
        if enabled, muteWithMic {
            let m = MicWatch.inUse()
            if m != micActive { micActive = m }
        } else if micActive { micActive = false }
    }

    private func applyListening() {
        if enabled, permission { listening = listener.start() } else { listener.stop(); listening = false }
    }

    func requestPermission() {
        if !KeyListener.requestPermission() { KeyListener.openSettings() }
        permission = KeyListener.hasPermission
        applyListening()
    }

    // MARK: Paketler

    func rescan() {
        let store = self.store, folder = self.folder
        loading = true
        queue.async { [weak self] in
            let r = store.sync(from: folder)
            DispatchQueue.main.async {
                guard let self else { return }
                self.packs = SynthPacks.all + r.packs
                self.problems = r.problems
                self.duplicates = r.duplicates
                self.loading = false
                if self.selected == nil { self.selectedID = SynthPacks.all[1].id }
                if self.loaded?.id != self.selectedID { self.load(self.selectedID) }
            }
        }
    }

    func setFolder(_ url: URL) {
        folder = url
        put(url.path, "keysFolder")
        watchFolder()
        rescan()
    }

    /// Paket seçmek klavye seslerini açmak istemek demektir: kapalıysa açılır, izin yoksa istenir.
    func select(_ id: String, announce: Bool = true, turnOn: Bool = true) {
        guard let info = packs.first(where: { $0.id == id }) else { return }
        if turnOn {
            if !enabled { enabled = true }
            if !permission { requestPermission() }
        }
        selectedID = id
        put(id, "keysPack")
        load(id) { [weak self] in
            if announce { self?.onPackChange(info.name) }
            self?.preview()
        }
    }

    /// Sıradaki pakete geçer (menü ve kısayol için).
    func selectNext() {
        guard !packs.isEmpty else { return }
        let i = packs.firstIndex { $0.id == selectedID } ?? -1
        select(packs[(i + 1) % packs.count].id)
    }

    private func load(_ id: String, then done: (() -> Void)? = nil) {
        guard let info = packs.first(where: { $0.id == id }) else { return }
        queue.async { [weak self] in
            let pack = try? PackLoader.load(info)
            DispatchQueue.main.async {
                guard let self, self.selectedID == id else { return }
                self.loaded = pack
                if pack == nil { self.problems.append("\(info.name): sesler okunamadı") }
                done?()
            }
        }
    }

    /// Klasöre yeni zip düşünce ya da silinince kendiliğinden yeniden okunur.
    /// Klasör ve alt klasörleri izlenir; yeni klasör eklenince o da izlemeye alınır.
    private func watchFolder() {
        watchers.forEach { $0.cancel() }
        watchers = []
        let fm = FileManager.default
        var dirs = [folder]
        if let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in e where e.level <= 3 {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { dirs.append(u) }
                if dirs.count > 64 { break }
            }
        }
        for dir in dirs {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let w = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
            w.setEventHandler { [weak self] in self?.folderChanged() }
            w.setCancelHandler { close(fd) }
            w.resume()
            watchers.append(w)
        }
    }

    private var pendingRescan: DispatchWorkItem?
    private func folderChanged() {
        pendingRescan?.cancel()
        let job = DispatchWorkItem { [weak self] in
            self?.watchFolder()
            self?.rescan()
        }
        pendingRescan = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: job)   // indirme ya da kopyalama bitsin
    }

    // MARK: Çalma

    var muted: Bool { !enabled || (muteWithMic && micActive) }

    func key(_ keyCode: UInt16, down: Bool) {
        guard !muted, let code = KeyCodes.mac[keyCode] else { return }
        play(code, down: down)
    }

    func play(_ code: String, down: Bool) {
        guard let pack = loaded, down || release, let buf = pack.sound(code, up: !down) else { return }
        let pan = stereo ? (KeyCodes.position(code) * 2 - 1) * 0.6 : 0
        let vary = variation || pack.randomPitch
        let rate: Float = vary ? 1 + Float(rng.nextSigned()) * 0.025 : 1
        let vol = Float(volume) * pack.volume * (vary ? 1 + Float(rng.nextSigned()) * 0.08 : 1) * (down ? 1 : 0.75)
        engine.play(buf, volume: vol, pan: pan, rate: rate)
    }

    /// Seçili paketi kısa bir cümleyle dinletir.
    func preview() {
        let seq = ["KeyM", "KeyE", "KeyR", "KeyH", "KeyA", "KeyB", "KeyA", "Space", "KeyD", "KeyE", "KeyS", "KeyK", "Enter"]
        for (i, code) in seq.enumerated() {
            let t = Double(i) * 0.105 + (code == "Space" ? 0.06 : 0) + (code == "Enter" ? 0.12 : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.play(code, down: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.07) { [weak self] in self?.play(code, down: false) }
        }
    }

    func revealFolder() {
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            watchFolder()
        }
        NSWorkspace.shared.open(folder)
    }

    private func put(_ v: Any, _ k: String) { defaultsStore?.set(v, forKey: k) }

    /// Testler için: sesi çalmadan yüklü paketi verir.
    func loadNow(_ id: String) -> LoadedPack? {
        guard let info = packs.first(where: { $0.id == id }) else { return nil }
        return try? PackLoader.load(info)
    }

    func setPacksForTest(_ list: [SoundPackInfo]) { packs = SynthPacks.all + list }
}

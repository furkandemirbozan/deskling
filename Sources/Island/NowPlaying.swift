import AppKit

enum MediaSource: String, Equatable {
    case music, spotify, browser, system

    var bundleID: String? {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .browser, .system: return nil
        }
    }

    var appName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .browser: return "Tarayıcı"
        case .system: return "Medya"
        }
    }

    var isRunning: Bool {
        guard let id = bundleID else { return true }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
}

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var stamp: Date
    var playing: Bool
    var source: MediaSource
    var artworkData: Data? = nil
    var artworkURL: String? = nil
    var tab: BrowserTab? = nil
    /// Tarayıcıdan yalnızca başlık okunabildiyse denetim medya tuşlarıyla yapılır.
    var limited = false

    var key: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }
    /// Kapaktaki küçük rozet ve kapağa tıklayınca açılacak uygulama.
    var appBundleID: String? { source.bundleID ?? tab?.browser }
    var appName: String { tab.flatMap { BrowserKind.find($0.browser)?.name } ?? source.appName }

    init(title: String, artist: String, album: String, duration: TimeInterval, position: TimeInterval, stamp: Date,
         playing: Bool, source: MediaSource, artworkData: Data? = nil, artworkURL: String? = nil, tab: BrowserTab? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.duration = duration; self.position = position
        self.stamp = stamp; self.playing = playing; self.source = source; self.artworkData = artworkData
        self.artworkURL = artworkURL; self.tab = tab
    }

    static func browser(_ p: BrowserPayload, tab: BrowserTab, now: Date) -> TrackInfo {
        var t = TrackInfo(title: p.title, artist: p.artist, album: p.album, duration: p.duration, position: p.position, stamp: now,
                          playing: p.playing, source: .browser, artworkURL: p.artwork.isEmpty ? nil : p.artwork, tab: tab)
        t.limited = p.limited
        return t
    }

    func elapsed(_ now: Date) -> TimeInterval {
        let e = position + (playing ? max(0, now.timeIntervalSince(stamp)) : 0)
        return duration > 0 ? min(duration, e) : e
    }

    static func == (a: TrackInfo, b: TrackInfo) -> Bool {
        a.key == b.key && a.duration == b.duration && a.position == b.position && a.stamp == b.stamp && a.playing == b.playing
    }
}

/// Müzik ve Spotify'ın dağıtık bildirimlerini ve MediaRemote sözlüğünü parça bilgisine çevirir.
enum NowPlayingParser {
    static func music(_ u: [AnyHashable: Any], now: Date) -> TrackInfo? {
        let state = u["Player State"] as? String
        guard state != "Stopped", let name = u["Name"] as? String, !name.isEmpty else { return nil }
        let total = (u["Total Time"] as? NSNumber)?.doubleValue ?? 0
        return TrackInfo(title: name, artist: u["Artist"] as? String ?? "", album: u["Album"] as? String ?? "",
                         duration: total / 1000, position: 0, stamp: now, playing: state == "Playing", source: .music)
    }

    static func spotify(_ u: [AnyHashable: Any], now: Date) -> TrackInfo? {
        let state = u["Player State"] as? String
        guard state != "Stopped", let name = u["Name"] as? String, !name.isEmpty else { return nil }
        let total = (u["Duration"] as? NSNumber)?.doubleValue ?? 0
        return TrackInfo(title: name, artist: u["Artist"] as? String ?? "", album: u["Album"] as? String ?? "",
                         duration: total / 1000, position: (u["Playback Position"] as? NSNumber)?.doubleValue ?? 0,
                         stamp: now, playing: state == "Playing", source: .spotify)
    }

    static func mediaRemote(_ i: [String: Any], now: Date) -> TrackInfo? {
        let p = "kMRMediaRemoteNowPlayingInfo"
        guard let title = i[p + "Title"] as? String, !title.isEmpty else { return nil }
        let rate = (i[p + "PlaybackRate"] as? NSNumber)?.doubleValue ?? 0
        return TrackInfo(title: title, artist: i[p + "Artist"] as? String ?? "", album: i[p + "Album"] as? String ?? "",
                         duration: (i[p + "Duration"] as? NSNumber)?.doubleValue ?? 0,
                         position: (i[p + "ElapsedTime"] as? NSNumber)?.doubleValue ?? 0,
                         stamp: i[p + "Timestamp"] as? Date ?? now, playing: rate > 0, source: .system,
                         artworkData: i[p + "ArtworkData"] as? Data)
    }
}

/// Özel MediaRemote çerçevesine çalışma anında bağlanır. Yeni macOS sürümleri bilgiyi boş döndürebilir; o zaman
/// yalnızca Müzik ve Spotify kullanılır.
final class MediaRemote {
    static let shared = MediaRemote()
    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias Send = @convention(c) (Int32, NSDictionary?) -> Bool
    private typealias Seek = @convention(c) (Double) -> Void
    private var getInfo: GetInfo?
    private var register: Register?
    private var send: Send?
    private var seek: Seek?

    private init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return }
        if let f = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") { getInfo = unsafeBitCast(f, to: GetInfo.self) }
        if let f = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") { register = unsafeBitCast(f, to: Register.self) }
        if let f = dlsym(h, "MRMediaRemoteSendCommand") { send = unsafeBitCast(f, to: Send.self) }
        if let f = dlsym(h, "MRMediaRemoteSetElapsedTime") { seek = unsafeBitCast(f, to: Seek.self) }
    }

    func start() { register?(.main) }
    func fetch(_ done: @escaping ([String: Any]) -> Void) {
        guard let getInfo else { done([:]); return }
        getInfo(.main) { d in done((d as? [String: Any]) ?? [:]) }
    }
    enum Command: Int32 { case toggle = 2, next = 4, previous = 5 }
    @discardableResult func command(_ c: Command) -> Bool { send?(c.rawValue, nil) ?? false }
    func setElapsed(_ t: Double) { seek?(t) }
}

/// Şu an çalan parça: kapak, renk ve denetimler.
final class NowPlaying: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: NSColor = NSColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: 1)
    var onChange: () -> Void = {}
    var now: () -> Date = Date.init
    /// Testlerde AppleScript çalıştırılmaz.
    var scriptsAllowed = true
    private let scriptQueue = DispatchQueue(label: "deskling.island.script")
    private lazy var browsers = BrowserMedia(queue: scriptQueue)
    /// Tarayıcı başına durum: JavaScript izni kapalıysa adada ipucu gösterilir.
    @Published private(set) var browserStatus: [String: BrowserStatus] = [:]
    var browserHints: [String] {
        browserStatus.filter { $0.value == .jsOff || $0.value == .needsAccess }.keys.sorted().compactMap { BrowserKind.find($0)?.jsHint }
    }
    var needsAccessibility: Bool { browserStatus.values.contains(.needsAccess) || track?.limited == true && !AXIsProcessTrusted() }
    private var artKey: String?
    private var observers: [NSObjectProtocol] = []
    private(set) var started = false

    func start() {
        guard !started else { return }
        started = true
        let dc = DistributedNotificationCenter.default()
        observers.append(dc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            self.apply(NowPlayingParser.music(n.userInfo ?? [:], now: self.now()), source: .music)
        })
        observers.append(dc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            self.apply(NowPlayingParser.spotify(n.userInfo ?? [:], now: self.now()), source: .spotify)
        })
        MediaRemote.shared.start()
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"] {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.fetchSystem()
            })
        }
        fetchSystem()
        guard scriptsAllowed else { return }
        browsers.onResult = { [weak self] list in self?.browserResult(list) }
        browsers.onStatus = { [weak self] s in self?.browserStatus = s; self?.onChange() }
        browsers.start()
    }

    private func browserResult(_ list: [(BrowserTab, BrowserPayload)]) {
        if let (tab, p) = BrowserMedia.pick(list) {
            apply(.browser(p, tab: tab, now: now()), source: .browser)
        } else if track?.source == .browser {
            apply(nil, source: .browser)
        }
        browsers.hasTrack = track?.source == .browser && track?.playing == true
    }

    func stop() {
        browsers.stop()
        for o in observers {
            DistributedNotificationCenter.default().removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers = []
        started = false
    }

    private func fetchSystem() {
        MediaRemote.shared.fetch { [weak self] info in
            guard let self else { return }
            if let t = NowPlayingParser.mediaRemote(info, now: self.now()) {
                self.apply(t, source: .system)
            } else if self.track?.source == .system {
                self.apply(nil, source: .system)
            }
        }
    }

    /// Yeni bilgiyi uygular. Bir kaynağın "durdu" bilgisi yalnızca kendi parçasını siler.
    func apply(_ info: TrackInfo?, source: MediaSource) {
        guard var t = info else {
            if track?.source == source {
                track = nil
                artwork = nil
                artKey = nil
                onChange()
            }
            return
        }
        if let old = track {
            if old.source != t.source, old.playing, !t.playing { return }   // çalan başka kaynağı duraklamış biri ezmesin
            if t.source == .music, old.key == t.key, t.position == 0 { t.position = old.elapsed(now()) }
            // Tarayıcı her yoklamada konum gönderir; tahmin tutuyorsa yeniden çizime gerek yok.
            if t.source == .browser, old.key == t.key, old.playing == t.playing, old.tab == t.tab,
               abs(old.elapsed(now()) - t.position) < 1.5, old.duration == t.duration { return }
        }
        track = t
        if artKey != t.key {
            artKey = t.key
            artwork = nil
            loadArtwork(t)
        }
        onChange()
    }

    func setArtwork(_ img: NSImage?, key: String) {
        guard key == artKey else { return }
        artwork = img
        if let img { accent = Self.accent(of: img) }
        onChange()
    }

    // MARK: Denetimler

    func togglePlay() {
        guard var t = track else { return }
        switch t.source {
        case .system: MediaRemote.shared.command(.toggle)
        case .browser:
            if t.limited || t.tab == nil { MediaKeys.control(.playPause) }
            else if let tab = t.tab { browsers.send(.setPlaying(!t.playing), to: tab) { MediaKeys.control(.playPause) } }
        case .music, .spotify: tell(t.source, "playpause")
        }
        let n = now()
        t.position = t.elapsed(n)
        t.stamp = n
        t.playing.toggle()
        track = t
        onChange()
    }

    func next() { skip(.next, .next, "next track") }
    func previous() { skip(.previous, .previous, "previous track") }
    /// Konuma atlama yalnızca sayfa içinden okunabilen parçalarda var.
    var canSeek: Bool { track.map { !($0.source == .browser && $0.limited) && $0.duration > 0 } ?? false }

    private func skip(_ c: MediaRemote.Command, _ b: BrowserMedia.Command, _ verb: String) {
        guard let t = track else { return }
        switch t.source {
        case .system: MediaRemote.shared.command(c)
        case .browser:
            let key: MediaKeys.Key = c == .next ? .next : .previous
            if t.limited || t.tab == nil { MediaKeys.control(key) } else if let tab = t.tab { browsers.send(b, to: tab) { MediaKeys.control(key) } }
        case .music, .spotify: tell(t.source, verb)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard var t = track else { return }
        let s = max(0, t.duration > 0 ? min(t.duration, seconds) : seconds)
        switch t.source {
        case .system: MediaRemote.shared.setElapsed(s)
        case .browser: if let tab = t.tab { browsers.send(.seek(s), to: tab) }
        case .music, .spotify: tell(t.source, "set player position to \(s)")
        }
        t.position = s
        t.stamp = now()
        track = t
        onChange()
    }

    func openApp() {
        if let tab = track?.tab { browsers.activate(tab); return }
        guard let id = track?.source.bundleID ?? MediaSource.music.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func open(_ source: MediaSource) {
        guard let id = source.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func installed(_ source: MediaSource) -> Bool {
        source.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
    }

    /// Ada açıkken çağrılır: Müzik bildirimlerinde konum yoktur, AppleScript'le doğru konum alınır.
    func refreshPosition() {
        guard let t = track, t.source == .music || t.source == .spotify, scriptsAllowed, t.source.isRunning else { return }
        let key = t.key
        run(t.source, "player position") { [weak self] d in
            guard let self, let d, self.track?.key == key else { return }
            let pos = Double(d.stringValue?.replacingOccurrences(of: ",", with: ".") ?? "") ?? d.doubleValue
            guard var cur = self.track, pos.isFinite else { return }
            cur.position = pos
            cur.stamp = self.now()
            self.track = cur
            self.onChange()
        }
    }

    // MARK: Kapak

    private func loadArtwork(_ t: TrackInfo) {
        let key = t.key
        if let data = t.artworkData { setArtwork(NSImage(data: data), key: key); return }
        if t.source == .browser {
            if let s = t.artworkURL { download(s, key: key) }
            return
        }
        guard scriptsAllowed, t.source.isRunning else { return }
        switch t.source {
        case .music:
            run(.music, "if player state is not stopped then get raw data of artwork 1 of current track") { [weak self] d in
                guard let data = d?.data, !data.isEmpty else { return }
                self?.setArtwork(NSImage(data: data), key: key)
            }
        case .spotify:
            run(.spotify, "artwork url of current track") { [weak self] d in
                guard let s = d?.stringValue else { return }
                self?.download(s, key: key)
            }
        case .browser, .system:
            break
        }
    }

    /// Kapak yalnızca https adresinden, çerez göndermeden indirilir.
    private func download(_ s: String, key: String) {
        guard let url = URL(string: s), url.scheme == "https" else { return }
        var req = URLRequest(url: url)
        req.httpShouldHandleCookies = false
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.setArtwork(img, key: key) }
        }.resume()
    }

    // MARK: AppleScript

    /// Uygulama açık değilse betik gönderilmez; böylece ada Müzik'i ya da Spotify'ı kendiliğinden başlatmaz.
    private func tell(_ s: MediaSource, _ verb: String) {
        run(s, verb) { _ in }
    }

    private func run(_ s: MediaSource, _ body: String, _ done: @escaping (NSAppleEventDescriptor?) -> Void) {
        guard scriptsAllowed, s == .music || s == .spotify, s.isRunning else { done(nil); return }
        let src = "tell application \"\(s.appName)\" to \(body)"
        scriptQueue.async {
            var err: NSDictionary?
            let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
            DispatchQueue.main.async { done(err == nil ? out : nil) }
        }
    }

    // MARK: Renk

    /// Kapağın baskın rengini, koyu adada okunacak kadar parlak ve doygun hale getirir.
    static func accent(of img: NSImage) -> NSColor {
        let fallback = NSColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: 1)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallback }
        let n = 12
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let pr = Double(px[i]) / 255, pg = Double(px[i + 1]) / 255, pb = Double(px[i + 2]) / 255
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            let weight = 0.08 + (mx - mn) * mx   // doygun ve parlak pikseller ağır basar
            r += pr * weight; g += pg * weight; b += pb * weight; w += weight
        }
        guard w > 0 else { return fallback }
        let c = NSColor(srgbRed: r / w, green: g / w, blue: b / w, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.88, alpha: 1) }
        return NSColor(hue: h, saturation: min(0.85, max(0.45, s * 1.25)), brightness: max(0.78, v), alpha: 1)
    }
}

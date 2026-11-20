import AVFoundation
import ImageIO
import UniformTypeIdentifiers

extension HoleSettings.Quality {
    /// Önce HEVC denenir, olmazsa H.264.
    var videoPresets: [String] {
        switch self {
        case .low: return [AVAssetExportPreset1280x720]
        case .medium: return [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1920x1080]
        case .high: return [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        }
    }
    var gifSide: CGFloat { self == .low ? 480 : self == .medium ? 640 : 800 }
    var crf: Int { self == .low ? 30 : self == .medium ? 26 : 22 }
}

extension HoleProcessor {
    static let gifLimit: Double = 30      // saniye

    /// Videoları tek tek işler. Normal: hafif MP4. Beyaz delik: sesli videodan ses, sessiz kısa videodan GIF.
    static func videos(_ urls: [URL], mode: HoleMode, settings: HoleSettings, progress: (Double) -> Void) throws -> HoleResult {
        var done: [HoleResult] = []
        for (i, u) in urls.enumerated() {
            let r = try video(u, mode: mode, settings: settings) { p in progress((Double(i) + p) / Double(urls.count)) }
            done.append(r)
        }
        let kept = done.filter(\.consumed)
        guard kept.count > 1 || urls.count > 1 else { return done[0] }
        guard !kept.isEmpty else { return done[0] }
        return HoleResult(ok: true, title: kept.count == urls.count ? "\(kept.count) video işlendi" : "\(kept.count)/\(urls.count) video işlendi",
                          detail: kept.compactMap(\.detail).first, outputs: kept.flatMap(\.outputs), consumed: true)
    }

    static func video(_ u: URL, mode: HoleMode, settings: HoleSettings, progress: (Double) -> Void) throws -> HoleResult {
        let ext = u.pathExtension.lowercased()
        if ext == "mkv" || ext == "avi" { return try viaFFmpeg(u, mode: mode, settings: settings) }
        let asset = AVURLAsset(url: u)
        guard asset.isReadable, !asset.tracks(withMediaType: .video).isEmpty else { throw HoleError.tool("Video okunamadı") }
        if mode == .white {
            if !asset.tracks(withMediaType: .audio).isEmpty { return try extractAudio(asset, u, progress: progress) }
            let seconds = CMTimeGetSeconds(asset.duration)
            guard seconds <= gifLimit else {
                return HoleResult(ok: false, title: "Bu videoda ses yok, GIF için de çok uzun",
                                  detail: "GIF en fazla \(Int(gifLimit)) saniyelik videodan yapılır", consumed: false)
            }
            return try makeGIF(asset, u, settings: settings, progress: progress)
        }
        return try compressVideo(asset, u, settings: settings, progress: progress)
    }

    private static func duration(_ asset: AVAsset) -> String {
        let s = Int(CMTimeGetSeconds(asset.duration).rounded())
        return s >= 60 ? "\(s / 60) dk \(s % 60) sn" : "\(s) sn"
    }

    /// Dışa aktarma bitene kadar bekler, bu sırada ilerlemeyi bildirir.
    private static func export(_ asset: AVAsset, presets: [String], to base: URL, types: [AVFileType],
                               progress: (Double) -> Void) throws -> URL {
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard let preset = presets.first(where: compatible.contains),
              let session = AVAssetExportSession(asset: asset, presetName: preset),
              let type = types.first(where: session.supportedFileTypes.contains) else {
            throw HoleError.tool("Bu video bu biçimde dışa aktarılamıyor")
        }
        let ext = type == .mp4 ? "mp4" : type == .m4a ? "m4a" : "mov"
        let out = freeURL(in: base.deletingLastPathComponent(), base: base.lastPathComponent, ext: ext)
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        let finished = DispatchSemaphore(value: 0)
        session.exportAsynchronously { finished.signal() }
        while finished.wait(timeout: .now() + 0.2) == .timedOut { progress(Double(session.progress)) }
        progress(1)
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw HoleError.tool(session.error?.localizedDescription ?? "Dışa aktarma tamamlanamadı")
        }
        return out
    }

    /// Ekran kayıtları gibi ağır videolar HEVC ya da H.264 ile hafif bir MP4'e dönüşür.
    static func compressVideo(_ asset: AVAsset, _ u: URL, settings: HoleSettings, progress: (Double) -> Void) throws -> HoleResult {
        let base = u.deletingLastPathComponent().appendingPathComponent(u.deletingPathExtension().lastPathComponent + "_compressed")
        let out = try export(asset, presets: settings.quality.videoPresets, to: base, types: [.mp4, .mov], progress: progress)
        let before = size(of: u), after = size(of: out)
        guard after < Int64(Double(before) * 0.95) else {
            try? FileManager.default.removeItem(at: out)
            return HoleResult(ok: false, title: "Bu video zaten küçük", detail: bytes(before), consumed: false)
        }
        return HoleResult(ok: true, title: "Video sıkıştırıldı", detail: saving(before, after), outputs: [out], consumed: true)
    }

    /// Beyaz delik: videonun sesi M4A olarak ayrılır.
    static func extractAudio(_ asset: AVAsset, _ u: URL, progress: (Double) -> Void) throws -> HoleResult {
        let base = u.deletingLastPathComponent().appendingPathComponent(u.deletingPathExtension().lastPathComponent + "_audio")
        let out = try export(asset, presets: [AVAssetExportPresetAppleM4A], to: base, types: [.m4a], progress: progress)
        return HoleResult(ok: true, title: "Videonun sesi ayrıldı", detail: "\(duration(asset)) · \(bytes(size(of: out)))",
                          outputs: [out], consumed: true)
    }

    /// Beyaz delik: sessiz kısa video saniyede 10 karelik, sonsuz dönen bir GIF olur.
    static func makeGIF(_ asset: AVAsset, _ u: URL, settings: HoleSettings, progress: (Double) -> Void) throws -> HoleResult {
        let seconds = CMTimeGetSeconds(asset.duration)
        let fps = 10.0
        let count = max(1, min(Int(seconds * fps), Int(gifLimit * fps)))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: settings.quality.gifSide, height: settings.quality.gifSide)
        let tolerance = CMTime(value: 1, timescale: 30)
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance

        let out = freeURL(in: u.deletingLastPathComponent(), base: u.deletingPathExtension().lastPathComponent + "_converted", ext: "gif")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw HoleError.tool("GIF oluşturulamadı")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        var written = 0
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let img = try? gen.copyCGImage(at: t, actualTime: nil) {
                CGImageDestinationAddImage(dest, img, frame)
                written += 1
            }
            progress(Double(i + 1) / Double(count))
        }
        guard written > 0, CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw HoleError.tool("Videodan kare alınamadı")
        }
        return HoleResult(ok: true, title: "Video GIF oldu", detail: "\(written) kare · \(bytes(size(of: out)))",
                          outputs: [out], consumed: true)
    }

    /// MKV ve AVI'yi macOS açamaz; ffmpeg kuruluysa onunla işlenir.
    static func viaFFmpeg(_ u: URL, mode: HoleMode, settings: HoleSettings) throws -> HoleResult {
        let kind = u.pathExtension.uppercased()
        guard let ffmpeg = HoleTools.find("ffmpeg") else {
            return HoleResult(ok: false, title: "\(kind) için ffmpeg gerekli", detail: "Terminalde: brew install ffmpeg", consumed: false)
        }
        let name = u.deletingPathExtension().lastPathComponent
        if mode == .white {
            let out = freeURL(in: u.deletingLastPathComponent(), base: name + "_audio", ext: "m4a")
            try run(ffmpeg.path, ["-nostdin", "-y", "-loglevel", "error", "-i", u.path, "-vn", "-c:a", "aac", "-b:a", "192k", out.path])
            return HoleResult(ok: true, title: "Videonun sesi ayrıldı", detail: bytes(size(of: out)), outputs: [out], consumed: true)
        }
        let out = freeURL(in: u.deletingLastPathComponent(), base: name + "_compressed", ext: "mp4")
        try run(ffmpeg.path, ["-nostdin", "-y", "-loglevel", "error", "-i", u.path, "-c:v", "libx264", "-crf", String(settings.quality.crf),
                              "-preset", "medium", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out.path])
        let before = size(of: u), after = size(of: out)
        guard after < Int64(Double(before) * 0.95) else {
            try? FileManager.default.removeItem(at: out)
            return HoleResult(ok: false, title: "Bu video zaten küçük", detail: bytes(before), consumed: false)
        }
        return HoleResult(ok: true, title: "\(kind) → MP4", detail: saving(before, after), outputs: [out], consumed: true)
    }
}

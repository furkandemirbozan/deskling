import AVFoundation
import ImageIO

/// Video işlemlerini, testte üretilen gerçek videolarla dener.
enum HoleVideoCheck {
    static var failures = 0
    private static let fm = FileManager.default

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    /// Hareketli, gürültülü ve yüksek bit hızlı bir ekran kaydı benzeri video yazar.
    static func makeVideo(_ url: URL, w: Int, h: Int, seconds: Double, fps: Int32, bitrate: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var seed: UInt32 = 99
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pb = buffer else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            let row = CVPixelBufferGetBytesPerRow(pb)
            let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w {
                    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                    let o = y * row + x * 4, n = UInt8(seed & 31)
                    p[o] = UInt8((x + i * 9) & 255) &+ n
                    p[o + 1] = UInt8((y + i * 5) & 255) &+ n
                    p[o + 2] = UInt8(((x + y) / 4) & 255)
                    p[o + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }

    /// Videoya 440 Hz bir ses ekler.
    static func addTone(to video: URL, out: URL) throws {
        let wav = fm.temporaryDirectory.appendingPathComponent("ton-\(UUID().uuidString).caf")
        defer { try? fm.removeItem(at: wav) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: wav, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(44100 * 3)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0..<Int(frames) { buf.floatChannelData![0][i] = 0.3 * sin(Float(i) * 2 * .pi * 440 / 44100) }
        try file.write(from: buf)

        let v = AVURLAsset(url: video), a = AVURLAsset(url: wav)
        let comp = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: v.duration)
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(range, of: v.tracks(withMediaType: .video)[0], at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: min(v.duration, a.duration)), of: a.tracks(withMediaType: .audio)[0], at: .zero)
        let s = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
        s.outputURL = out
        s.outputFileType = .mov
        let done = DispatchSemaphore(value: 0)
        s.exportAsynchronously { done.signal() }
        done.wait()
    }

    private static func info(_ u: URL) -> (video: CGSize?, audio: Bool, seconds: Double) {
        let a = AVURLAsset(url: u)
        let v = a.tracks(withMediaType: .video).first
        let size = v.map { $0.naturalSize.applying($0.preferredTransform) }.map { CGSize(width: abs($0.width), height: abs($0.height)) }
        return (size, !a.tracks(withMediaType: .audio).isEmpty, CMTimeGetSeconds(a.duration))
    }

    static func run(in dir: URL) {
        let kayit = dir.appendingPathComponent("ekran kaydı.mov")
        let sesli = dir.appendingPathComponent("sesli.mov")
        let uzun = dir.appendingPathComponent("uzun.mov")
        let kucuk = dir.appendingPathComponent("kucuk.mov")
        let mkv = dir.appendingPathComponent("film.mkv")
        do {
            try makeVideo(kayit, w: 1920, h: 1080, seconds: 3, fps: 30, bitrate: 40_000_000)
            try addTone(to: kayit, out: sesli)
            try makeVideo(uzun, w: 160, h: 96, seconds: 31, fps: 2, bitrate: 200_000)
            try makeVideo(kucuk, w: 160, h: 96, seconds: 2, fps: 10, bitrate: 60_000)
            try Data(repeating: 1, count: 2048).write(to: mkv)
        } catch {
            check("test videoları üretilir", false, "\(error)")
            return
        }
        check("test videoları üretilir", info(kayit).video != nil && info(sesli).audio)
        let originals = [kayit, sesli, uzun, kucuk, mkv]
        let sums = originals.map { (try? Data(contentsOf: $0)) ?? Data() }
        var steps: [Double] = []
        func go(_ urls: [URL], _ mode: HoleMode = .normal, _ q: HoleSettings.Quality = .medium) -> HoleResult {
            var s = HoleSettings(); s.quality = q
            steps = []
            return HoleProcessor.process(urls, mode: mode, trashOriginal: false, settings: s, trash: { _ in }, progress: { steps.append($0) })
        }

        let c = go([kayit])
        let ci = c.outputs.first.map(info)
        check("ekran kaydı hafif bir MP4'e sıkışır", c.ok && c.outputs.first?.lastPathComponent == "ekran kaydı_compressed.mp4", c.detail ?? c.title)
        check("sıkışan video oynatılabilir ve süresi korunur", ci?.video != nil && abs((ci?.seconds ?? 0) - 3) < 0.2,
              String(format: "%.2f sn", ci?.seconds ?? 0))
        check("ilerleme bildirilir ve tamamlanır", !steps.isEmpty && steps.last == 1, "\(steps.count) adım")
        let low = go([kayit], .normal, .low)
        let lowSize = low.outputs.first.flatMap { info($0).video } ?? .zero
        check("düşük kalitede video 720p'ye iner", low.ok && max(lowSize.width, lowSize.height) <= 1280 && lowSize.width > 0, "\(Int(lowSize.width))x\(Int(lowSize.height))")

        let a = go([sesli], .white)
        let ai = a.outputs.first.map(info)
        check("beyaz delik sesli videonun sesini ayırır", a.ok && a.outputs.first?.pathExtension == "m4a" && ai?.audio == true && ai?.video == nil, a.title)
        check("ayrılan sesin süresi videoyla aynıdır", abs((ai?.seconds ?? 0) - 3) < 0.2)

        let g = go([kayit], .white)
        var frames = 0, gifSide = 0
        if let out = g.outputs.first, let src = CGImageSourceCreateWithURL(out as CFURL, nil) {
            frames = CGImageSourceGetCount(src)
            let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            gifSide = max((p?[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p?[kCGImagePropertyPixelHeight] as? Int) ?? 0)
        }
        check("beyaz delik sessiz kısa videodan GIF yapar", g.ok && g.outputs.first?.pathExtension == "gif" && frames >= 28 && frames <= 31, "\(frames) kare")
        check("GIF orta kalitede en fazla 640 piksel olur", gifSide > 0 && gifSide <= 640, "\(gifSide) px")
        let l = go([uzun], .white)
        check("sessiz uzun videodan GIF yapılmaz", !l.ok && !l.consumed, l.title)
        let k = go([kucuk])
        check("zaten küçük video geri fırlatılır", !k.consumed && !fm.fileExists(atPath: dir.appendingPathComponent("kucuk_compressed.mp4").path), k.title)
        if HoleTools.find("ffmpeg") == nil {
            let m = go([mkv])
            check("ffmpeg yoksa MKV için nazik uyarı verilir", !m.consumed && m.title == "MKV için ffmpeg gerekli")
        }
        let two = go([kayit, sesli])
        check("birden çok video tek tek işlenir", two.ok && two.outputs.count == 2 && two.title == "2 video işlendi", two.title)
        check("video işlemlerinde orijinaller değişmez", originals.map { (try? Data(contentsOf: $0)) ?? Data() } == sums)
    }
}

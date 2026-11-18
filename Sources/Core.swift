import AppKit
import CoreServices
import ImageIO
import UniformTypeIdentifiers

// MARK: - Modeller

enum Evidence: String {
    case spotlight = "macOS kaydı"
    case exif = "Dosya imzası"
}

struct Shot: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let created: Date
    let modified: Date
    let evidence: Evidence
    var id: String { url.path }
    var name: String { url.lastPathComponent }

    static func == (a: Shot, b: Shot) -> Bool { a.id == b.id && a.modified == b.modified }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct CleanRecord: Codable, Identifiable {
    var id = UUID()
    let name: String
    let originalPath: String
    let trashPath: String
    let date: Date
    var restored = false
}

// MARK: - Algılama

/// Dosya adına asla güvenmez: yalnızca macOS'un koyduğu ekran görüntüsü işaretlerini kabul eder.
enum ScreenshotDetector {
    static func evidence(for url: URL) -> Evidence? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              v.isRegularFile == true, v.isSymbolicLink != true,
              let type = v.contentType, type.conforms(to: .image) else { return nil }

        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? NSNumber,
           flag.boolValue {
            return .spotlight
        }
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let comment = exif[kCGImagePropertyExifUserComment] as? String,
           comment.trimmingCharacters(in: .whitespacesAndNewlines) == "Screenshot" {
            return .exif
        }
        return nil
    }

    /// Yalnızca klasörün en üst seviyesine bakar, alt klasörlere girmez.
    static func scan(_ dir: URL) -> [Shot] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return files.compactMap { url -> Shot? in
            guard let ev = evidence(for: url), let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Shot(url: url, size: Int64(v.fileSize ?? 0),
                        created: v.creationDate ?? .distantPast,
                        modified: v.contentModificationDate ?? .distantPast, evidence: ev)
        }.sorted { $0.created > $1.created }
    }

    static func thumbnail(_ url: URL, maxPixels: Int = 220) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

// MARK: - Güvenli taşıma

enum CleanError: LocalizedError {
    case changed
    var errorDescription: String? { "Dosya taranandan sonra değişmiş, dokunulmadı." }
}

enum Cleaner {
    /// Klasörde aynı adlı dosya varsa üzerine yazmamak için yeni bir ad bulur.
    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var dest = url
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return dest
    }

    /// Son anda tekrar doğrular, sonra dosyayı toz haznesi klasörüne taşır. Hiçbir dosya silinmez.
    static func collect(_ shot: Shot, into dir: URL) throws -> CleanRecord {
        let fm = FileManager.default
        let v = try shot.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard Int64(v.fileSize ?? -1) == shot.size,
              v.contentModificationDate == shot.modified,
              ScreenshotDetector.evidence(for: shot.url) != nil else { throw CleanError.changed }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueURL(dir.appendingPathComponent(shot.name))
        try fm.moveItem(at: shot.url, to: dest)
        return CleanRecord(name: shot.name, originalPath: shot.url.path, trashPath: dest.path, date: Date())
    }

    static func restore(_ record: CleanRecord) throws -> URL {
        let dest = uniqueURL(URL(fileURLWithPath: record.originalPath))
        try FileManager.default.moveItem(at: URL(fileURLWithPath: record.trashPath), to: dest)
        return dest
    }
}

// MARK: - Masaüstü geometrisi

enum DesktopMap {
    static var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    /// Finder'dan simge konumlarını alır; izin yoksa macOS'un varsayılan ızgarasını tahmin eder.
    /// Dönen noktalar ekranın sol altına göre yereldir.
    static func positions(names: [String], askFinder: Bool, completion: @escaping ([String: CGPoint]) -> Void) {
        let size = screen.frame.size
        let visible = screen.visibleFrame
        let topInset = screen.frame.maxY - visible.maxY
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = askFinder ? finderPositions(names) : [:]
            var out: [String: CGPoint] = [:]
            let rows = max(1, Int((size.height - topInset - 120) / 104))
            for (i, name) in names.enumerated() {
                let p: CGPoint
                if let f = raw[name] {
                    p = CGPoint(x: f.x, y: size.height - f.y)
                } else {
                    p = CGPoint(x: size.width - 70 - CGFloat(i / rows) * 104,
                                y: size.height - topInset - 70 - CGFloat(i % rows) * 104)
                }
                out[name] = CGPoint(x: min(max(p.x, 60), size.width - 60), y: min(max(p.y, 60), size.height - 40))
            }
            DispatchQueue.main.async { completion(out) }
        }
    }

    private static func finderPositions(_ names: [String]) -> [String: CGPoint] {
        guard !names.isEmpty else { return [:] }
        let script = """
        on run argv
            set out to {}
            tell application "Finder"
                repeat with n in argv
                    try
                        set p to desktop position of item (n as text) of desktop
                        set end of out to ((item 1 of p) as text) & "," & ((item 2 of p) as text)
                    on error
                        set end of out to "?"
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to linefeed
            return out as text
        end run
        """
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script] + names
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [:] }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [:] }
        var out: [String: CGPoint] = [:]
        for (name, line) in zip(names, text.split(separator: "\n", omittingEmptySubsequences: false)) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: ",")
            if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                out[name] = CGPoint(x: x, y: y)
            }
        }
        return out
    }

    /// Robotun hazneyi boşaltmak için durduğu nokta: istasyonun hemen önü.
    static func stationApproach() -> CGPoint {
        let b = basePoint()
        return CGPoint(x: b.x + 92, y: b.y)
    }

    /// İstasyon kutusunun ortası.
    static func stationCenter() -> CGPoint {
        let b = basePoint()
        return CGPoint(x: b.x - 52, y: b.y)
    }

    static func basePoint() -> CGPoint {
        let s = screen
        return CGPoint(x: s.visibleFrame.minX - s.frame.minX + 130, y: s.visibleFrame.minY - s.frame.minY + 84)
    }
}

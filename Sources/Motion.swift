import AppKit

// MARK: - Gezinti rotaları

enum PatrolStyle: String, CaseIterable {
    case zigzag, loop, wander, perimeter, figureEight, spiral
}

struct PatrolRoute {
    let style: PatrolStyle
    let points: [CGPoint]
}

/// Her gezintide bir öncekinden farklı biçimde, rastgele bir rota üretir.
struct PatrolPlanner {
    private(set) var last: PatrolStyle?

    mutating func next(in area: CGRect) -> PatrolRoute {
        var rng = SystemRandomNumberGenerator()
        return next(in: area, using: &rng)
    }

    mutating func next<G: RandomNumberGenerator>(in area: CGRect, using rng: inout G) -> PatrolRoute {
        let style = PatrolStyle.allCases.filter { $0 != last }.randomElement(using: &rng)!
        last = style
        let raw: [CGPoint]
        switch style {
        case .zigzag: raw = Self.zigzag(area, &rng)
        case .loop: raw = Self.loop(area, &rng)
        case .wander: raw = Self.wander(area, &rng)
        case .perimeter: raw = Self.perimeter(area, &rng)
        case .figureEight: raw = Self.figureEight(area, &rng)
        case .spiral: raw = Self.spiral(area, &rng)
        }
        return PatrolRoute(style: style, points: raw.map {
            CGPoint(x: min(max($0.x, area.minX), area.maxX), y: min(max($0.y, area.minY), area.maxY))
        })
    }

    private static func zigzag<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        let rows = Int.random(in: 3...5, using: &rng)
        let vertical = Bool.random(using: &rng)
        let reverse = Bool.random(using: &rng)
        var flip = Bool.random(using: &rng)
        var out: [CGPoint] = []
        for i in 0..<rows {
            var f = CGFloat(i) / CGFloat(rows - 1)
            if reverse { f = 1 - f }
            for g in (flip ? [CGFloat(1), 0] : [CGFloat(0), 1]) {
                let jitter = CGFloat.random(in: -0.05...0.05, using: &rng)
                out.append(vertical ? CGPoint(x: a.minX + a.width * f, y: a.minY + a.height * (g + jitter))
                                    : CGPoint(x: a.minX + a.width * (g + jitter), y: a.minY + a.height * f))
            }
            flip.toggle()
        }
        return out
    }

    private static func loop<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        let n = Int.random(in: 7...10, using: &rng)
        let start = CGFloat.random(in: 0...(2 * .pi), using: &rng)
        let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let rx = a.width * CGFloat.random(in: 0.3...0.5, using: &rng)
        let ry = a.height * CGFloat.random(in: 0.3...0.5, using: &rng)
        return (0...n).map { i in
            let t = start + dir * CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(x: a.midX + cos(t) * rx, y: a.midY + sin(t) * ry)
        }
    }

    private static func wander<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        let n = Int.random(in: 6...9, using: &rng)
        let gap = min(a.width, a.height) * 0.3
        var out: [CGPoint] = []
        var tries = 0
        while out.count < n, tries < 200 {
            tries += 1
            let p = CGPoint(x: CGFloat.random(in: a.minX...a.maxX, using: &rng),
                            y: CGFloat.random(in: a.minY...a.maxY, using: &rng))
            if let l = out.last, hypot(l.x - p.x, l.y - p.y) < gap { continue }
            out.append(p)
        }
        return out
    }

    private static func perimeter<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        var corners = [CGPoint(x: a.minX, y: a.minY), CGPoint(x: a.maxX, y: a.minY),
                       CGPoint(x: a.maxX, y: a.maxY), CGPoint(x: a.minX, y: a.maxY)]
        if Bool.random(using: &rng) { corners.reverse() }
        let shift = Int.random(in: 0..<4, using: &rng)
        var out: [CGPoint] = []
        for i in 0...4 {
            let p = corners[(i + shift) % 4], q = corners[(i + shift + 1) % 4]
            out.append(p)
            if i < 4 {
                let f = CGFloat.random(in: 0.35...0.65, using: &rng)
                let inward = CGFloat.random(in: 0.04...0.16, using: &rng)
                let m = CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f)
                out.append(CGPoint(x: m.x + (a.midX - m.x) * inward, y: m.y + (a.midY - m.y) * inward))
            }
        }
        return out
    }

    private static func figureEight<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        let n = 12
        let phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
        let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let upright = Bool.random(using: &rng)
        return (0...n).map { i in
            let t = phase + dir * CGFloat(i) / CGFloat(n) * 2 * .pi
            let u = sin(t) * 0.48, v = sin(2 * t) * 0.42
            return CGPoint(x: a.midX + a.width * (upright ? v : u), y: a.midY + a.height * (upright ? u : v))
        }
    }

    private static func spiral<G: RandomNumberGenerator>(_ a: CGRect, _ rng: inout G) -> [CGPoint] {
        let n = 13
        let start = CGFloat.random(in: 0...(2 * .pi), using: &rng)
        let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let turns = CGFloat.random(in: 1.6...2.3, using: &rng)
        let outward = Bool.random(using: &rng)
        return (0..<n).map { i in
            var f = CGFloat(i) / CGFloat(n - 1)
            if outward { f = 1 - f }
            let t = start + dir * f * turns * 2 * .pi
            let r = 0.5 - 0.42 * f
            return CGPoint(x: a.midX + cos(t) * a.width * r, y: a.midY + sin(t) * a.height * r)
        }
    }
}

// MARK: - Simgelere çarpma

struct IconSlide: Equatable {
    let name: String
    let from: CGPoint
    let to: CGPoint
}

/// Masaüstü simgelerinin yerini tutar, robot değdiğinde simgenin nereye savrulacağını hesaplar.
final class IconField {
    static let contact: CGFloat = 72     // robot yarıçapı + simge yarıçapı
    static let spacing: CGFloat = 78     // iki simge üst üste binmesin
    static let cooldown = 0.9

    private(set) var icons: [String: CGPoint] = [:]
    var ignored: Set<String> = []        // toplanacak ekran görüntüleri itilmez
    var bounds: CGRect = .zero
    private var lastHit: [String: Double] = [:]

    var isEmpty: Bool { icons.isEmpty }

    func load(_ map: [String: CGPoint]) { icons = map; lastHit = [:] }
    func remove(_ name: String) { icons[name] = nil }
    func clear() { icons = [:]; ignored = []; lastHit = [:] }

    func hit(robot: CGPoint, heading: CGFloat, speed: CGFloat, now: Double, blocked: [CGRect]) -> [IconSlide] {
        var rng = SystemRandomNumberGenerator()
        return hit(robot: robot, heading: heading, speed: speed, now: now, blocked: blocked, using: &rng)
    }

    func hit<G: RandomNumberGenerator>(robot: CGPoint, heading: CGFloat, speed: CGFloat, now: Double,
                                       blocked: [CGRect], using rng: inout G) -> [IconSlide] {
        guard speed > 30 else { return [] }
        let h = CGPoint(x: cos(heading), y: sin(heading))
        // Finder'ın tepki süresini örtmek için temas biraz önceden algılanır.
        let lead = speed * 0.08
        let nose = CGPoint(x: robot.x + h.x * lead, y: robot.y + h.y * lead)
        var out: [IconSlide] = []
        for (name, p) in icons.sorted(by: { $0.key < $1.key }) where !ignored.contains(name) {
            guard hypot(p.x - nose.x, p.y - nose.y) < Self.contact,
                  now - (lastHit[name] ?? -100) >= Self.cooldown,
                  !blocked.contains(where: { $0.contains(p) }) else { continue }
            let dx = p.x - robot.x, dy = p.y - robot.y
            let d = max(hypot(dx, dy), 0.001)
            let n = CGPoint(x: dx / d, y: dy / d)
            guard n.x * h.x + n.y * h.y > -0.2 else { continue }   // arkada kalan simgeye çarpılmaz

            var angle = atan2(n.y * 0.7 + h.y * 0.3, n.x * 0.7 + h.x * 0.3)
            if abs(h.x * n.y - h.y * n.x) < 0.2 {     // tam karşıdan vurunca yolun kenarına savrulur
                angle += (Bool.random(using: &rng) ? 1 : -1) * CGFloat.random(in: 0.4...0.7, using: &rng)
            }
            guard let to = landing(for: name, from: p, angle: angle, distance: 60 + speed * 0.35,
                                   robot: robot, blocked: blocked) else { continue }
            icons[name] = to
            lastHit[name] = now
            out.append(IconSlide(name: name, from: p, to: to))
        }
        return out
    }

    private func landing(for name: String, from p: CGPoint, angle: CGFloat, distance: CGFloat,
                         robot: CGPoint, blocked: [CGRect]) -> CGPoint? {
        for factor in [CGFloat(1), 0.72, 0.48] {
            for turn in [CGFloat(0), 0.6, -0.6, 1.2, -1.2] {
                let a = angle + turn
                let c = CGPoint(x: min(max(p.x + cos(a) * distance * factor, bounds.minX), bounds.maxX),
                                y: min(max(p.y + sin(a) * distance * factor, bounds.minY), bounds.maxY))
                guard hypot(c.x - p.x, c.y - p.y) >= 26,
                      hypot(c.x - robot.x, c.y - robot.y) >= hypot(p.x - robot.x, p.y - robot.y),
                      !blocked.contains(where: { $0.insetBy(dx: -40, dy: -40).contains(c) }),
                      !icons.contains(where: { $0.key != name && hypot($0.value.x - c.x, $0.value.y - c.y) < Self.spacing })
                else { continue }
                return c
            }
        }
        return nil
    }
}

// MARK: - Finder bağlantısı

/// Gerçek masaüstü simgelerini okur ve kaydırır. Dosyaların kendisine dokunmaz, yalnızca yerlerini değiştirir.
enum FinderIcons {
    static let readScript = """
    set out to {}
    tell application "Finder"
        repeat with f in (get every item of desktop)
            try
                set p to desktop position of f
                set end of out to ((item 1 of p) as text) & "," & ((item 2 of p) as text) & "," & (name of f)
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return out as text
    """

    /// Bağımsız değişkenler: kare sayısı, x1, y1, x2, y2, ..., dosya adı.
    static let slideScript = """
    on run argv
        set c to (item 1 of argv) as integer
        set n to item (2 + c * 2) of argv
        try
            tell application "Finder" to set f to item n of desktop
            repeat with i from 0 to c - 1
                set x to (item (2 + i * 2) of argv) as integer
                set y to (item (3 + i * 2) of argv) as integer
                tell application "Finder" to set desktop position of f to {x, y}
                delay 0.012
            end repeat
        end try
    end run
    """

    /// Finder koordinatlarında, yavaşlayarak duran kaydırma kareleri.
    static func frames(_ s: IconSlide, screenHeight: CGFloat, count: Int = 9) -> [CGPoint] {
        (1...count).map { i in
            let t = CGFloat(i) / CGFloat(count)
            let e = 1 - pow(1 - t, 3)
            return CGPoint(x: (s.from.x + (s.to.x - s.from.x) * e).rounded(),
                           y: (screenHeight - (s.from.y + (s.to.y - s.from.y) * e)).rounded())
        }
    }

    static func parse(_ text: String, screenHeight: CGFloat) -> [String: CGPoint] {
        var out: [String: CGPoint] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]), !parts[2].isEmpty else { continue }
            out[String(parts[2])] = CGPoint(x: x, y: screenHeight - y)
        }
        return out
    }

    static func read(completion: @escaping ([String: CGPoint]) -> Void) {
        let height = DesktopMap.screen.frame.height
        DispatchQueue.global(qos: .userInitiated).async {
            let text = run(["-e", readScript], limit: 20, capture: true) ?? ""
            let map = parse(text, screenHeight: height)
            DispatchQueue.main.async { completion(map) }
        }
    }

    static func slide(_ s: IconSlide) {
        let frames = frames(s, screenHeight: DesktopMap.screen.frame.height)
        let args = ["-e", slideScript, String(frames.count)]
            + frames.flatMap { [String(Int($0.x)), String(Int($0.y))] } + [s.name]
        DispatchQueue.global(qos: .userInteractive).async { _ = run(args, limit: 6, capture: false) }
    }

    @discardableResult
    private static func run(_ args: [String], limit: Double, capture: Bool) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = args
        p.standardOutput = capture ? pipe : FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: killer)
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - İçine çekme hareketi

enum SuckMotion {
    struct Pose {
        let position: CGPoint
        let along: CGFloat     // çekiş yönündeki ölçek
        let across: CGFloat    // çekişe dik ölçek
        let spin: CGFloat
        let opacity: CGFloat
    }

    static let tug: CGFloat = 0.2      // önce direnir, sonra hızla kapılır

    static func pose(_ t: CGFloat, from a: CGPoint, to b: CGPoint, swirl: CGFloat) -> Pose {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 1)
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux
        if t < tug {
            let u = t / tug
            let shake = sin(u * .pi * 4) * (1 - u * 0.3)
            let lean = sin(u * .pi) * 9
            return Pose(position: CGPoint(x: a.x + ux * lean + px * shake * 3, y: a.y + uy * lean + py * shake * 3),
                        along: 1 + 0.16 * u, across: 1 - 0.08 * u, spin: shake * 0.1, opacity: 1)
        }
        let u = (t - tug) / (1 - tug)
        let e = pow(u, 2.4)
        let bend = sin(e * .pi) * 26 * swirl
        let size = 1 - 0.93 * pow(e, 0.8)
        let stretch = sin(e * .pi)
        return Pose(position: CGPoint(x: a.x + dx * e + px * bend, y: a.y + dy * e + py * bend),
                    along: size * (1.16 + 1.5 * stretch), across: size * (0.92 - 0.35 * stretch),
                    spin: swirl * e * e * 2 * .pi, opacity: t < 0.92 ? 1 : max(0, (1 - t) / 0.08))
    }

    /// Çekiş yönünde uzayan, dönerek küçülen görüntünün dönüşümü.
    static func transform(_ p: Pose, direction a: CGFloat) -> CATransform3D {
        var m = CATransform3DMakeRotation(p.spin, 0, 0, 1)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(-a, 0, 0, 1))
        m = CATransform3DConcat(m, CATransform3DMakeScale(p.along, p.across, 1))
        return CATransform3DConcat(m, CATransform3DMakeRotation(a, 0, 0, 1))
    }
}

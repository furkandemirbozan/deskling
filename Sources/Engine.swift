import CoreGraphics
import Foundation

struct Job {
    let id: String
    let point: CGPoint
    let shot: Shot?          // nil ise demo kartı: hiçbir dosyaya dokunulmaz
    let thumb: CGImage?
    var waypoint = false     // gezinti noktası: durmadan, kavis çizerek geçilir
}

enum Phase: Equatable {
    case docked, scanning, turning, driving, vacuuming, dumping, aligning, backing
}

/// Ekrandan bağımsız hareket motoru. Her karede `tick` ile ilerler.
final class RobotEngine {
    enum Leg { case job, trash, base }

    var onPickup: (Job) -> Bool = { _ in true }
    var onDump: (Int) -> Void = { _ in }
    var onPhaseChange: (Phase) -> Void = { _ in }
    var onMissionEnd: () -> Void = {}

    var maxSpeed: CGFloat = 240
    var capacity = 3
    var basePoint: CGPoint
    var trashPoint: CGPoint

    private(set) var pos: CGPoint
    private(set) var heading: CGFloat = 0
    private(set) var phase: Phase = .docked { didSet { if phase != oldValue { onPhaseChange(phase) } } }
    private(set) var battery: Double = 100
    private(set) var carrying = 0
    private(set) var paused = false
    private(set) var leg: Leg = .base
    private(set) var jobs: [Job] = []
    private(set) var current: Job?

    private var target: CGPoint = .zero
    private var aim: CGPoint = .zero
    private(set) var speed: CGFloat = 0
    private var phaseT: Double = 0
    private var waypointT: Double = 0
    private var missionActive = false

    /// Robot dosyanın üstüne çıkmaz, önünde durup onu içine çeker.
    static let standoff: CGFloat = 84

    private let lowBattery = 15.0
    private let resumeBattery = 60.0

    init(base: CGPoint, trash: CGPoint) {
        basePoint = base
        trashPoint = trash
        pos = base
    }

    var isIdle: Bool { phase == .docked && jobs.isEmpty && battery >= 100 }
    var isBusy: Bool { phase != .docked || !jobs.isEmpty }
    var isCharging: Bool { phase == .docked && !jobs.isEmpty }

    func start(_ newJobs: [Job]) {
        jobs += newJobs
        paused = false
        missionActive = true
        if phase == .docked, battery >= resumeBattery { setPhase(.scanning) }
    }

    func togglePause() { paused.toggle() }

    /// Kalan işleri iptal eder; hazne doluysa önce çöpe uğrayıp eve döner.
    func goHome() {
        jobs.removeAll()
        paused = false
        guard phase != .docked else {
            if missionActive { missionActive = false; onMissionEnd() }
            return
        }
        if leg == .job, phase == .turning || phase == .driving {
            current = nil
            advance()
        }
    }

    func tick(_ dt: Double) {
        guard !paused else { return }
        phaseT += dt
        switch phase {
        case .docked:
            battery = min(100, battery + 8 * dt)
            if !jobs.isEmpty, battery >= resumeBattery { setPhase(.scanning) }
        case .scanning:
            if phaseT >= 1.5 { advance() }
        case .turning:
            if rotate(toward: angle(to: aim), dt) { setPhase(.driving) }
        case .driving:
            if current?.waypoint == true { cruise(dt) } else { drive(dt) }
        case .vacuuming:
            if phaseT >= 1.4 { current = nil; advance() }
        case .dumping:
            if phaseT >= 1.4 { carrying = 0; advance() }
        case .aligning:
            if rotate(toward: 0, dt) { setPhase(.backing) }
        case .backing:
            let d = basePoint.x - pos.x, dy = basePoint.y - pos.y
            let dist = hypot(d, dy), step = CGFloat(70 * dt)
            if dist <= step {
                pos = basePoint
                setPhase(.docked)
                if jobs.isEmpty, missionActive { missionActive = false; onMissionEnd() }
            } else {
                pos.x += d / dist * step
                pos.y += dy / dist * step
            }
        }
    }

    // MARK: - Görev akışı

    private func advance() {
        if carrying > 0, carrying >= capacity || jobs.isEmpty || battery < lowBattery {
            go(.trash, trashPoint)
        } else if jobs.isEmpty || battery < lowBattery {
            go(.base, CGPoint(x: basePoint.x + 92, y: basePoint.y))
        } else {
            let i = jobs[0].waypoint ? 0 : jobs.indices.min { dist(jobs[$0].point) < dist(jobs[$1].point) }!
            let job = jobs.remove(at: i)
            current = job
            go(.job, job.point, stopShort: !job.waypoint)
        }
    }

    private func go(_ l: Leg, _ p: CGPoint, stopShort: Bool = false) {
        leg = l
        aim = p
        target = p
        if stopShort {
            let d = dist(p)
            target = d > Self.standoff
                ? CGPoint(x: p.x - (p.x - pos.x) / d * Self.standoff, y: p.y - (p.y - pos.y) / d * Self.standoff)
                : pos
        }
        speed = 0
        waypointT = 0
        setPhase(.turning)
    }

    /// Çarpınca robot bir an yavaşlar.
    func bumped() { speed *= 0.45 }

    private func arrive() {
        speed = 0
        switch leg {
        case .job:
            guard let job = current else { advance(); return }
            if onPickup(job) {
                carrying += 1
                setPhase(.vacuuming)
            } else {
                current = nil
                advance()
            }
        case .trash:
            setPhase(.dumping)
            onDump(carrying)
        case .base:
            setPhase(.aligning)
        }
    }

    private func setPhase(_ p: Phase) {
        phaseT = 0
        phase = p
    }

    // MARK: - Hareket

    private func drive(_ dt: Double) {
        let dx = target.x - pos.x, dy = target.y - pos.y
        let d = hypot(dx, dy)
        let accel: CGFloat = 420, decel: CGFloat = 380
        speed = min(maxSpeed, speed + accel * CGFloat(dt), sqrt(2 * decel * max(d, 0)) + 24)
        let step = speed * CGFloat(dt)
        battery = max(0, battery - 0.3 * dt)
        if d <= max(step, 1.5) {
            pos = target
            arrive()
            return
        }
        pos.x += dx / d * step
        pos.y += dy / d * step
        heading = atan2(dy, dx)
    }

    /// Gezintide noktalar arasında durmadan, direksiyon kırarak ilerler.
    private func cruise(_ dt: Double) {
        waypointT += dt
        if dist(target) < 52 || waypointT > 7 {
            if let next = jobs.first, next.waypoint, battery >= lowBattery {
                current = jobs.removeFirst()
                target = next.point
                aim = next.point
                waypointT = 0
            } else {
                current = nil
                advance()
            }
            return
        }
        let diff = shortest(angle(to: target) - heading)
        let turn = CGFloat(2.8 * dt)
        heading += min(max(diff, -turn), turn)
        let wanted = maxSpeed * (0.32 + 0.68 * max(0, cos(diff)))
        let change = CGFloat((wanted > speed ? 420 : 600) * dt)
        speed += min(max(wanted - speed, -change), change)
        pos.x += cos(heading) * speed * CGFloat(dt)
        pos.y += sin(heading) * speed * CGFloat(dt)
        battery = max(0, battery - 0.3 * dt)
    }

    private func shortest(_ a: CGFloat) -> CGFloat {
        var diff = a.truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        return diff
    }

    private func rotate(toward a: CGFloat, _ dt: Double) -> Bool {
        let diff = shortest(a - heading)
        let step = CGFloat(5.2 * dt)
        if abs(diff) <= step { heading = a; return true }
        heading += diff > 0 ? step : -step
        return false
    }

    private func angle(to p: CGPoint) -> CGFloat { atan2(p.y - pos.y, p.x - pos.x) }
    private func dist(_ p: CGPoint) -> CGFloat { hypot(p.x - pos.x, p.y - pos.y) }
}

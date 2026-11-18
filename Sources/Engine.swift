import CoreGraphics
import Foundation

struct Job {
    let id: String
    let point: CGPoint
    let shot: Shot?          // nil ise demo kartı: hiçbir dosyaya dokunulmaz
    let thumb: CGImage?
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
    private var speed: CGFloat = 0
    private var phaseT: Double = 0
    private var missionActive = false

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
            if rotate(toward: angle(to: target), dt) { setPhase(.driving) }
        case .driving:
            drive(dt)
        case .vacuuming:
            if phaseT >= 1.15 { current = nil; advance() }
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
            let i = jobs.indices.min { dist(jobs[$0].point) < dist(jobs[$1].point) }!
            current = jobs.remove(at: i)
            go(.job, current!.point)
        }
    }

    private func go(_ l: Leg, _ p: CGPoint) {
        leg = l
        target = p
        speed = 0
        setPhase(.turning)
    }

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

    private func rotate(toward a: CGFloat, _ dt: Double) -> Bool {
        var diff = (a - heading).truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        let step = CGFloat(5.2 * dt)
        if abs(diff) <= step { heading = a; return true }
        heading += diff > 0 ? step : -step
        return false
    }

    private func angle(to p: CGPoint) -> CGFloat { atan2(p.y - pos.y, p.x - pos.x) }
    private func dist(_ p: CGPoint) -> CGFloat { hypot(p.x - pos.x, p.y - pos.y) }
}

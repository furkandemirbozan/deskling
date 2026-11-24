import Foundation
import CoreGraphics

/// Bardaktaki sıvının yüzeyi: iki sönümlü yay.
/// - `tilt`: yüzeyin eğimi (ilk dalga kipi). Yatay ivme sıvıyı hareketin tersine yığar.
/// - `wave`: ortası kabarıp çöken ikinci kip. Dikey ivme ve ani duruşlar uyarır.
/// Bardak bırakılınca ikisi de birkaç saniyede durulur.
struct SloshPhysics {
    var tilt: Double = 0, tiltV: Double = 0
    var wave: Double = 0, waveV: Double = 0
    /// Yüzeyde sürekli dolaşan küçük kırışıklıklar için faz.
    var phase: Double = 0

    // Yay sabitleri: ilk kipin doğal frekansı ~1.6 Hz, ikincisi ~2.7 Hz; sönüm oranı ~0.1 ve ~0.14.
    var tiltK = 100.0, tiltC = 2.0
    var waveK = 290.0, waveC = 4.8
    /// İvmenin (pt/s²) eğime çevrilme katsayısı.
    var gain = 0.0016
    var maxTilt = 0.42
    var maxWave = 0.35

    /// Sabit adımla ilerler; ivme pt/s² cinsinden, y yukarı pozitif.
    mutating func step(dt: Double, accel: CGVector) {
        var left = min(dt, 0.25)
        while left > 0 {
            let h = min(left, 1.0 / 240)
            left -= h
            // Yarı örtük Euler: sert yaylarda bile kararlı.
            tiltV += (-tiltK * tilt - tiltC * tiltV - gain * accel.dx) * h
            tilt += tiltV * h
            waveV += (-waveK * wave - waveC * waveV + gain * 0.6 * abs(accel.dy) * (accel.dy < 0 ? 1 : -0.5)) * h
            wave += waveV * h
            if abs(tilt) > maxTilt { tilt = maxTilt * (tilt > 0 ? 1 : -1); tiltV *= -0.3 }
            if abs(wave) > maxWave { wave = maxWave * (wave > 0 ? 1 : -1); waveV *= -0.3 }
        }
        phase += dt * (1.3 + energy * 9)
    }

    /// Dokunma ya da süre bitince sarsılma gibi tek seferlik itki.
    mutating func kick(tilt t: Double, wave w: Double) {
        tiltV += t
        waveV += w
    }

    /// Kalan hareket enerjisi; durulmayı ölçmek ve kare hızını düşürmek için.
    var energy: Double {
        0.5 * (tiltV * tiltV + tiltK * tilt * tilt) / tiltK + 0.5 * (waveV * waveV + waveK * wave * wave) / waveK
    }

    var isCalm: Bool { energy < 1e-5 }

    /// Yüzeyin `u` (-1 sol kenar … 1 sağ kenar) noktasındaki yüksekliği, yarı genişlik `halfWidth` ile çarpılmış pt.
    func height(at u: Double, halfWidth: Double) -> Double {
        let ripple = min(0.03, energy * 4) * sin(u * 7 + phase * 3)
        return halfWidth * (tan(tilt) * u + wave * (0.5 - u * u) * 0.9 + ripple)
    }
}

/// Pencere konumlarından hız ve ivme tahmini (yumuşatılmış).
struct MotionTracker {
    private var last: CGPoint?
    private var velocity = CGVector.zero
    private(set) var accel = CGVector.zero

    mutating func update(_ p: CGPoint, dt: Double) {
        guard dt > 0 else { return }
        defer { last = p }
        guard let last else { return }
        let v = CGVector(dx: (p.x - last.x) / dt, dy: (p.y - last.y) / dt)
        let a = CGVector(dx: (v.dx - velocity.dx) / dt, dy: (v.dy - velocity.dy) / dt)
        let k = min(1, dt * 18)   // fare titremesi yüzeyi çırpınmaya çevirmesin
        accel = CGVector(dx: accel.dx + (a.dx - accel.dx) * k, dy: accel.dy + (a.dy - accel.dy) * k)
        velocity = v
        // Aşırı değerler (pencere ışınlanması gibi) kırpılır.
        let lim: CGFloat = 60_000
        accel = CGVector(dx: max(-lim, min(lim, accel.dx)), dy: max(-lim, min(lim, accel.dy)))
    }

    mutating func reset() {
        last = nil
        velocity = .zero
        accel = .zero
    }
}

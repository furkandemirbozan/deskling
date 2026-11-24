import CoreGraphics
import Foundation

/// Mat dokulu seramik kupa: kalın kulp, krem sırlı iç, koyu filtre kahve ve yüzeyde pencere yansıması.
enum CoffeeMug {
    static let mid: CGFloat = 96
    static let foot: CGFloat = 14, rim: CGFloat = 150
    static let outer = Profile(pts: [(14, 42.5), (18, 45), (40, 46), (100, 47), (150, 48)])
    static let tilt: CGFloat = 0.3
    static let lip: CGFloat = 3.2
    static let maxDepth: CGFloat = 27

    static let geo = DrinkGeo(mid: mid, bottom: rim - maxDepth, top: rim, rim: rim, rimHalf: 48,
                              interior: { outer.half($0) - lip }, opaque: true, steamRate: 11, tilt: tilt)

    /// Kupanın sırı: arduvaz mavisi.
    static func glaze(_ k: CGFloat, _ a: CGFloat = 1) -> CGColor {
        DrinkArt.rgb(0.28 * k, 0.34 * k, 0.4 * k, a)
    }

    static func bodyPath() -> CGPath {
        let p = CGMutablePath()
        let ry = outer.half(rim) * tilt
        p.move(to: CGPoint(x: mid - outer.half(foot), y: foot))
        var y = foot
        while y < rim { y = min(rim, y + 3); p.addLine(to: CGPoint(x: mid - outer.half(y), y: y)) }
        p.addPath(DrinkArt.halfEllipse(CGPoint(x: mid, y: rim), outer.half(rim), ry, upper: false))
        y = rim
        while y > foot { y = max(foot, y - 3); p.addLine(to: CGPoint(x: mid + outer.half(y), y: y)) }
        let fr = outer.half(foot)
        for i in 0...24 {
            let a = CGFloat.pi * CGFloat(i) / 24
            p.addLine(to: CGPoint(x: mid + cos(a) * fr, y: foot - sin(a) * fr * tilt * 0.55))
        }
        p.closeSubpath()
        return p
    }

    // MARK: - Durağan katmanlar

    static func back(_ ctx: CGContext) {
        typealias A = DrinkArt
        A.shadow(ctx, center: CGPoint(x: 108, y: 9), rx: 78, ry: 13, alpha: 0.38)
        A.shadow(ctx, center: CGPoint(x: 99, y: 8), rx: 48, ry: 8, alpha: 0.3)
        handle(ctx)
        let body = bodyPath()
        // Mat seramik: geniş ve yumuşak ışık, parlama yok
        A.fillAcross(ctx, body, from: mid - 48, to: mid + 48, [(0, glaze(0.55)), (0.16, glaze(0.92)), (0.34, glaze(1.18)),
                                                             (0.55, glaze(1.02)), (0.82, glaze(0.72)), (1, glaze(0.5))])
        A.fillDown(ctx, body, from: foot - 8, to: foot + 26, [(0, A.rgb(0, 0, 0, 0.35)), (1, A.rgb(0, 0, 0, 0))])
        // Sırdaki benekler: mat dokuyu verir
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        var r = SeededRandom(5)
        for _ in 0..<520 {
            let x = r.cg(mid - 48, mid + 48), y = r.cg(foot - 6, rim)
            let light = r.next() < 0.55
            ctx.setFillColor(light ? A.rgb(1, 1, 1, r.cg(0.03, 0.09)) : A.rgb(0, 0, 0, r.cg(0.04, 0.1)))
            let s = r.cg(0.3, 0.9)
            ctx.fillEllipse(in: A.ellipse(CGPoint(x: x, y: y), s, s))
        }
        // Dipte sırsız toprak bandı
        let raw = CGMutablePath()
        let fr = outer.half(foot)
        raw.move(to: CGPoint(x: mid - fr, y: foot + 4))
        for i in 0...24 {
            let a = CGFloat.pi * CGFloat(i) / 24
            raw.addLine(to: CGPoint(x: mid - cos(a) * fr, y: foot + 4 - sin(a) * fr * tilt * 0.55))
        }
        for i in stride(from: 24, through: 0, by: -1) {
            let a = CGFloat.pi * CGFloat(i) / 24
            raw.addLine(to: CGPoint(x: mid - cos(a) * (fr - 1), y: foot - 3 - sin(a) * fr * tilt * 0.55))
        }
        raw.closeSubpath()
        A.fillAcross(ctx, raw, from: mid - fr, to: mid + fr, [(0, A.rgb(0.5, 0.42, 0.34)), (0.35, A.rgb(0.82, 0.73, 0.62)), (1, A.rgb(0.45, 0.38, 0.3))])
        ctx.restoreGState()
        // Krem sırlı iç çeper
        let inner = outer.half(rim) - lip
        let opening = CGPath(ellipseIn: A.ellipse(CGPoint(x: mid, y: rim), inner, inner * tilt), transform: nil)
        A.fillDown(ctx, opening, from: rim + inner * tilt, to: rim - inner * tilt, [(0, A.rgb(0.95, 0.92, 0.86)), (0.55, A.rgb(0.84, 0.8, 0.73)), (1, A.rgb(0.62, 0.58, 0.52))])
    }

    private static func handle(_ ctx: CGContext) {
        typealias A = DrinkArt
        let x0 = mid + outer.half(120) - 3
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: 128))
        p.addCurve(to: CGPoint(x: x0 + 31, y: 100), control1: CGPoint(x: x0 + 24, y: 134), control2: CGPoint(x: x0 + 32, y: 120))
        p.addCurve(to: CGPoint(x: x0 - 1, y: 54), control1: CGPoint(x: x0 + 30, y: 74), control2: CGPoint(x: x0 + 20, y: 54))
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.addPath(p)
        ctx.setStrokeColor(glaze(0.5))
        ctx.setLineWidth(14)
        ctx.strokePath()
        ctx.addPath(p)
        ctx.setStrokeColor(glaze(0.85))
        ctx.setLineWidth(10.5)
        ctx.strokePath()
        ctx.translateBy(x: -1.4, y: 1.2)
        ctx.addPath(p)
        ctx.setStrokeColor(glaze(1.15))
        ctx.setLineWidth(4)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func front(_ ctx: CGContext) {
        typealias A = DrinkArt
        let h = outer.half(rim), ry = h * tilt
        // Sırsız, açık renkli ağız kenarı
        ctx.setStrokeColor(A.rgb(0.83, 0.79, 0.72))
        ctx.setLineWidth(lip)
        ctx.strokeEllipse(in: A.ellipse(CGPoint(x: mid, y: rim), h - lip / 2, ry - lip / 2 * tilt))
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), h, ry, upper: false))
        ctx.setStrokeColor(glaze(0.6, 0.8))
        ctx.setLineWidth(0.8)
        ctx.strokePath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim + 0.6), h - 1.6, ry - 0.6, upper: true))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.55))
        ctx.setLineWidth(0.7)
        ctx.strokePath()
    }

    // MARK: - Her kare

    static func liquid(_ ctx: CGContext, _ s: DrinkState, _ p: DrinkParticles) {
        typealias A = DrinkArt
        let inner = outer.half(rim) - lip
        let opening = CGPath(ellipseIn: A.ellipse(CGPoint(x: mid, y: rim), inner, inner * tilt), transform: nil)
        ctx.saveGState()
        ctx.addPath(opening)
        ctx.clip()
        let level = CGFloat(min(1, max(0, s.level)))
        let d = (1 - level) * maxDepth
        // Seviye düştükçe çeperde kalan ince kahve halkaları
        if level < 0.97 {
            for k in 1...3 {
                let ringD = CGFloat(k) / 4 * maxDepth
                guard ringD < d - 2 else { continue }
                ctx.setStrokeColor(A.rgb(0.42, 0.26, 0.14, 0.22))
                ctx.setLineWidth(0.8)
                ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim - ringD), inner, inner * tilt, upper: true))
                ctx.strokePath()
            }
        }
        if level > 0.002 {
            let rx = inner - d * 0.04, ry = rx * tilt, cy = rim - d
            var front: [CGPoint] = [], back: [CGPoint] = []
            let n = 30
            for i in 0...n {
                let u = Double(i) / Double(n) * 2 - 1
                let hgt = CGFloat(s.slosh.height(at: u, halfWidth: Double(rx))) * 0.5
                let e = ry * CGFloat(sqrt(max(0, 1 - u * u)))
                front.append(CGPoint(x: mid + CGFloat(u) * rx, y: cy + hgt - e))
                back.append(CGPoint(x: mid + CGFloat(u) * rx, y: cy + hgt + e))
            }
            let top = CGMutablePath()
            top.addLines(between: front)
            for pt in back.reversed() { top.addLine(to: pt) }
            top.closeSubpath()
            ctx.saveGState()
            ctx.addPath(top)
            ctx.clip()
            ctx.saveGState()
            ctx.translateBy(x: mid, y: cy)
            ctx.scaleBy(x: 1, y: ry / rx)
            ctx.drawRadialGradient(A.gradient([(0, A.rgb(0.2, 0.1, 0.05)), (0.7, A.rgb(0.15, 0.07, 0.03)), (0.9, A.rgb(0.32, 0.18, 0.08)), (1, A.rgb(0.5, 0.31, 0.15))]),
                                   startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [.drawsAfterEndLocation])
            ctx.restoreGState()
            // Pencere yansıması: sıvı dalgalanınca kayar ve titrer
            let shift = CGFloat(s.slosh.tilt * 60)
            let wob = CGFloat(sin(s.slosh.phase * 2.3)) * CGFloat(min(1, s.slosh.energy * 300)) * 2
            let refl = CGRect(x: mid - rx * 0.5 + shift + wob, y: cy + ry * 0.12, width: rx * 0.5, height: ry * 0.42)
            ctx.saveGState()
            ctx.translateBy(x: refl.midX, y: refl.midY)
            ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.6, d: 1, tx: 0, ty: 0))
            let rp = CGPath(roundedRect: CGRect(x: -refl.width / 2, y: -refl.height / 2, width: refl.width, height: refl.height),
                            cornerWidth: 3, cornerHeight: 2, transform: nil)
            ctx.addPath(rp)
            ctx.setFillColor(A.rgb(1, 1, 1, 0.13))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.restoreGState()
            // Kenarda ince krema halkası
            ctx.addPath(top)
            ctx.setStrokeColor(A.rgb(0.58, 0.38, 0.2, 0.7))
            ctx.setLineWidth(1.2)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

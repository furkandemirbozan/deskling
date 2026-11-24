import CoreGraphics
import Foundation

/// Kalın camlı bira bardağı: kehribar bira, yoğun köpük, yükselen baloncuklar, terleyen cam ve köpük izleri.
enum BeerPint {
    static let mid: CGFloat = 110
    static let foot: CGFloat = 12, base: CGFloat = 27, rim: CGFloat = 196
    static let outer = Profile(pts: [(12, 35), (22, 36.5), (80, 40), (140, 44), (165, 47.4), (176, 49.6), (185, 48.6), (196, 48)])
    static let wall: CGFloat = 3
    static let fullFoam: CGFloat = 22

    static let geo = DrinkGeo(mid: mid, bottom: base, top: 168, rim: rim, rimHalf: 48,
                              interior: { outer.half($0) - wall }, bubbles: true, tilt: 0.15)

    static func foamHeight(_ s: DrinkState) -> CGFloat {
        guard s.phase == .focus else { return fullFoam }
        return 4.5 + (fullFoam - 4.5) * CGFloat(pow(1 - s.progress, 0.9))
    }

    static func foamTop(_ g: DrinkGeo, _ s: DrinkState) -> CGFloat {
        min(g.rim + 6, g.surface(s.level) + foamHeight(s) * CGFloat(min(1, s.level * 8)))
    }

    // MARK: - Durağan katmanlar

    static func back(_ ctx: CGContext) {
        typealias A = DrinkArt
        A.shadow(ctx, center: CGPoint(x: 112, y: 10), rx: 60, ry: 10, alpha: 0.34)
        // Biradan masaya düşen sarı ışık
        ctx.saveGState()
        ctx.translateBy(x: 128, y: 9)
        ctx.scaleBy(x: 1, y: 0.2)
        ctx.drawRadialGradient(A.gradient([(0, A.rgb(1, 0.7, 0.2, 0.3)), (1, A.rgb(1, 0.7, 0.2, 0))]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 40, options: [])
        ctx.restoreGState()
        let glass = A.silhouette(mid: mid, from: foot, to: rim, half: outer.half)
        ctx.addPath(glass)
        ctx.setFillColor(A.rgb(1, 1, 1, 0.06))
        ctx.fillPath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), 48, 7.2, upper: true))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.45))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    static func front(_ ctx: CGContext) {
        typealias A = DrinkArt
        let glass = A.silhouette(mid: mid, from: foot, to: rim, half: outer.half)
        // Kalın cam: kenarlarda koyu kırılma bandı
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.addPath(glass)
        ctx.setStrokeColor(A.rgb(0.25, 0.2, 0.1, 0.2))
        ctx.setLineWidth(7)
        ctx.strokePath()
        // Soğuk camın üstündeki ince buğu noktaları
        var r = SeededRandom(99)
        for _ in 0..<520 {
            let y = r.cg(30, 178), u = r.cg(-0.97, 0.97)
            ctx.setFillColor(A.rgb(1, 1, 1, r.cg(0.06, 0.16)))
            let s = r.cg(0.25, 0.7)
            ctx.fillEllipse(in: A.ellipse(CGPoint(x: mid + u * outer.half(y), y: y), s, s))
        }
        ctx.restoreGState()
        ctx.addPath(glass)
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.5))
        ctx.setLineWidth(0.9)
        ctx.strokePath()
        // Kalın dip
        let block = A.silhouette(mid: mid, from: foot, to: base, half: outer.half)
        A.fillAcross(ctx, block, from: mid - 36, to: mid + 36, [(0, A.rgb(1, 1, 1, 0.14)), (0.3, A.rgb(1, 0.95, 0.8, 0.5)),
                                                              (0.6, A.rgb(1, 0.8, 0.4, 0.3)), (1, A.rgb(1, 1, 1, 0.16))])
        for (y, a): (CGFloat, CGFloat) in [(foot, 0.6), (base, 0.45)] {
            ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: y), outer.half(y) - 1, 5, upper: false))
            ctx.setStrokeColor(A.rgb(1, 1, 1, a))
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
        // Şişkin bel halkası (nonik) ve ışık şeritleri
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: 176), outer.half(176) - 0.5, 7.3, upper: false))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.35))
        ctx.setLineWidth(1.6)
        ctx.strokePath()
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: -0.86, u1: -0.68, from: 26, to: 192, alpha: 0.55)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: -0.56, u1: -0.5, from: 60, to: 170, alpha: 0.22)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: 0.74, u1: 0.84, from: 30, to: 190, alpha: 0.3)
        // Yoğuşma damlaları: koyu kenar, parlak tepe, alt tarafta biranın kırılan ışığı
        for _ in 0..<64 {
            let y = r.cg(34, 172), u = r.cg(-0.9, 0.9)
            let x = mid + u * outer.half(y)
            let rad = r.cg(0.8, 2.3) * (1 - abs(u) * 0.35)
            drop(ctx, CGPoint(x: x, y: y), rad, squash: 1 - abs(u) * 0.4)
        }
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), 48, 7.2, upper: false))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.8))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }

    static func drop(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, squash: CGFloat = 1) {
        typealias A = DrinkArt
        let rx = r * squash, ry = r * 1.12
        ctx.setFillColor(A.rgb(0.2, 0.15, 0.05, 0.16))
        ctx.fillEllipse(in: A.ellipse(c, rx, ry))
        ctx.setFillColor(A.rgb(1, 0.92, 0.7, 0.28))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: c.x, y: c.y - ry * 0.25), rx * 0.75, ry * 0.6))
        ctx.setFillColor(A.rgb(1, 1, 1, 0.9))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: c.x - rx * 0.35, y: c.y + ry * 0.4), max(0.35, rx * 0.28), max(0.35, ry * 0.22)))
    }

    // MARK: - Her kare

    static func liquid(_ ctx: CGContext, _ s: DrinkState, _ p: DrinkParticles) {
        typealias A = DrinkArt
        let g = geo
        let surface = g.surface(s.level)
        let half = g.interior(surface)
        // Köpük izleri: biranın çekildiği yerlerde camın iç yüzünde kalan dantel
        if !p.lacing.isEmpty {
            for (i, y) in p.lacing.enumerated() where y > foamTop(g, s) + 2 {
                var r = SeededRandom(UInt64(200 + i))
                let h = g.interior(y)
                // Her yudum camda ince, kopuk kopuk bir köpük çizgisi bırakır; aşağı doğru ince sarkmalar
                var u = r.cg(-0.95, -0.7)
                while u < 0.95 {
                    let len = r.cg(0.05, 0.22)
                    let yy = y + r.cg(-1.5, 1.5) - abs(u) * 2.2
                    let pts = stride(from: u, through: min(0.95, u + len), by: 0.02).map {
                        CGPoint(x: mid + $0 * h, y: yy + sin($0 * 40 + CGFloat(i)) * 0.6 - abs($0) * 0.8)
                    }
                    ctx.addLines(between: pts)
                    ctx.setStrokeColor(A.rgb(1, 0.99, 0.95, r.cg(0.18, 0.42)))
                    ctx.setLineWidth(r.cg(0.5, 1.3))
                    ctx.strokePath()
                    if r.next() < 0.5 {
                        let x = mid + (u + len * 0.5) * h
                        ctx.setFillColor(A.rgb(1, 0.99, 0.95, r.cg(0.12, 0.3)))
                        ctx.fillEllipse(in: A.ellipse(CGPoint(x: x, y: yy - r.cg(1, 3)), r.cg(0.4, 1), r.cg(1, 2.6)))
                    }
                    u += len + r.cg(0.04, 0.2)
                }
            }
        }
        if s.level > 0.004 {
            let shape = A.liquidShape(g, s, level: s.level)
            A.fillAcross(ctx, shape.body, from: mid - half - 2, to: mid + half + 2, [
                (0, A.rgb(0.55, 0.26, 0.02, 0.94)), (0.18, A.rgb(0.82, 0.45, 0.06, 0.9)), (0.42, A.rgb(0.99, 0.73, 0.22, 0.84)),
                (0.66, A.rgb(0.95, 0.62, 0.14, 0.86)), (0.88, A.rgb(0.72, 0.36, 0.04, 0.92)), (1, A.rgb(0.5, 0.22, 0.02, 0.95))])
            A.fillDown(ctx, shape.body, from: g.bottom, to: surface, [(0, A.rgb(0.35, 0.12, 0, 0.35)), (0.5, A.rgb(0.35, 0.12, 0, 0.08)), (1, A.rgb(1, 0.9, 0.5, 0.12))])
            // Baloncuklar
            ctx.saveGState()
            ctx.addPath(shape.body)
            ctx.clip()
            for b in p.bubbles {
                let c = CGPoint(x: b.x, y: b.y), r = CGFloat(b.r)
                ctx.setFillColor(A.rgb(1, 0.97, 0.85, 0.28))
                ctx.fillEllipse(in: A.ellipse(c, r, r))
                ctx.setStrokeColor(A.rgb(1, 1, 0.95, 0.65))
                ctx.setLineWidth(0.35)
                ctx.strokeEllipse(in: A.ellipse(c, r, r))
                ctx.setFillColor(A.rgb(1, 1, 1, 0.9))
                ctx.fillEllipse(in: A.ellipse(CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.35), r * 0.3, r * 0.3))
            }
            ctx.restoreGState()
            foam(ctx, s, shape.front, surface)
        }
    }

    /// Kabarık beyaz köpük: önü krem rengi, üstü inişli çıkışlı, içinde ince kabarcık dokusu.
    private static func foam(_ ctx: CGContext, _ s: DrinkState, _ liquidFront: [CGPoint], _ surface: CGFloat) {
        typealias A = DrinkArt
        let g = geo
        let topY = foamTop(g, s)
        guard topY > surface + 1 else { return }
        let n = 30
        var bottomPts: [CGPoint] = [], topFront: [CGPoint] = [], topBack: [CGPoint] = []
        for i in 0...n {
            let u = Double(i) / Double(n) * 2 - 1
            let slosh = CGFloat(s.slosh.height(at: u, halfWidth: Double(g.interior(topY)))) * 0.8
            let bump = CGFloat(sin(u * 9 + 1.3) * 0.9 + sin(u * 23 + 0.4) * 0.45 + sin(s.time * 0.9 + u * 5) * 0.25)
            let y = min(rim + 6, topY + slosh + bump)
            let h = min(outer.half(min(y, rim)) - 0.6, g.interior(y) + (y > rim - 2 ? 2 : 0))
            let e = h * g.tilt * CGFloat(sqrt(max(0, 1 - u * u)))
            topFront.append(CGPoint(x: mid + CGFloat(u) * h, y: y - e))
            topBack.append(CGPoint(x: mid + CGFloat(u) * h, y: min(y + e, rim + 7)))
            let lb = liquidFront[min(liquidFront.count - 1, Int(Double(i) / Double(n) * Double(liquidFront.count - 1)))]
            bottomPts.append(CGPoint(x: mid + CGFloat(u) * g.interior(lb.y), y: lb.y))
        }
        let body = CGMutablePath()
        body.addLines(between: bottomPts)
        for pt in topBack.reversed() { body.addLine(to: pt) }
        body.closeSubpath()
        let h = g.interior(topY)
        A.fillAcross(ctx, body, from: mid - h, to: mid + h, [(0, A.rgb(0.82, 0.79, 0.7)), (0.25, A.rgb(0.97, 0.95, 0.9)),
                                                           (0.45, A.rgb(1, 0.99, 0.96)), (0.8, A.rgb(0.92, 0.9, 0.84)), (1, A.rgb(0.78, 0.75, 0.66))])
        // Bira ile köpüğün birleştiği sarımsı geçiş
        A.fillDown(ctx, body, from: surface - 2, to: surface + 5, [(0, A.rgb(1, 0.82, 0.4, 0.75)), (1, A.rgb(1, 0.9, 0.6, 0))])
        let top = CGMutablePath()
        top.addLines(between: topFront)
        for pt in topBack.reversed() { top.addLine(to: pt) }
        top.closeSubpath()
        A.fillAcross(ctx, top, from: mid - h, to: mid + h, [(0, A.rgb(0.93, 0.92, 0.88)), (0.4, A.rgb(1, 1, 0.99)), (1, A.rgb(0.9, 0.88, 0.82))])
        ctx.saveGState()
        ctx.addPath(body)
        ctx.addPath(top)
        ctx.clip()
        var r = SeededRandom(64)
        ctx.setLineWidth(0.35)
        for _ in 0..<90 {
            let u = r.cg(-0.95, 0.95), v = r.cg(0, 1)
            let y = surface + (topY - surface + 6) * v
            let rad = r.cg(0.4, 1.5)
            ctx.setStrokeColor(A.rgb(0.72, 0.66, 0.52, r.cg(0.25, 0.6)))
            ctx.strokeEllipse(in: A.ellipse(CGPoint(x: mid + u * g.interior(y), y: y), rad, rad * 0.85))
        }
        ctx.restoreGState()
        ctx.addLines(between: topFront)
        ctx.setStrokeColor(A.rgb(0.78, 0.74, 0.64, 0.6))
        ctx.setLineWidth(0.6)
        ctx.strokePath()
    }

    /// Camın dışındaki buğu ve arada bir aşağı kayan damlalar.
    static func overlay(_ ctx: CGContext, _ s: DrinkState, _ p: DrinkParticles) {
        typealias A = DrinkArt
        let glass = A.silhouette(mid: mid, from: foot, to: rim, half: outer.half)
        let cold = geo.surface(s.level) + 2
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.clip(to: CGRect(x: 0, y: 0, width: DrinkArt.canvas.width, height: cold))
        // Soğuk sıvının olduğu yerde cam buğulanır
        ctx.drawLinearGradient(A.gradient([(0, A.rgb(1, 1, 1, 0.1)), (1, A.rgb(1, 1, 1, 0.04))]),
                               start: CGPoint(x: 0, y: foot), end: CGPoint(x: 0, y: cold), options: [])
        for d in p.sliders {
            let x = CGFloat(d.x), y = CGFloat(d.y), r = CGFloat(d.r)
            // Damlanın sildiği iz buğusuz, daha berrak
            ctx.setStrokeColor(A.rgb(0.25, 0.18, 0.05, 0.1))
            ctx.setLineWidth(r * 1.1)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: x, y: CGFloat(d.startY)))
            ctx.addLine(to: CGPoint(x: x + sin(y * 0.2) * 0.5, y: y + r))
            ctx.strokePath()
            drop(ctx, CGPoint(x: x, y: y), r * 1.1)
        }
        ctx.restoreGState()
    }
}

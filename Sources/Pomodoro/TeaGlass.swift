import CoreGraphics
import Foundation

/// İnce belli çay bardağı: kalın camlı dip, tavşan kanı çay, porselen tabak ve küçük metal kaşık.
enum TeaGlass {
    static let mid: CGFloat = 110
    // Gerçek bardağın oranları: boy ağız çapının ~1.6 katı, altta tombul göbek, ortada belirgin bel.
    static let foot: CGFloat = 28, base: CGFloat = 36, rim: CGFloat = 133
    static let rimHalf: CGFloat = 33, rimRY: CGFloat = 5.4
    static let outer = Profile(pts: [(28, 23), (33, 26.6), (46, 29.8), (59.5, 27.4), (72, 21.4), (86, 22.4),
                                     (104, 27.6), (120, 31.4), (133, 33)])
    static let wall: CGFloat = 2.1

    static let geo = DrinkGeo(mid: mid, bottom: base, top: 124, rim: rim, rimHalf: rimHalf,
                              interior: { outer.half($0) - wall }, steamRate: 10, tilt: 0.16)

    static let saucer = CGPoint(x: 110, y: 25)

    // MARK: - Durağan katmanlar

    static func back(_ ctx: CGContext) {
        typealias A = DrinkArt
        A.shadow(ctx, center: CGPoint(x: 112, y: 15), rx: 84, ry: 13, alpha: 0.32)
        // Tabak: alt kalınlık, üst yüz, altın kenar, kırmızı halka ve bardağın oturduğu yuva
        ctx.setFillColor(A.rgb(0.72, 0.72, 0.75))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: 110, y: 21), 71, 12.5))
        let top = CGPath(ellipseIn: A.ellipse(saucer, 71, 12.4), transform: nil)
        A.fillAcross(ctx, top, from: 39, to: 181, [(0, A.rgb(0.86, 0.86, 0.89)), (0.3, A.rgb(0.99, 0.99, 1)),
                                                    (0.7, A.rgb(0.95, 0.95, 0.97)), (1, A.rgb(0.8, 0.8, 0.84))])
        ctx.setStrokeColor(A.rgb(0.83, 0.63, 0.25))
        ctx.setLineWidth(1.4)
        ctx.strokeEllipse(in: A.ellipse(saucer, 70.3, 11.8))
        ctx.setStrokeColor(A.rgb(0.66, 0.08, 0.1, 0.85))
        ctx.setLineWidth(1.6)
        ctx.strokeEllipse(in: A.ellipse(saucer, 60, 10.2))
        ctx.setStrokeColor(A.rgb(0.83, 0.63, 0.25, 0.8))
        ctx.setLineWidth(0.6)
        ctx.strokeEllipse(in: A.ellipse(saucer, 56.5, 9.6))
        let well = CGPath(ellipseIn: A.ellipse(CGPoint(x: 110, y: 26.5), 31, 5.6), transform: nil)
        A.fillDown(ctx, well, from: 32, to: 21, [(0, A.rgb(0.8, 0.8, 0.84)), (1, A.rgb(0.97, 0.97, 0.99))])
        // Bardağın tabağa düşen gölgesi ve camdan geçen kırmızı ışık
        A.shadow(ctx, center: CGPoint(x: 113, y: 27), rx: 30, ry: 5.5, alpha: 0.22)
        ctx.saveGState()
        ctx.translateBy(x: 126, y: 23)
        ctx.scaleBy(x: 1, y: 0.18)
        ctx.drawRadialGradient(A.gradient([(0, A.rgb(0.85, 0.25, 0.08, 0.28)), (1, A.rgb(0.85, 0.25, 0.08, 0))]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 26, options: [])
        ctx.restoreGState()
        // Camın arka yüzü ve arka ağız kenarı
        let glass = A.silhouette(mid: mid, from: foot, to: rim, half: outer.half)
        ctx.addPath(glass)
        ctx.setFillColor(A.rgb(1, 1, 1, 0.05))
        ctx.fillPath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), rimHalf, rimRY, upper: true))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.4))
        ctx.setLineWidth(0.9)
        ctx.strokePath()
    }

    static func front(_ ctx: CGContext) {
        typealias A = DrinkArt
        let glass = A.silhouette(mid: mid, from: foot, to: rim, half: outer.half)
        // Cam kalınlığı: kenarlara doğru koyulaşan ince bant
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.addPath(glass)
        ctx.setStrokeColor(A.rgb(0.2, 0.2, 0.25, 0.18))
        ctx.setLineWidth(4.5)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(glass)
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.45))
        ctx.setLineWidth(0.8)
        ctx.strokePath()
        // Kalın dip: ışığı kıran cam blok
        let block = A.silhouette(mid: mid, from: foot, to: base, half: outer.half)
        A.fillAcross(ctx, block, from: mid - 26, to: mid + 26, [(0, A.rgb(1, 1, 1, 0.12)), (0.3, A.rgb(1, 1, 1, 0.5)),
                                                                (0.55, A.rgb(1, 0.9, 0.85, 0.22)), (1, A.rgb(1, 1, 1, 0.14))])
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: base), outer.half(base) - 1, 3.6, upper: false))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.55))
        ctx.setLineWidth(0.9)
        ctx.strokePath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: foot), outer.half(foot), 3.4, upper: false))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.6))
        ctx.setLineWidth(1.1)
        ctx.strokePath()
        // Işık şeritleri: solda uzun ve parlak, sağda ince yansıma, belde kısa bir parıltı
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: -0.84, u1: -0.66, from: 37, to: 130, alpha: 0.62)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: -0.52, u1: -0.46, from: 96, to: 127, alpha: 0.32)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: 0.72, u1: 0.8, from: 42, to: 128, alpha: 0.28)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: 0.16, u1: 0.3, from: 39, to: 58, alpha: 0.18)
        // Ön ağız kenarı
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), rimHalf, rimRY, upper: false))
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.75))
        ctx.setLineWidth(1.4)
        ctx.strokePath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim - 0.4), rimHalf - 1.5, rimRY - 0.6, upper: false))
        ctx.setStrokeColor(A.rgb(0.3, 0.3, 0.35, 0.18))
        ctx.setLineWidth(0.6)
        ctx.strokePath()
    }

    // MARK: - Her kare

    static func liquid(_ ctx: CGContext, _ s: DrinkState, _ p: DrinkParticles) {
        typealias A = DrinkArt
        guard s.level > 0.003 else { return }
        let g = geo
        let shape = A.liquidShape(g, s, level: s.level)
        let half = g.interior(g.surface(s.level * 0.5))
        // Derinlikli tavşan kanı: kenarlarda koyu, ışığın geçtiği ortada parlak
        A.fillAcross(ctx, shape.body, from: mid - half - 2, to: mid + half + 2, [
            (0, A.rgb(0.3, 0.04, 0.02, 0.95)), (0.18, A.rgb(0.55, 0.11, 0.04, 0.93)), (0.4, A.rgb(0.8, 0.25, 0.08, 0.9)),
            (0.62, A.rgb(0.72, 0.19, 0.06, 0.9)), (0.86, A.rgb(0.48, 0.08, 0.03, 0.93)), (1, A.rgb(0.28, 0.03, 0.02, 0.95))])
        let surf = g.surface(s.level)
        A.fillDown(ctx, shape.body, from: g.bottom, to: surf, [(0, A.rgb(0.1, 0, 0, 0.4)), (0.45, A.rgb(0.1, 0, 0, 0.08)), (1, A.rgb(0, 0, 0, 0))])
        // Dipte toplanan kırık ışık
        ctx.saveGState()
        ctx.addPath(shape.body)
        ctx.clip()
        let caustic = CGPoint(x: mid + 8, y: g.bottom + 10)
        ctx.drawRadialGradient(A.gradient([(0, A.rgb(1, 0.55, 0.22, 0.42)), (1, A.rgb(1, 0.4, 0.1, 0))]),
                               startCenter: caustic, startRadius: 0, endCenter: caustic, endRadius: 20, options: [])
        ctx.restoreGState()
        // Yüzey: koyu çay üstünde gökyüzü yansıması ve ön kenarda ince menisküs
        A.fillAcross(ctx, shape.top, from: mid - half, to: mid + half, [
            (0, A.rgb(0.42, 0.08, 0.03, 0.95)), (0.3, A.rgb(0.68, 0.3, 0.2, 0.95)), (0.55, A.rgb(0.55, 0.16, 0.06, 0.95)),
            (1, A.rgb(0.36, 0.06, 0.02, 0.95))])
        ctx.addLines(between: shape.front)
        ctx.setStrokeColor(A.rgb(1, 0.75, 0.6, 0.35))
        ctx.setLineWidth(0.7)
        ctx.strokePath()
    }

    /// Tabaktaki kaşık; süre bitince tabakta şıngırdar.
    static func overlay(_ ctx: CGContext, _ s: DrinkState, _ p: DrinkParticles) {
        typealias A = DrinkArt
        let rattle = s.shake > 0 ? CGFloat(sin(s.time * 52) * 0.16 * s.shake) : 0
        let hop = s.shake > 0 ? CGFloat(abs(sin(s.time * 39)) * 2.2 * s.shake) : 0
        let pivot = CGPoint(x: 151, y: 24)
        A.shadow(ctx, center: CGPoint(x: pivot.x + 17, y: pivot.y - 2), rx: 26, ry: 3.2, alpha: 0.18 * (1 - min(1, hop / 3)))
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y + hop)
        ctx.rotate(by: 0.2 + rattle)
        let metal: [(CGFloat, CGColor)] = [(0, A.rgb(0.5, 0.52, 0.56)), (0.35, A.rgb(0.97, 0.97, 0.99)),
                                            (0.6, A.rgb(0.74, 0.76, 0.8)), (1, A.rgb(0.46, 0.48, 0.52))]
        // Sap: uca doğru incelir, ucunda küçük topuz
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: 6, y: 1.4))
        handle.addLine(to: CGPoint(x: 39, y: 1.1))
        handle.addQuadCurve(to: CGPoint(x: 39, y: -1.1), control: CGPoint(x: 41.5, y: 0))
        handle.addLine(to: CGPoint(x: 6, y: -1.4))
        handle.closeSubpath()
        A.fillDown(ctx, handle, from: 1.4, to: -1.4, metal)
        let bowl = CGPath(ellipseIn: A.ellipse(CGPoint(x: 0, y: 0), 8.6, 4.3), transform: nil)
        A.fillDown(ctx, bowl, from: 4.3, to: -4.3, metal)
        ctx.addPath(bowl)
        ctx.setStrokeColor(A.rgb(0.4, 0.42, 0.46, 0.6))
        ctx.setLineWidth(0.4)
        ctx.strokePath()
        ctx.setFillColor(A.rgb(1, 1, 1, 0.8))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: -2.4, y: 1.5), 2.6, 0.9))
        ctx.restoreGState()
    }
}

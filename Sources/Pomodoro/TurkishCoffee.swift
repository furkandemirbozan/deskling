import CoreGraphics
import Foundation

/// Türk kahvesi: altın yaldızlı, lale motifli porselen fincan ve tabağı; nefes alan köpük, azaldıkça çeperde kalan telve.
enum TurkishCoffee {
    static let mid: CGFloat = 110
    static let foot: CGFloat = 27, rim: CGFloat = 104
    static let outer = Profile(pts: [(27, 20.5), (31, 25.5), (40, 30.5), (60, 34.8), (82, 37.3), (104, 38.6)])
    static let tilt: CGFloat = 0.34
    static let lip: CGFloat = 1.8
    /// Görünen en derin sıvı yüzeyi (fincan boşken bile dibi biraz görünsün).
    static let maxDepth: CGFloat = 23

    static let geo = DrinkGeo(mid: mid, bottom: rim - maxDepth, top: rim, rim: rim, rimHalf: 38.6,
                              interior: { outer.half($0) - lip }, opaque: true, steamRate: 15, tilt: tilt)

    static let gold = DrinkArt.rgb(0.86, 0.66, 0.26)
    static let bordo = DrinkArt.rgb(0.5, 0.05, 0.09)

    /// Silindir üzerindeki yatay çember: önden bakınca alt yarım elips.
    static func ring(_ y: CGFloat) -> (CGFloat) -> CGFloat {
        let half = outer.half(y), ry = half * tilt
        return { x in
            let u = max(-1, min(1, (x - mid) / half))
            return y - ry * sqrt(1 - u * u)
        }
    }

    /// İki çember arasındaki bant (motif şeridi).
    static func band(_ y0: CGFloat, _ y1: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let n = 40
        let h0 = outer.half(y0), h1 = outer.half(y1)
        for i in 0...n {
            let u = CGFloat(i) / CGFloat(n) * 2 - 1
            let pt = CGPoint(x: mid + u * h0, y: y0 - h0 * tilt * sqrt(1 - u * u))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        for i in stride(from: n, through: 0, by: -1) {
            let u = CGFloat(i) / CGFloat(n) * 2 - 1
            p.addLine(to: CGPoint(x: mid + u * h1, y: y1 - h1 * tilt * sqrt(1 - u * u)))
        }
        p.closeSubpath()
        return p
    }

    /// Fincanın yanından görünen gövdesi: üstte ağız elipsinin ön yarısıyla biter.
    static func bodyPath() -> CGPath {
        let p = CGMutablePath()
        let ry = outer.half(rim) * tilt
        p.move(to: CGPoint(x: mid - outer.half(foot), y: foot))
        var y = foot
        while y < rim { y = min(rim, y + 2); p.addLine(to: CGPoint(x: mid - outer.half(y), y: y)) }
        p.addPath(DrinkArt.halfEllipse(CGPoint(x: mid, y: rim), outer.half(rim), ry, upper: false))
        y = rim
        while y > foot { y = max(foot, y - 2); p.addLine(to: CGPoint(x: mid + outer.half(y), y: y)) }
        // Alt kenar da elips: dip yuvarlak görünür
        let fr = outer.half(foot)
        for i in 0...20 {
            let a = CGFloat.pi * CGFloat(i) / 20
            p.addLine(to: CGPoint(x: mid + cos(a) * fr, y: foot - sin(a) * fr * tilt * 0.5))
        }
        p.closeSubpath()
        return p
    }

    // MARK: - Durağan katmanlar

    static func back(_ ctx: CGContext) {
        typealias A = DrinkArt
        A.shadow(ctx, center: CGPoint(x: 112, y: 14), rx: 90, ry: 14, alpha: 0.32)
        let sc = CGPoint(x: 110, y: 24)
        ctx.setFillColor(A.rgb(0.7, 0.7, 0.73))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: 110, y: 20), 76, 13.6))
        let top = CGPath(ellipseIn: A.ellipse(sc, 76, 13.5), transform: nil)
        A.fillAcross(ctx, top, from: 34, to: 186, [(0, A.rgb(0.84, 0.84, 0.87)), (0.3, A.rgb(1, 1, 1)), (0.7, A.rgb(0.95, 0.95, 0.97)), (1, A.rgb(0.78, 0.78, 0.82))])
        // Tabak kenarında bordo şerit ve altın çizgiler
        ctx.setStrokeColor(bordo)
        ctx.setLineWidth(4.2)
        ctx.strokeEllipse(in: A.ellipse(sc, 69, 12.1))
        ctx.setStrokeColor(gold)
        ctx.setLineWidth(0.8)
        ctx.strokeEllipse(in: A.ellipse(sc, 71.6, 12.6))
        ctx.strokeEllipse(in: A.ellipse(sc, 66.4, 11.6))
        ctx.setLineWidth(1.3)
        ctx.strokeEllipse(in: A.ellipse(sc, 75.4, 13.2))
        // Şeritte küçük altın noktalar
        ctx.setFillColor(gold)
        for k in 0..<28 {
            let a = CGFloat(k) / 28 * 2 * .pi
            ctx.fillEllipse(in: A.ellipse(CGPoint(x: sc.x + cos(a) * 69, y: sc.y + sin(a) * 12.1), 0.9, 0.55))
        }
        let well = CGPath(ellipseIn: A.ellipse(CGPoint(x: 110, y: 26.5), 30, 5.2), transform: nil)
        A.fillDown(ctx, well, from: 32, to: 21, [(0, A.rgb(0.8, 0.8, 0.84)), (1, A.rgb(0.98, 0.98, 1))])
        A.shadow(ctx, center: CGPoint(x: 116, y: 26), rx: 36, ry: 6, alpha: 0.26)

        handle(ctx)
        // Porselen gövde: parlak sır, soldan gelen ışık
        let body = bodyPath()
        A.fillAcross(ctx, body, from: mid - 39, to: mid + 39, [(0, A.rgb(0.72, 0.72, 0.75)), (0.18, A.rgb(0.93, 0.93, 0.95)),
                                                             (0.32, A.rgb(1, 1, 1)), (0.6, A.rgb(0.95, 0.95, 0.96)),
                                                             (0.86, A.rgb(0.8, 0.8, 0.83)), (1, A.rgb(0.66, 0.66, 0.7))])
        // Lale motifli bordo şerit
        let stripe = band(64, 90)
        A.fillAcross(ctx, stripe, from: mid - 38, to: mid + 38, [(0, A.rgb(0.28, 0.02, 0.05)), (0.3, A.rgb(0.66, 0.09, 0.13)),
                                                               (0.55, A.rgb(0.56, 0.06, 0.1)), (1, A.rgb(0.25, 0.02, 0.04))])
        for y: CGFloat in [64, 90, 95.5] { goldRing(ctx, y, width: y == 95.5 ? 0.7 : 1.1) }
        goldRing(ctx, 40, width: 0.8)
        motifs(ctx, y: 77)
        // Sır parlaklığı
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: -0.62, u1: -0.47, from: 36, to: 100, alpha: 0.75)
        A.highlightStrip(ctx, mid: mid, half: outer.half, u0: 0.68, u1: 0.74, from: 44, to: 98, alpha: 0.25)
        // İç çeper: arkası aydınlık, öne doğru gölgeli
        let opening = CGPath(ellipseIn: A.ellipse(CGPoint(x: mid, y: rim), outer.half(rim) - lip, (outer.half(rim) - lip) * tilt), transform: nil)
        A.fillDown(ctx, opening, from: rim + 13, to: rim - 13, [(0, A.rgb(0.97, 0.96, 0.95)), (0.6, A.rgb(0.86, 0.85, 0.84)), (1, A.rgb(0.7, 0.69, 0.68))])
    }

    private static func goldRing(_ ctx: CGContext, _ y: CGFloat, width: CGFloat) {
        let f = ring(y), h = outer.half(y)
        var pts: [CGPoint] = []
        var x = mid - h
        while x <= mid + h { pts.append(CGPoint(x: x, y: f(x))); x += 1.5 }
        ctx.addLines(between: pts)
        ctx.setStrokeColor(gold)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    /// Silindir üzerine sarılmış altın laleler: kenara yaklaştıkça daralır.
    private static func motifs(_ ctx: CGContext, y: CGFloat) {
        let count = 9
        let h = outer.half(y), ry = h * tilt
        for k in 0..<(count * 2) {
            let theta = CGFloat(k) / CGFloat(count * 2) * 2 * .pi + 0.17
            let depth = cos(theta)   // 1 tam önde, 0 kenarda; arka yüz görünmez
            guard depth > 0.08 else { continue }
            ctx.saveGState()
            ctx.translateBy(x: mid + h * sin(theta), y: y - ry * depth)
            ctx.scaleBy(x: depth * 0.95, y: 1)
            if k % 2 == 0 { tulip(ctx) } else {
                ctx.setFillColor(gold)
                for d: CGFloat in [-5, 0, 5] { ctx.fillEllipse(in: DrinkArt.ellipse(CGPoint(x: 0, y: d), 1.2, 1.2)) }
            }
            ctx.restoreGState()
        }
    }

    private static func tulip(_ ctx: CGContext) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -1))
        p.addQuadCurve(to: CGPoint(x: -4.6, y: 3.6), control: CGPoint(x: -5.4, y: -1))
        p.addQuadCurve(to: CGPoint(x: -2.6, y: 8.6), control: CGPoint(x: -5, y: 7.4))
        p.addQuadCurve(to: CGPoint(x: 0, y: 4.6), control: CGPoint(x: -1.1, y: 6.8))
        p.addQuadCurve(to: CGPoint(x: 2.6, y: 8.6), control: CGPoint(x: 1.1, y: 6.8))
        p.addQuadCurve(to: CGPoint(x: 4.6, y: 3.6), control: CGPoint(x: 5, y: 7.4))
        p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: 5.4, y: -1))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(gold)
        ctx.fillPath()
        // Orta yaprak çizgisi ve sap, iki yaprak
        ctx.setStrokeColor(DrinkArt.rgb(0.5, 0.05, 0.09, 0.8))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0, y: 0.5)); ctx.addLine(to: CGPoint(x: 0, y: 5.5)); ctx.strokePath()
        ctx.setStrokeColor(gold)
        ctx.setLineWidth(0.9)
        ctx.move(to: CGPoint(x: 0, y: -1)); ctx.addLine(to: CGPoint(x: 0, y: -9.5)); ctx.strokePath()
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0, y: -8))
        leaf.addQuadCurve(to: CGPoint(x: -5, y: -3.5), control: CGPoint(x: -4.8, y: -7.5))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -6), control: CGPoint(x: -1.5, y: -4.5))
        leaf.move(to: CGPoint(x: 0, y: -7))
        leaf.addQuadCurve(to: CGPoint(x: 4.6, y: -2.8), control: CGPoint(x: 4.6, y: -6.6))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -5), control: CGPoint(x: 1.4, y: -3.6))
        ctx.addPath(leaf)
        ctx.setFillColor(gold)
        ctx.fillPath()
    }

    private static func handle(_ ctx: CGContext) {
        typealias A = DrinkArt
        let p = CGMutablePath()
        p.move(to: CGPoint(x: mid + 34, y: 91))
        p.addCurve(to: CGPoint(x: mid + 53, y: 80), control1: CGPoint(x: mid + 46, y: 96), control2: CGPoint(x: mid + 54, y: 90))
        p.addCurve(to: CGPoint(x: mid + 33, y: 52), control1: CGPoint(x: mid + 52, y: 66), control2: CGPoint(x: mid + 44, y: 54))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(A.rgb(0.62, 0.62, 0.66))
        ctx.setLineWidth(7.2)
        ctx.strokePath()
        ctx.addPath(p)
        ctx.setStrokeColor(A.rgb(0.95, 0.95, 0.96))
        ctx.setLineWidth(5.4)
        ctx.strokePath()
        ctx.translateBy(x: -1, y: 0.8)
        ctx.addPath(p)
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.9))
        ctx.setLineWidth(1.6)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 1.6, y: 0)
        ctx.addPath(p)
        ctx.setStrokeColor(gold)
        ctx.setLineWidth(0.7)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func front(_ ctx: CGContext) {
        typealias A = DrinkArt
        let h = outer.half(rim), ry = h * tilt
        // Porselen ağız kalınlığı ve altın yaldız
        ctx.setStrokeColor(A.rgb(1, 1, 1, 0.95))
        ctx.setLineWidth(lip)
        ctx.strokeEllipse(in: A.ellipse(CGPoint(x: mid, y: rim), h - lip / 2, ry - lip / 2 * tilt))
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), h, ry, upper: false))
        ctx.setStrokeColor(gold)
        ctx.setLineWidth(1.7)
        ctx.strokePath()
        ctx.addPath(A.halfEllipse(CGPoint(x: mid, y: rim), h, ry, upper: true))
        ctx.setLineWidth(0.8)
        ctx.strokePath()
        ctx.setFillColor(A.rgb(1, 1, 1, 0.85))
        ctx.fillEllipse(in: A.ellipse(CGPoint(x: mid - 24, y: rim - 9.6), 4.5, 0.8))
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
        // Telve: sıvının çekildiği çeperde kalan kahverengi iz ve süzülen damlalar
        if level < 0.995 {
            let a = min(1, (1 - level) * 4)
            let stain = CGPath(ellipseIn: A.ellipse(CGPoint(x: mid, y: rim - 1), inner, inner * tilt), transform: nil)
            A.fillDown(ctx, stain, from: rim + inner * tilt, to: rim - d - inner * tilt,
                       [(0, A.rgb(0.42, 0.26, 0.14, 0.05 * a)), (0.45, A.rgb(0.36, 0.21, 0.11, 0.34 * a)), (1, A.rgb(0.3, 0.17, 0.08, 0.55 * a))])
            // Çeperden süzülen, ucu kalınlaşan düzensiz telve damlaları
            var r = SeededRandom(41)
            for _ in 0..<9 {
                let u = r.cg(-0.8, 0.8)
                let y0 = rim + inner * tilt * sqrt(1 - u * u) * r.cg(0.2, 0.7)
                let len = (r.cg(2, 6) + d * r.cg(0.25, 0.7))
                let x0 = mid + u * inner * 0.96
                let w = r.cg(0.7, 1.5)
                let drip = CGMutablePath()
                drip.move(to: CGPoint(x: x0 - w * 0.4, y: y0))
                drip.addCurve(to: CGPoint(x: x0 - w, y: y0 - len), control1: CGPoint(x: x0 - w * 0.3, y: y0 - len * 0.4),
                              control2: CGPoint(x: x0 - w * 1.2, y: y0 - len * 0.7))
                drip.addQuadCurve(to: CGPoint(x: x0 + w, y: y0 - len), control: CGPoint(x: x0, y: y0 - len - w * 1.6))
                drip.addCurve(to: CGPoint(x: x0 + w * 0.4, y: y0), control1: CGPoint(x: x0 + w * 1.2, y: y0 - len * 0.7),
                              control2: CGPoint(x: x0 + w * 0.3, y: y0 - len * 0.4))
                drip.closeSubpath()
                ctx.addPath(drip)
                ctx.setFillColor(A.rgb(0.32, 0.19, 0.09, r.cg(0.16, 0.32) * a))
                ctx.fillPath()
            }
            // Telvenin bıraktığı benekli doku
            for _ in 0..<40 {
                let u = r.cg(-0.9, 0.9), v = r.cg(0.1, 1)
                let y = rim + inner * tilt * sqrt(1 - u * u) * v - d * r.cg(0, 0.8)
                let sz = r.cg(0.4, 1.3)
                ctx.setFillColor(A.rgb(0.28, 0.16, 0.07, r.cg(0.1, 0.3) * a))
                ctx.fillEllipse(in: A.ellipse(CGPoint(x: mid + u * inner, y: y), sz, sz * 0.7))
            }
        }
        if level > 0.002 {
            let rx = inner - d * 0.2, ry = rx * tilt, cy = rim - d
            var front: [CGPoint] = [], back: [CGPoint] = []
            let n = 30
            for i in 0...n {
                let u = Double(i) / Double(n) * 2 - 1
                let hgt = CGFloat(s.slosh.height(at: u, halfWidth: Double(rx))) * 0.55
                let e = ry * CGFloat(sqrt(max(0, 1 - u * u)))
                front.append(CGPoint(x: mid + CGFloat(u) * rx, y: cy + hgt - e))
                back.append(CGPoint(x: mid + CGFloat(u) * rx, y: cy + hgt + e))
            }
            let top = CGMutablePath()
            top.addLines(between: front)
            for pt in back.reversed() { top.addLine(to: pt) }
            top.closeSubpath()
            // Koyu kahve, kenarda ışık halkası
            A.fillAcross(ctx, top, from: mid - rx, to: mid + rx, [(0, A.rgb(0.12, 0.06, 0.03)), (0.35, A.rgb(0.26, 0.14, 0.07)), (1, A.rgb(0.1, 0.05, 0.02))])
            let foam = s.phase == .focus ? 1 - 0.62 * s.progress : 1
            foamLayer(ctx, top, cx: mid, cy: cy, rx: rx, ry: ry, amount: foam, s: s)
            // Duvara yapışan köpük halkası
            ctx.addPath(top)
            ctx.setStrokeColor(A.rgb(0.6, 0.42, 0.26, 0.55))
            ctx.setLineWidth(1.4)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Kalın, hafifçe nefes alan köpük: karamel tonları, açık lekeler ve minik kabarcıklar.
    private static func foamLayer(_ ctx: CGContext, _ top: CGPath, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, amount: Double, s: DrinkState) {
        typealias A = DrinkArt
        let a = CGFloat(max(0, min(1, amount)))
        ctx.saveGState()
        ctx.addPath(top)
        ctx.clip()
        ctx.saveGState()
        ctx.translateBy(x: cx - rx * 0.15, y: cy + ry * 0.2)
        ctx.scaleBy(x: 1, y: ry / rx)
        let breath = 1 + 0.035 * CGFloat(sin(s.time * 1.25))
        ctx.drawRadialGradient(A.gradient([(0, A.rgb(0.84, 0.66, 0.45, a)), (0.55, A.rgb(0.68, 0.48, 0.29, a)), (0.85, A.rgb(0.52, 0.33, 0.18, a * 0.9)), (1, A.rgb(0.38, 0.22, 0.11, a * 0.4))]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx * 1.15 * breath, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        var r = SeededRandom(17)
        for i in 0..<34 {
            let ang = r.range(0, 6.283), rad = sqrt(r.next()) * 0.92
            let wob = 1 + 0.12 * sin(s.time * (0.8 + Double(i % 5) * 0.17) + Double(i))
            let x = cx + CGFloat(cos(ang) * rad) * rx + CGFloat(sin(s.time * 0.4 + Double(i)) * 0.6)
            let y = cy + CGFloat(sin(ang) * rad) * ry
            let size = r.cg(1.4, 4.2) * CGFloat(wob)
            let light = i % 3 != 0
            // Köpük incelirken lekeler yırtılıp koyu kahveyi gösterir
            let hole = Double(i) / 34 > amount
            ctx.setFillColor(hole ? A.rgb(0.16, 0.08, 0.04, 0.55) : light ? A.rgb(0.9, 0.75, 0.55, 0.3 * a) : A.rgb(0.42, 0.25, 0.12, 0.22 * a))
            ctx.fillEllipse(in: A.ellipse(CGPoint(x: x, y: y), size * (hole ? 0.9 : 1), size * 0.42 * (hole ? 0.9 : 1)))
        }
        ctx.setStrokeColor(A.rgb(0.35, 0.2, 0.09, 0.35 * a))
        ctx.setLineWidth(0.35)
        for _ in 0..<46 {
            let ang = r.range(0, 6.283), rad = 0.55 + 0.42 * r.next()
            let x = cx + CGFloat(cos(ang) * rad) * rx, y = cy + CGFloat(sin(ang) * rad) * ry
            ctx.strokeEllipse(in: A.ellipse(CGPoint(x: x, y: y), r.cg(0.5, 1.2), r.cg(0.3, 0.6)))
        }
        ctx.restoreGState()
    }
}

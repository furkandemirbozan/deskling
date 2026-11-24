import AppKit

/// Menü çubuğu için içeceklerin sade siluetleri. Şablon görüntüdür; açık ve koyu menü çubuğuna kendiliğinden uyar.
enum DrinkIcons {
    private static var cache: [String: NSImage] = [:]

    /// `fill` 0…1 arası: odakta sıvının ne kadarının kaldığını simgede de gösterir.
    static func menuIcon(_ kind: DrinkKind, fill: Double = 1) -> NSImage {
        let step = Int((min(1, max(0, fill)) * 8).rounded())
        let key = "\(kind.rawValue)-\(step)"
        if let i = cache[key] { return i }
        let f = CGFloat(step) / 8
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.3)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            draw(kind, fill: f, ctx)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = kind.title
        cache[key] = img
        return img
    }

    private static func draw(_ kind: DrinkKind, fill: CGFloat, _ ctx: CGContext) {
        switch kind {
        case .tea:
            // İnce belli bardak ve tabak
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 5.6, y: 16))
            p.addCurve(to: CGPoint(x: 7.2, y: 9.4), control1: CGPoint(x: 5.7, y: 13), control2: CGPoint(x: 7.3, y: 11.4))
            p.addCurve(to: CGPoint(x: 6.6, y: 4), control1: CGPoint(x: 7.1, y: 7.4), control2: CGPoint(x: 6.1, y: 5.6))
            p.addLine(to: CGPoint(x: 11.4, y: 4))
            p.addCurve(to: CGPoint(x: 10.8, y: 9.4), control1: CGPoint(x: 11.9, y: 5.6), control2: CGPoint(x: 10.9, y: 7.4))
            p.addCurve(to: CGPoint(x: 12.4, y: 16), control1: CGPoint(x: 10.7, y: 11.4), control2: CGPoint(x: 12.3, y: 13))
            liquid(ctx, p, bottom: 4, top: 15, fill: fill)
            ctx.addPath(p); ctx.strokePath()
            ctx.move(to: CGPoint(x: 2.5, y: 2.4)); ctx.addLine(to: CGPoint(x: 15.5, y: 2.4)); ctx.strokePath()
        case .turkishCoffee:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 3, y: 12.5))
            p.addCurve(to: CGPoint(x: 6, y: 4.2), control1: CGPoint(x: 3.2, y: 8.5), control2: CGPoint(x: 4.3, y: 5.2))
            p.addLine(to: CGPoint(x: 11, y: 4.2))
            p.addCurve(to: CGPoint(x: 14, y: 12.5), control1: CGPoint(x: 12.7, y: 5.2), control2: CGPoint(x: 13.8, y: 8.5))
            liquid(ctx, p, bottom: 4.2, top: 11.8, fill: fill)
            ctx.addPath(p); ctx.strokePath()
            ctx.addArc(center: CGPoint(x: 14.2, y: 9.4), radius: 2.1, startAngle: .pi * 0.55, endAngle: -.pi * 0.6, clockwise: true)
            ctx.strokePath()
            ctx.move(to: CGPoint(x: 1.5, y: 2.4)); ctx.addLine(to: CGPoint(x: 15.5, y: 2.4)); ctx.strokePath()
            steam(ctx, x: 8.5)
        case .mug:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 3.2, y: 13.5))
            p.addLine(to: CGPoint(x: 3.6, y: 3.4))
            p.addQuadCurve(to: CGPoint(x: 4.6, y: 2.4), control: CGPoint(x: 3.6, y: 2.4))
            p.addLine(to: CGPoint(x: 10.8, y: 2.4))
            p.addQuadCurve(to: CGPoint(x: 11.8, y: 3.4), control: CGPoint(x: 11.8, y: 2.4))
            p.addLine(to: CGPoint(x: 12.2, y: 13.5))
            liquid(ctx, p, bottom: 2.4, top: 12.5, fill: fill)
            ctx.addPath(p); ctx.strokePath()
            ctx.addArc(center: CGPoint(x: 13, y: 8.6), radius: 2.8, startAngle: .pi * 0.62, endAngle: -.pi * 0.62, clockwise: true)
            ctx.strokePath()
            steam(ctx, x: 7.7)
        case .beer:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 4, y: 15.6))
            p.addLine(to: CGPoint(x: 5.3, y: 2.2))
            p.addLine(to: CGPoint(x: 12.7, y: 2.2))
            p.addLine(to: CGPoint(x: 14, y: 15.6))
            liquid(ctx, p, bottom: 2.2, top: 12.2, fill: fill)
            ctx.addPath(p); ctx.strokePath()
            // Köpük
            let top = 2.2 + (12.2 - 2.2) * fill
            if fill > 0.05 {
                for (i, x) in [5.6, 8, 10.4, 12.6].enumerated() {
                    ctx.fillEllipse(in: CGRect(x: x - 1.6, y: top - 0.4 + (i % 2 == 0 ? 0.5 : 0), width: 3.2, height: 3))
                }
            }
        }
    }

    /// Bardağın içini seviyeye kadar doldurur.
    private static func liquid(_ ctx: CGContext, _ outline: CGPath, bottom: CGFloat, top: CGFloat, fill: CGFloat) {
        guard fill > 0.01 else { return }
        ctx.saveGState()
        let closed = CGMutablePath()
        closed.addPath(outline)
        closed.closeSubpath()
        ctx.addPath(closed)
        ctx.clip()
        ctx.fill(CGRect(x: 0, y: 0, width: 18, height: bottom + (top - bottom) * fill))
        ctx.restoreGState()
    }

    private static func steam(_ ctx: CGContext, x: CGFloat) {
        ctx.saveGState()
        ctx.setLineWidth(1)
        for dx: CGFloat in [-2.2, 1.4] {
            ctx.move(to: CGPoint(x: x + dx, y: 14.2))
            ctx.addCurve(to: CGPoint(x: x + dx + 0.4, y: 17.6), control1: CGPoint(x: x + dx + 1.4, y: 15.2), control2: CGPoint(x: x + dx - 1, y: 16.6))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

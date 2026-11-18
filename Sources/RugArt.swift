import AppKit

/// Türk kilim motifleriyle kodla dokunan halı. Düğüm düğüm çizildiği için yakından bakınca dokuma görünür.
enum RugArt {
    static let size = CGSize(width: 480, height: 330)
    private static let knotsPerPoint: CGFloat = 1.5
    private static let upscale = 2
    static let scale: CGFloat = knotsPerPoint * CGFloat(upscale)

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static let navy = rgb(0x13264A), ink = rgb(0x0B1630), red = rgb(0xA8201C), wine = rgb(0x761411)
    private static let gold = rgb(0xDDAE55), cream = rgb(0xEBDDB5), rust = rgb(0xC9642C), slate = rgb(0x7393A6)

    static let front: CGImage = weave(back: false)
    static let back: CGImage = weave(back: true)

    // MARK: - Dokuma

    private static func weave(back: Bool) -> CGImage {
        let w = Int(size.width * knotsPerPoint), h = Int(size.height * knotsPerPoint)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(false)
        ctx.scaleBy(x: knotsPerPoint, y: knotsPerPoint)
        paint(ctx)

        // Her düğüme küçük bir renk farkı vererek el dokuması hissi kat.
        var seed: UInt32 = 1923
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            let row: CGFloat = y % 2 == 0 ? 1.03 : 0.95
            for x in 0..<w {
                seed = seed &* 1664525 &+ 1013904223
                let jitter = 0.88 + CGFloat(seed >> 24) / 255 * 0.22
                let i = (y * w + x) * 4
                var r = CGFloat(px[i]), g = CGFloat(px[i + 1]), b = CGFloat(px[i + 2])
                if back {   // arka yüz: soluk ve mat
                    let l = 0.3 * r + 0.59 * g + 0.11 * b
                    r = (r * 0.42 + l * 0.58) * 0.62
                    g = (g * 0.42 + l * 0.58) * 0.56
                    b = (b * 0.42 + l * 0.58) * 0.50
                }
                let a = CGFloat(px[i + 3])
                px[i] = UInt8(min(a, r * jitter * row))
                px[i + 1] = UInt8(min(a, g * jitter * row))
                px[i + 2] = UInt8(min(a, b * jitter * row))
            }
        }
        let knots = ctx.makeImage()!
        let big = CGContext(data: nil, width: w * upscale, height: h * upscale, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        big.interpolationQuality = .none
        big.draw(knots, in: CGRect(x: 0, y: 0, width: w * upscale, height: h * upscale))
        return big.makeImage()!
    }

    // MARK: - Desen

    private static func paint(_ c: CGContext) {
        let W = size.width, H = size.height
        let fringe: CGFloat = 13
        let body = CGRect(x: fringe, y: 0, width: W - fringe * 2, height: H)

        // Saçaklar
        var s: UInt32 = 77
        var y: CGFloat = 0.5
        while y < H {
            s = s &* 1664525 &+ 1013904223
            let len = fringe - CGFloat(s >> 29)
            c.setFillColor(y.truncatingRemainder(dividingBy: 4) < 2 ? cream : rgb(0xD9CBA2))
            c.fill(CGRect(x: fringe - len, y: y, width: len, height: 1.34))
            c.fill(CGRect(x: W - fringe, y: y, width: len, height: 1.34))
            y += 2
        }

        c.setFillColor(navy); c.fill(body)

        // Dış su: küçük rozetler
        var r = body.insetBy(dx: 4, dy: 4)
        c.setFillColor(ink); c.fill(r)
        rosettes(c, band: r, thickness: 14)
        r = r.insetBy(dx: 14, dy: 14)
        c.setFillColor(cream); c.fill(r)
        r = r.insetBy(dx: 1, dy: 1)

        // Ana bordür: koçboynuzu
        c.setFillColor(red); c.fill(r)
        hornBorder(c, band: r, thickness: 30)
        r = r.insetBy(dx: 30, dy: 30)
        c.setFillColor(cream); c.fill(r)
        r = r.insetBy(dx: 1, dy: 1)

        // İç su: noktalar
        c.setFillColor(wine); c.fill(r)
        dots(c, band: r, thickness: 7)
        r = r.insetBy(dx: 7, dy: 7)
        c.setFillColor(gold); c.fill(r)
        r = r.insetBy(dx: 1, dy: 1)

        // Zemin
        c.setFillColor(ink); c.fill(r)
        c.saveGState()
        c.clip(to: r)
        field(c, r)
        c.restoreGState()
    }

    private static func field(_ c: CGContext, _ r: CGRect) {
        let cols = 5, rows = 5
        let dx = r.width / CGFloat(cols), dy = r.height / CGFloat(rows)

        // Boşluklardaki küçük yıldızlar
        for j in 0...rows * 2 {
            for i in 0...cols * 2 where (i + j) % 2 == 1 {
                let p = CGPoint(x: r.minX + CGFloat(i) * dx / 2, y: r.minY + CGFloat(j) * dy / 2)
                star(c, p, 5.5, (i / 2) % 2 == 0 ? slate : rust)
                star(c, p, 2.4, cream)
            }
        }
        for j in 0..<rows {
            let cy = r.minY + (CGFloat(j) + 0.5) * dy
            if j % 2 == 0 {
                for i in 0..<cols {
                    let cx = r.minX + (CGFloat(i) + 0.5) * dx
                    medallion(c, CGPoint(x: cx, y: cy), 20, golden: (i + j / 2) % 2 == 0)
                }
            } else {
                for i in 0...cols {
                    hookedDiamond(c, CGPoint(x: r.minX + CGFloat(i) * dx, y: cy), 31, 22, tint: i % 2 == 0)
                }
            }
        }
    }

    // MARK: - Motifler

    private static func fill(_ c: CGContext, _ pts: [CGPoint], _ color: CGColor) {
        c.addLines(between: pts); c.closePath()
        c.setFillColor(color); c.fillPath()
    }

    /// Basamaklı sekizgen göbek.
    private static func stepped(_ p: CGPoint, _ r: CGFloat) -> [CGPoint] {
        let q: [(CGFloat, CGFloat)] = [(0.30, 1), (0.30, 0.84), (0.60, 0.84), (0.60, 0.62), (0.84, 0.62), (0.84, 0.30), (1, 0.30)]
        var out = q.map { CGPoint(x: p.x + $0.0 * r, y: p.y + $0.1 * r) }
        out += q.reversed().map { CGPoint(x: p.x + $0.0 * r, y: p.y - $0.1 * r) }
        out += q.map { CGPoint(x: p.x - $0.0 * r, y: p.y - $0.1 * r) }
        out += q.reversed().map { CGPoint(x: p.x - $0.0 * r, y: p.y + $0.1 * r) }
        return out
    }

    /// Selçuklu yıldızı: iç içe iki kare.
    private static func star(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ color: CGColor) {
        let k = r * 0.72
        fill(c, [CGPoint(x: p.x - k, y: p.y - k), CGPoint(x: p.x + k, y: p.y - k),
                 CGPoint(x: p.x + k, y: p.y + k), CGPoint(x: p.x - k, y: p.y + k)], color)
        diamond(c, p, r, r, color)
    }

    private static func diamond(_ c: CGContext, _ p: CGPoint, _ a: CGFloat, _ b: CGFloat, _ color: CGColor) {
        fill(c, [CGPoint(x: p.x, y: p.y + b), CGPoint(x: p.x + a, y: p.y),
                 CGPoint(x: p.x, y: p.y - b), CGPoint(x: p.x - a, y: p.y)], color)
    }

    private static func medallion(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, golden: Bool) {
        fill(c, stepped(p, r + 2), golden ? wine : cream)
        fill(c, stepped(p, r), golden ? gold : red)
        star(c, p, r * 0.68, golden ? red : cream)
        star(c, p, r * 0.46, golden ? cream : navy)
        star(c, p, r * 0.27, golden ? wine : red)
        diamond(c, p, r * 0.11, r * 0.11, gold)
        for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
            let q = CGPoint(x: p.x + CGFloat(sx) * r * 0.70, y: p.y + CGFloat(sy) * r * 0.70)
            diamond(c, q, 1.7, 1.7, golden ? navy : gold)
        }
    }

    private static func hookedDiamond(_ c: CGContext, _ p: CGPoint, _ a: CGFloat, _ b: CGFloat, tint: Bool) {
        let line = tint ? rust : red
        diamond(c, p, a, b, line)
        diamond(c, p, a - 3.5, b - 3, ink)
        diamond(c, p, a - 7, b - 6, line)
        diamond(c, p, a - 10, b - 8.5, tint ? navy : wine)

        // Köşelerdeki kancalar
        c.setFillColor(line)
        for s in [CGFloat(1), -1] {
            c.fill(CGRect(x: p.x - 1.2, y: p.y + s * b - 1, width: 2.4, height: s * 6))
            c.fill(CGRect(x: p.x - 7, y: p.y + s * (b + 5) - 1.2, width: 14, height: 2.4))
            c.fill(CGRect(x: p.x + s * a - 1, y: p.y - 1.2, width: s * 5, height: 2.4))
            c.fill(CGRect(x: p.x + s * (a + 4) - 1.2, y: p.y - 6, width: 2.4, height: 12))
        }
        star(c, p, 8, tint ? slate : gold)
        star(c, p, 4.6, tint ? cream : wine)
        diamond(c, p, 1.8, 1.8, red)
    }

    /// Koçboynuzu: bereket ve güç simgesi.
    private static func horn(_ c: CGContext, _ p: CGPoint, vertical: Bool, flip: CGFloat) {
        let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-1.3, -9, 2.6, 13), (-9.5, 2, 19, 2.6), (-9.5, 2, 2.6, 7.5), (6.9, 2, 2.6, 7.5),
            (-6, 7, 3.5, 2.6), (2.5, 7, 3.5, 2.6),
        ]
        c.setFillColor(gold)
        for s in segs {
            var rect = CGRect(x: s.0, y: s.1 * flip, width: s.2, height: s.3 * flip)
            if vertical { rect = CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width) }
            c.fill(rect.offsetBy(dx: p.x, dy: p.y))
        }
    }

    private static func around(_ band: CGRect, _ inset: CGFloat, spacing: CGFloat,
                               _ draw: (CGPoint, Bool, CGFloat, Int) -> Void) {
        let r = band.insetBy(dx: inset, dy: inset)
        let nx = max(1, Int((r.width / spacing).rounded())), ny = max(1, Int((r.height / spacing).rounded()))
        for i in 0...nx {
            let x = r.minX + CGFloat(i) * r.width / CGFloat(nx)
            draw(CGPoint(x: x, y: r.minY), false, 1, i)
            draw(CGPoint(x: x, y: r.maxY), false, -1, i)
        }
        for j in 1..<ny {
            let y = r.minY + CGFloat(j) * r.height / CGFloat(ny)
            draw(CGPoint(x: r.minX, y: y), true, 1, j)
            draw(CGPoint(x: r.maxX, y: y), true, -1, j)
        }
    }

    private static func hornBorder(_ c: CGContext, band: CGRect, thickness t: CGFloat) {
        around(band, t / 2, spacing: 36) { p, vertical, flip, i in
            if i % 2 == 0 {
                horn(c, p, vertical: vertical, flip: flip)
            } else {
                diamond(c, p, 8, 8, wine)
                star(c, p, 5, gold)
                diamond(c, p, 2, 2, navy)
            }
        }
    }

    private static func rosettes(_ c: CGContext, band: CGRect, thickness t: CGFloat) {
        let palette = [gold, slate, red, cream]
        around(band, t / 2, spacing: 21) { p, _, _, i in
            star(c, p, 5, palette[i % palette.count])
            star(c, p, 2.3, i % 2 == 0 ? ink : wine)
        }
    }

    private static func dots(_ c: CGContext, band: CGRect, thickness t: CGFloat) {
        around(band, t / 2, spacing: 9) { p, _, _, i in
            diamond(c, p, 2, 2, i % 2 == 0 ? gold : cream)
        }
    }
}

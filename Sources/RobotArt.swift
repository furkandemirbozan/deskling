import AppKit

/// Robotun tüm parçaları kodla çizilir (üstten görünüm, ön taraf +x yönünde).
enum RobotArt {
    static let size: CGFloat = 112          // katman kenarı (pt)
    static let radius: CGFloat = 44         // gövde yarıçapı (pt)
    static let scale: CGFloat = 3

    static func render(_ side: CGFloat = size, _ draw: (CGContext) -> Void) -> CGImage {
        let px = Int(side * scale)
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: side / 2, y: side / 2)
        draw(ctx)
        return ctx.makeImage()!
    }

    private static func c(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: w, green: w, blue: w * 1.04, alpha: a) }

    private static func circle(_ x: CGContext, _ r: CGFloat, at p: CGPoint = .zero) -> CGRect {
        CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }

    private static func radial(_ x: CGContext, r: CGFloat, center: CGPoint = .zero, stops: [(CGFloat, CGColor)]) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
                           locations: stops.map(\.0))!
        x.saveGState()
        x.addEllipse(in: circle(x, r, at: center))
        x.clip()
        x.drawRadialGradient(g, startCenter: CGPoint(x: center.x - r * 0.3, y: center.y + r * 0.35), startRadius: 0,
                             endCenter: center, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
        x.restoreGState()
    }

    static let shadow: CGImage = render(size + 28) { x in
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [c(0, 0.5), c(0, 0.32), c(0, 0)] as CFArray, locations: [0, 0.72, 1])!
        x.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius + 18, options: [])
    }

    static let body: CGImage = render { x in
        let R = radius
        radial(x, r: R, stops: [(0, c(0.20)), (0.7, c(0.095)), (1, c(0.035))])

        // Ön tampon
        x.setLineCap(.round)
        x.setStrokeColor(c(0.02))
        x.setLineWidth(5)
        x.addArc(center: .zero, radius: R - 2.6, startAngle: -1.2, endAngle: 1.2, clockwise: false)
        x.strokePath()
        x.setStrokeColor(c(0.34, 0.9))
        x.setLineWidth(0.8)
        x.addArc(center: .zero, radius: R - 0.6, startAngle: -1.15, endAngle: 1.15, clockwise: false)
        x.strokePath()

        // Üst plaka
        let plate = R * 0.86
        radial(x, r: plate, stops: [(0, c(0.17)), (1, c(0.075))])
        x.saveGState()
        x.addEllipse(in: circle(x, plate))
        x.clip()
        x.setFillColor(c(1, 0.055))
        let step: CGFloat = 5.2
        var row = 0
        var yy = -plate
        while yy < plate {
            var xx = -plate + (row % 2 == 0 ? 0 : step / 2)
            while xx < plate {
                x.addLines(between: [CGPoint(x: xx, y: yy + 1.3), CGPoint(x: xx + 1.3, y: yy),
                                     CGPoint(x: xx, y: yy - 1.3), CGPoint(x: xx - 1.3, y: yy)])
                x.closePath()
                xx += step
            }
            yy += step * 0.72
            row += 1
        }
        x.fillPath()
        x.restoreGState()
        x.setStrokeColor(c(0.32, 0.55))
        x.setLineWidth(0.6)
        x.strokeEllipse(in: circle(x, plate))

        // Arka havalandırma ızgarası
        x.setFillColor(c(0.34))
        for ring in 0..<3 {
            let r = R - 3 - CGFloat(ring) * 2.2
            for i in -6...6 {
                let a = CGFloat.pi + CGFloat(i) * 0.075
                x.fillEllipse(in: circle(x, 0.55, at: CGPoint(x: cos(a) * r, y: sin(a) * r)))
            }
        }

        // Kontrol düğmesi (fotoğraftaki kapsül)
        let pill = CGRect(x: -R * 0.62, y: -6.5, width: 7.5, height: 13)
        x.addPath(CGPath(roundedRect: pill, cornerWidth: 3.7, cornerHeight: 3.7, transform: nil))
        x.setFillColor(c(0.02))
        x.fillPath()
        x.setFillColor(c(0.62))
        x.fillEllipse(in: circle(x, 1.1, at: CGPoint(x: pill.midX, y: pill.midY + 3)))
        x.fillEllipse(in: circle(x, 1.1, at: CGPoint(x: pill.midX, y: pill.midY - 3)))

        // Lidar yuvası
        radial(x, r: R * 0.40, stops: [(0, c(0.02)), (1, c(0.07))])
        x.setStrokeColor(c(0.28, 0.7))
        x.setLineWidth(0.6)
        x.strokeEllipse(in: circle(x, R * 0.40))
    }

    static let lidar: CGImage = render { x in
        let r = radius * 0.31
        radial(x, r: r, stops: [(0, c(0.24)), (0.55, c(0.10)), (1, c(0.03))])
        x.setStrokeColor(c(0.42, 0.8))
        x.setLineWidth(0.7)
        x.strokeEllipse(in: circle(x, r - 0.4))
        // Dönüşü belli eden tarayıcı penceresi
        x.setLineCap(.round)
        x.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.86, blue: 1, alpha: 0.95))
        x.setLineWidth(2)
        x.addArc(center: .zero, radius: r - 2.6, startAngle: -0.42, endAngle: 0.42, clockwise: false)
        x.strokePath()
        x.setStrokeColor(c(0.7))
        x.setLineWidth(1)
        x.move(to: CGPoint(x: -3, y: 2.5)); x.addLine(to: CGPoint(x: 2, y: 2.5))
        x.move(to: CGPoint(x: -3, y: 2.5)); x.addLine(to: CGPoint(x: -3, y: -3))
        x.strokePath()
    }

    static let brush: CGImage = render(64) { x in
        for i in 0..<3 {
            x.saveGState()
            x.rotate(by: CGFloat(i) * 2 * .pi / 3)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 2, y: 2))
            p.addQuadCurve(to: CGPoint(x: 30, y: 7), control: CGPoint(x: 16, y: 6))
            p.addLine(to: CGPoint(x: 30.5, y: 3.5))
            p.addQuadCurve(to: CGPoint(x: 2, y: -2), control: CGPoint(x: 16, y: 1))
            p.closeSubpath()
            x.addPath(p)
            x.setFillColor(c(0.33))
            x.fillPath()
            x.restoreGState()
        }
        x.setFillColor(c(0.08))
        x.fillEllipse(in: circle(x, 4.5))
    }

    /// Şarj istasyonu: robotun arkasında (solda) durur.
    static let station: CGImage = render(120) { x in
        let rect = CGRect(x: -26, y: -46, width: 40, height: 92)
        x.saveGState()
        x.setShadow(offset: CGSize(width: 0, height: -3), blur: 9, color: c(0, 0.45))
        x.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        x.setFillColor(c(0.075))
        x.fillPath()
        x.restoreGState()
        x.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 9, cornerHeight: 9, transform: nil))
        x.setFillColor(c(0.13))
        x.fillPath()
        x.setFillColor(CGColor(srgbRed: 0.78, green: 0.66, blue: 0.34, alpha: 1))
        x.fill(CGRect(x: 8, y: 13, width: 6, height: 6))
        x.fill(CGRect(x: 8, y: -19, width: 6, height: 6))
    }

    static func demoCard(_ index: Int) -> CGImage {
        let hues: [(CGFloat, CGFloat, CGFloat)] = [(0.27, 0.46, 0.86), (0.18, 0.62, 0.55), (0.78, 0.42, 0.28), (0.52, 0.36, 0.78)]
        let h = hues[index % hues.count]
        return render(84) { x in
            let r = CGRect(x: -36, y: -25, width: 72, height: 50)
            x.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
            x.setFillColor(CGColor(srgbRed: h.0, green: h.1, blue: h.2, alpha: 1))
            x.fillPath()
            x.setFillColor(c(1, 0.95))
            x.fill(CGRect(x: -29, y: -17, width: 58, height: 30))
            x.setFillColor(c(0.72))
            x.fill(CGRect(x: -24, y: 3, width: 34, height: 4))
            x.fill(CGRect(x: -24, y: -5, width: 46, height: 3))
            x.fill(CGRect(x: -24, y: -11, width: 25, height: 3))
        }
    }

    static func appIcon(_ px: CGFloat) -> NSImage {
        let img = render(128) { x in
            let bg = CGRect(x: -56, y: -56, width: 112, height: 112)
            x.addPath(CGPath(roundedRect: bg, cornerWidth: 25, cornerHeight: 25, transform: nil))
            x.clip()
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(srgbRed: 0.86, green: 0.91, blue: 0.93, alpha: 1),
                                        CGColor(srgbRed: 0.56, green: 0.67, blue: 0.72, alpha: 1)] as CFArray,
                               locations: [0, 1])!
            x.drawLinearGradient(g, start: CGPoint(x: 0, y: 56), end: CGPoint(x: 0, y: -56), options: [])
            x.rotate(by: 0.6)
            for (image, side) in [(shadow, size + 28), (body, size), (lidar, size)] {
                x.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            }
        }
        return NSImage(cgImage: img, size: NSSize(width: px, height: px))
    }
}

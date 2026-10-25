import AppKit

/// Tüm görsel kimlik burada çizilir: menü çubuğu simgesi + uygulama ikonu.
/// Harici görsel dosyası yok — her şey NSBezierPath ile vektörel üretilir.
enum LogoRenderer {

    // MARK: - Menü çubuğu (template: siyah + alfa, sistem rengi uygular)

    static func statusImage(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            let s = rect.width
            let lw = max(1.4, s * 0.085)
            let inset = s * 0.14
            let frame = rect.insetBy(dx: inset, dy: inset * 1.15)

            // Vizör köşeleri (viewfinder)
            let arm = frame.width * 0.34
            let path = NSBezierPath()
            path.lineWidth = lw
            path.lineCapStyle = .round
            // sol üst
            path.move(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
            path.line(to: NSPoint(x: frame.minX, y: frame.maxY))
            path.line(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
            // sağ üst
            path.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
            path.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
            path.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
            // sağ alt
            path.move(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
            path.line(to: NSPoint(x: frame.maxX, y: frame.minY))
            path.line(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
            // sol alt
            path.move(to: NSPoint(x: frame.minX + arm, y: frame.minY))
            path.line(to: NSPoint(x: frame.minX, y: frame.minY))
            path.line(to: NSPoint(x: frame.minX, y: frame.minY + arm))
            path.stroke()

            // Lens: dolu daire + iç boşluk (alpha ile oyulur)
            let lensR = s * 0.20
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let lens = NSBezierPath(ovalIn: NSRect(x: center.x - lensR, y: center.y - lensR,
                                                   width: lensR * 2, height: lensR * 2))
            lens.fill()

            ctx.setBlendMode(.clear)
            let holeR = lensR * 0.44
            let hole = NSBezierPath(ovalIn: NSRect(x: center.x - holeR, y: center.y - holeR,
                                                   width: holeR * 2, height: holeR * 2))
            hole.fill()
            ctx.setBlendMode(.normal)

            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Uygulama ikonu

    private static let yesilAcik = NSColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1) // #4ade80
    private static let yesilKoyu = NSColor(srgbRed: 0.08, green: 0.50, blue: 0.24, alpha: 1) // #15803d

    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width

            // Squircle zemin + gradyan
            let radius = s * 0.225
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02),
                                  xRadius: radius, yRadius: radius)
            bg.addClip()
            let grad = NSGradient(starting: yesilAcik, ending: yesilKoyu)
            grad?.draw(in: bg, angle: -90)

            // Üst ışık bandı
            let band = NSBezierPath(rect: NSRect(x: 0, y: rect.midY, width: s, height: rect.midY))
            NSColor.white.withAlphaComponent(0.10).setFill()
            band.fill()

            // Beyaz çerçeve + köşe kırıkları
            let inset = s * 0.20
            let lw = max(2, s * 0.045)
            let frame = rect.insetBy(dx: inset, dy: inset)
            let arm = frame.width * 0.30
            let p = NSBezierPath()
            p.lineWidth = lw
            p.lineCapStyle = .round
            NSColor.white.setStroke()
            p.move(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
            p.line(to: NSPoint(x: frame.minX, y: frame.maxY))
            p.line(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
            p.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
            p.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
            p.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
            p.move(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
            p.line(to: NSPoint(x: frame.maxX, y: frame.minY))
            p.line(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
            p.move(to: NSPoint(x: frame.minX + arm, y: frame.minY))
            p.line(to: NSPoint(x: frame.minX, y: frame.minY))
            p.line(to: NSPoint(x: frame.minX, y: frame.minY + arm))
            p.stroke()

            // Lens (beyaz) + iç koyu halka + parlama
            let cx = rect.midX, cy = rect.midY
            let r = s * 0.175
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()

            let r2 = r * 0.62
            yesilKoyu.withAlphaComponent(0.92).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - r2, y: cy - r2, width: r2 * 2, height: r2 * 2)).fill()

            NSColor.white.withAlphaComponent(0.85).setFill()
            let rr = r * 0.20
            NSBezierPath(ovalIn: NSRect(x: cx - r * 0.42 - rr, y: cy + r * 0.30 - rr,
                                        width: rr * 2, height: rr * 2)).fill()

            return true
        }
    }
}

/// `.iconset` üretimi (make_icons.sh bunu `iconutil` ile .icns'e çevirir).
enum IconGen {
    static let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

    static func makeIconSet(into dir: String) {
        let base = URL(fileURLWithPath: dir)
        let set = base.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

        // (piksel boyutu, dosya adı) — iconutil'ün beklediği isimler
        let jobs: [(Int, String)] = [
            (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
        ]
        for (px, name) in jobs {
            let img = LogoRenderer.appIcon(size: CGFloat(px))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: set.appendingPathComponent(name))
        }
        // Menü çubuğu simgesi (bundle Resources'a girer)
        for (px, name) in [(18, "menubar.png"), (36, "menubar@2x.png")] {
            let img = LogoRenderer.statusImage(size: CGFloat(px))
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: base.appendingPathComponent(name))
            }
        }
        print("OK ikon seti: \(set.path)")
    }
}

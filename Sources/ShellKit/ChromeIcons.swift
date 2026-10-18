import AppKit

/// Line-art glyphs for the window chrome, drawn in code: 1.5-unit rounded strokes on a 30-unit canvas, each with a
/// small "sparkle". The canvas is drawn at 22 pt inside a 30 pt button (4 pt inset), so strokes land at ~1.1 pt.
/// Template images (tinted by the button that shows them).
enum ChromeIcon: CaseIterable {
    case settings, search, new, pin, previous, next, front, export, delete

    /// The design canvas, in units.
    static let canvas: CGFloat = 30
    /// The drawn glyph box in points (the button is 30 pt, the glyph inset 4 pt on every side).
    static let size: CGFloat = 22

    var image: NSImage {
        let s = Self.size
        let image = NSImage(size: NSSize(width: s, height: s), flipped: true) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: s / Self.canvas)
            scale.concat()
            NSColor.black.set()
            self.draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func stroke(_ path: NSBezierPath, width: CGFloat = 1.5) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func line(_ points: [(CGFloat, CGFloat)], close: Bool = false) -> NSBezierPath {
        let p = NSBezierPath()
        for (i, pt) in points.enumerated() {
            if i == 0 { p.move(to: NSPoint(x: pt.0, y: pt.1)) } else { p.line(to: NSPoint(x: pt.0, y: pt.1)) }
        }
        if close { p.close() }
        return p
    }

    private func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat = 2) {
        NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
    }

    /// A tiny four-point star.
    private func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat = 1.3) {
        let p = NSBezierPath()
        let k = r * 0.25
        p.move(to: NSPoint(x: x, y: y - r))
        p.curve(to: NSPoint(x: x + r, y: y), controlPoint1: NSPoint(x: x + k, y: y - k), controlPoint2: NSPoint(x: x + k, y: y - k))
        p.curve(to: NSPoint(x: x, y: y + r), controlPoint1: NSPoint(x: x + k, y: y + k), controlPoint2: NSPoint(x: x + k, y: y + k))
        p.curve(to: NSPoint(x: x - r, y: y), controlPoint1: NSPoint(x: x - k, y: y + k), controlPoint2: NSPoint(x: x - k, y: y + k))
        p.curve(to: NSPoint(x: x, y: y - r), controlPoint1: NSPoint(x: x - k, y: y - k), controlPoint2: NSPoint(x: x - k, y: y - k))
        p.fill()
    }

    private func ring(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    /// Strokes `path` in the background first (a knockout gap around a line that crosses another), then for real.
    private func strokeWithGap(_ path: NSBezierPath, width: CGFloat = 1.5, gap: CGFloat = 1) {
        let ctx = NSGraphicsContext.current
        let saved = ctx?.compositingOperation ?? .sourceOver
        ctx?.compositingOperation = .clear
        stroke(path, width: width + gap * 2)
        ctx?.compositingOperation = saved
        stroke(path, width: width)
    }

    private func draw() {
        switch self {
        case .settings:
            // Three sliders; each line breaks at its knob, a ring with a pinhole.
            for (y, knob) in [(CGFloat(9.25), CGFloat(15.25)), (15.25, 20), (20.75, 12)] {
                stroke(line([(6.75, y), (knob - 2.5, y)]))
                stroke(line([(knob + 2.5, y), (23.25, y)]))
                stroke(ring(knob, y, 1.75), width: 1.9)
            }
            dot(7, 12)
        case .search:
            // A magnifier whose lens is a ringed planet: the ring's back half hides behind the lens, its front
            // half crosses it with a small gap.
            let c = NSPoint(x: 14.75, y: 13.5)
            stroke(ring(c.x, c.y, 6.8))
            let ellipse = NSRect(x: c.x - 8.9, y: 14.5 - 1.6, width: 17.8, height: 3.2)
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 30, height: 30))
            outside.append(ring(c.x, c.y, 6.8).reversed)
            outside.addClip()
            stroke(NSBezierPath(ovalIn: ellipse))
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 14.5, width: 30, height: 15.5)).addClip()
            strokeWithGap(NSBezierPath(ovalIn: ellipse), gap: 0.6)
            NSGraphicsContext.restoreGraphicsState()
            stroke(line([(18.6, 20.6), (20.6, 24)]))
            sparkle(21.9, 19.4, 1.1)
        case .new:
            // A rounded square with a pen stroke from its centre into the top-right corner.
            stroke(NSBezierPath(roundedRect: NSRect(x: 6.75, y: 6.75, width: 16.5, height: 16.5), xRadius: 3.5, yRadius: 3.5))
            stroke(line([(14.9, 15.1), (22, 8)]))
            sparkle(24.4, 5.2, 1.3)
        case .pin:
            // A pushpin seen from the side, standing on a baseline.
            stroke(ring(15.25, 10.75, 4.5))
            stroke(line([(15, 15.5), (15, 22.5)]))
            stroke(line([(6.75, 23.25), (23.25, 23.25)]))
            dot(18.5, 20.5)
        case .previous:
            // ◁ joined to a bar on its right.
            stroke(line([(7.75, 15), (14.75, 11.25), (14.75, 18.75)], close: true))
            stroke(line([(14.75, 15), (19.5, 15)]), width: 1)
            stroke(line([(19.5, 6.75), (19.5, 23)]), width: 1.25)
            dot(16.5, 6.75)
        case .next:
            // A bar joined to ▷ on its right.
            stroke(line([(10.75, 6.75), (10.75, 23.25)]), width: 1.25)
            stroke(line([(10.75, 15), (15.25, 15)]), width: 1)
            stroke(line([(15.25, 11.25), (21.75, 15), (15.25, 18.75)], close: true))
            dot(7.75, 22.75)
        case .front:
            // A line through a short and a tall bar into ▷: jump to the front of the stack.
            stroke(line([(5, 15), (19.75, 15)]), width: 1)
            stroke(line([(11.5, 10.75), (11.5, 19.25)]), width: 1.25)
            stroke(line([(15, 6.75), (15, 23.25)]), width: 1.25)
            stroke(line([(19.75, 11.25), (26.25, 15), (19.75, 18.75)], close: true))
        case .export:
            // △ on a stem rising out of a rounded box; the stem ends in a dot.
            stroke(line([(15, 5.75), (18.75, 11.75), (11.25, 11.75)], close: true))
            stroke(NSBezierPath(roundedRect: NSRect(x: 6.75, y: 13.75, width: 16.5, height: 9), xRadius: 2.5, yRadius: 2.5))
            stroke(line([(15, 12.5), (15, 16.5)]), width: 1.25)
            dot(15, 18.4)
        case .delete:
            // A bin: a double-lined lid with a handle dot, a round-bottomed body and three slots.
            dot(15, 4.75)
            stroke(NSBezierPath(roundedRect: NSRect(x: 5.25, y: 7.25, width: 19.5, height: 2), xRadius: 1, yRadius: 1))
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 6.75, y: 10))
            body.line(to: NSPoint(x: 6.75, y: 21.5))
            body.appendArc(withCenter: NSPoint(x: 10.75, y: 21.5), radius: 4, startAngle: 180, endAngle: 90, clockwise: true)
            body.line(to: NSPoint(x: 19.25, y: 25.5))
            body.appendArc(withCenter: NSPoint(x: 19.25, y: 21.5), radius: 4, startAngle: 90, endAngle: 0, clockwise: true)
            body.line(to: NSPoint(x: 23.25, y: 10))
            stroke(body)
            for x in [11.25, 14.75, 18.75] as [CGFloat] { stroke(line([(x, 15), (x, 19)])) }
        }
    }
}

/// The nine slots are the planets, Mercury to Pluto, each drawn on a 30-unit canvas at its relative size.
enum Planet: Int, CaseIterable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune, pluto

    var name: String {
        switch self {
        case .mercury: "Mercury"
        case .venus: "Venus"
        case .earth: "Earth"
        case .mars: "Mars"
        case .jupiter: "Jupiter"
        case .saturn: "Saturn"
        case .uranus: "Uranus"
        case .neptune: "Neptune"
        case .pluto: "Pluto"
        }
    }

    /// The body on the canvas: centre and diameter in units.
    private var body: (x: CGFloat, y: CGFloat, d: CGFloat) {
        switch self {
        case .mercury: (14.5, 15, 4)
        case .venus: (15, 15, 8.5)
        case .earth: (15.4, 14.75, 10.5)
        case .mars: (15, 15, 8.5)
        case .jupiter: (15, 15, 23.5)
        case .saturn: (15, 14.75, 14.5)
        case .uranus: (15, 14.75, 12)
        case .neptune: (15, 14.75, 12)
        case .pluto: (14.75, 14.75, 3)
        }
    }

    /// Draws the planet's 30-unit canvas into `rect` (y down) in `color`. Details are cut out of the body
    /// (transparent), so whatever is behind shows through. `outlined` hollows the body out to a ring about 1 pt
    /// wide at bar size (the tiny dwarf planets stay solid).
    func draw(in rect: NSRect, color: NSColor, outlined: Bool = false) {
        guard let ctx = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        let xf = NSAffineTransform()
        xf.translateX(by: rect.minX, yBy: rect.minY)
        xf.scale(by: rect.width / 30)
        xf.concat()
        color.setFill()
        color.setStroke()
        let b = body
        let disc = NSBezierPath(ovalIn: NSRect(x: b.x - b.d / 2, y: b.y - b.d / 2, width: b.d, height: b.d))

        func knockout(_ draw: () -> Void) {
            ctx.compositingOperation = .clear
            draw()
            ctx.compositingOperation = .sourceOver
        }
        func fillBody() {
            disc.fill()
            let ring: CGFloat = 1.4
            guard outlined, b.d > 3 * ring else { return }
            knockout { NSBezierPath(ovalIn: NSRect(x: b.x - b.d / 2 + ring, y: b.y - b.d / 2 + ring,
                                                   width: b.d - 2 * ring, height: b.d - 2 * ring)).fill() }
        }
        switch self {
        case .saturn:
            // A tilted ring: its back half hides behind the body, its front half crosses it with a gap.
            var t = AffineTransform(translationByX: 15, byY: 14.6)
            t.rotate(byDegrees: -12.2)
            let ring = NSBezierPath(ovalIn: NSRect(x: -12.9, y: -2.4, width: 25.8, height: 4.8))
            ring.transform(using: t)
            ring.lineWidth = 1.2
            ring.stroke()
            fillBody()
            NSGraphicsContext.saveGraphicsState()
            let front = NSBezierPath()
            front.move(to: NSPoint(x: -14, y: 0))
            front.line(to: NSPoint(x: 14, y: 0))
            front.line(to: NSPoint(x: 14, y: 8))
            front.line(to: NSPoint(x: -14, y: 8))
            front.close()
            front.transform(using: t)
            front.addClip()
            knockout { ring.lineWidth = 2.6; ring.stroke() }
            ring.lineWidth = 1.2
            ring.stroke()
            NSGraphicsContext.restoreGraphicsState()
        case .uranus:
            // A thin, nearly upright ring behind the body.
            var t = AffineTransform(translationByX: 14.75, byY: 14.9)
            t.rotate(byDegrees: 8.2)
            let ring = NSBezierPath(ovalIn: NSRect(x: -1.3, y: -10.4, width: 2.6, height: 20.8))
            ring.transform(using: t)
            ring.lineWidth = 0.55
            ring.stroke()
            fillBody()
        default:
            fillBody()
        }
        switch self {
        case .venus where !outlined:
            // A wavy cloud band across the middle.
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 10.5, y: 15.2))
            wave.curve(to: NSPoint(x: 19.5, y: 15.4), controlPoint1: NSPoint(x: 13.5, y: 13.9), controlPoint2: NSPoint(x: 16, y: 16.4))
            wave.lineWidth = 0.6
            knockout { wave.stroke() }
        case .earth:
            NSBezierPath(ovalIn: NSRect(x: 7.75, y: 11, width: 1.5, height: 1.5)).fill()
        case .mars where !outlined:
            // Polar caps: short cuts near the top and bottom.
            for y in [11.9, 18.1] as [CGFloat] {
                let cap = NSBezierPath()
                cap.move(to: NSPoint(x: 13.4, y: y))
                cap.line(to: NSPoint(x: 16.4, y: y))
                cap.lineWidth = 0.5
                knockout { cap.stroke() }
            }
        case .jupiter:
            knockout { NSBezierPath(ovalIn: NSRect(x: 17.1, y: 16.2, width: 3.6, height: 3.6)).fill() }
        default: break
        }
        ctx.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}

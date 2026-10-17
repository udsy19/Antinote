import AppKit

/// Line-art glyphs for the window chrome, drawn in code: thin rounded strokes, each with a small "sparkle".
/// Template images (tinted by the button that shows them).
enum ChromeIcon: CaseIterable {
    case settings, search, new, pin, previous, next, front, export, delete

    /// Glyph box in points (the hit target around it is larger). Glyphs are designed on a 16-unit grid.
    static let size: CGFloat = 13

    var image: NSImage {
        let s = Self.size
        let image = NSImage(size: NSSize(width: s, height: s), flipped: true) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: s / 16)
            scale.concat()
            NSColor.black.set()
            self.draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func stroke(_ path: NSBezierPath, width: CGFloat = 1.45) {
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

    private func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat = 1.3) {
        NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
    }

    /// A tiny four-point star.
    private func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat = 1.6) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: y - r))
        p.curve(to: NSPoint(x: x + r, y: y), controlPoint1: NSPoint(x: x + r * 0.15, y: y - r * 0.15),
                controlPoint2: NSPoint(x: x + r * 0.15, y: y - r * 0.15))
        p.curve(to: NSPoint(x: x, y: y + r), controlPoint1: NSPoint(x: x + r * 0.15, y: y + r * 0.15),
                controlPoint2: NSPoint(x: x + r * 0.15, y: y + r * 0.15))
        p.curve(to: NSPoint(x: x - r, y: y), controlPoint1: NSPoint(x: x - r * 0.15, y: y + r * 0.15),
                controlPoint2: NSPoint(x: x - r * 0.15, y: y + r * 0.15))
        p.curve(to: NSPoint(x: x, y: y - r), controlPoint1: NSPoint(x: x - r * 0.15, y: y - r * 0.15),
                controlPoint2: NSPoint(x: x - r * 0.15, y: y - r * 0.15))
        p.fill()
    }

    private func ring(_ center: NSPoint, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private func draw() {
        switch self {
        case .settings:
            // Three sliders with knobs at different positions.
            for (y, knob) in [(CGFloat(3.5), CGFloat(10)), (8, 12.5), (12.5, 4.5)] {
                stroke(line([(1.5, y), (knob - 2, y)]))
                stroke(line([(knob + 2, y), (14.5, y)]))
                stroke(ring(NSPoint(x: knob, y: y), 2))
            }
            dot(1.6, 6)
        case .search:
            // A magnifier whose lens is a ringed planet.
            let c = NSPoint(x: 7, y: 7)
            stroke(ring(c, 4.4))
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: NSRect(x: -2, y: -2, width: 20, height: 20))
            outside.append(ring(c, 4.4).reversed)
            outside.addClip()
            let orbit = NSBezierPath(ovalIn: NSRect(x: -6.8, y: -1.7, width: 13.6, height: 3.4))
            var t = AffineTransform(translationByX: c.x, byY: c.y + 0.4)
            t.rotate(byDegrees: -8)
            orbit.transform(using: t)
            stroke(orbit, width: 1.2)
            NSGraphicsContext.restoreGraphicsState()
            stroke(line([(10.2, 10.6), (12.8, 14.2)]))
            sparkle(14.4, 10.6, 1.4)
        case .new:
            // A rounded square with a pen stroke out of its top-right corner.
            let square = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 11, height: 11), xRadius: 2.8, yRadius: 2.8)
            stroke(square)
            stroke(line([(6.8, 9.2), (13.2, 2.8)]))
            sparkle(14.6, 1.2, 1.2)
        case .pin:
            // A pushpin from the side over a baseline.
            stroke(ring(NSPoint(x: 8, y: 4.8), 3.1))
            stroke(line([(8, 7.9), (8, 13.4)]))
            stroke(line([(2.8, 13.6), (13.2, 13.6)]))
            dot(10.8, 11.6)
        case .previous:
            stroke(line([(2.5, 8), (8.6, 4.6), (8.6, 11.4)], close: true))
            stroke(line([(12, 2.5), (12, 13.5)]))
            dot(9.6, 2.4)
        case .next:
            stroke(line([(4, 2.5), (4, 13.5)]))
            stroke(line([(7.4, 4.6), (13.5, 8), (7.4, 11.4)], close: true))
            dot(1.8, 13.4)
        case .front:
            stroke(line([(0.8, 8), (8.8, 8)]))
            stroke(line([(4, 3.5), (4, 12.5)]))
            stroke(line([(6.6, 3.5), (6.6, 12.5)]))
            stroke(line([(9.2, 4.6), (15.2, 8), (9.2, 11.4)], close: true))
        case .export:
            stroke(NSBezierPath(roundedRect: NSRect(x: 2.5, y: 8.5, width: 11, height: 6), xRadius: 2, yRadius: 2))
            stroke(line([(8, 6.3), (8, 11)]))
            stroke(line([(5.6, 6.3), (8, 1.8), (10.4, 6.3)], close: true))
        case .delete:
            // A trash can: lid with a handle, a tapered body and three slots.
            stroke(line([(1.8, 4.2), (14.2, 4.2)]))
            stroke(line([(6.2, 4.2), (6.2, 2.4), (9.8, 2.4), (9.8, 4.2)]))
            stroke(line([(3.2, 4.2), (4.2, 14), (11.8, 14), (12.8, 4.2)]))
            for x in [6.2, 8, 9.8] as [CGFloat] { stroke(line([(x, 7.2), (x, 11)]), width: 1.1) }
            dot(8, 0.9)
        }
    }
}

/// The nine slots are the planets, Mercury to Pluto, drawn at their relative sizes.
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

    /// Body diameter in points (measured against the 24 pt bar).
    var diameter: CGFloat {
        switch self {
        case .mercury: 2.2
        case .pluto: 2
        case .venus: 6.8
        case .earth: 6
        case .mars: 5
        case .jupiter: 12.5
        case .saturn: 8.5
        case .uranus: 6
        case .neptune: 6.4
        }
    }

    /// Draws the planet centred at `c` in `color`; details are cut out with `cutout` (the bar's fill).
    func draw(at c: NSPoint, color: NSColor, cutout: NSColor) {
        let d = diameter
        let body = NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        color.setFill()
        color.setStroke()
        switch self {
        case .saturn, .uranus:
            NSBezierPath(ovalIn: body).fill()
            let ring = self == .saturn
                ? NSBezierPath(ovalIn: NSRect(x: -8, y: -1.9, width: 16, height: 3.8))
                : NSBezierPath(ovalIn: NSRect(x: -1.5, y: -5.6, width: 3, height: 11.2))
            var t = AffineTransform(translationByX: c.x, byY: c.y)
            t.rotate(byDegrees: self == .saturn ? 8 : -10)
            ring.transform(using: t)
            ring.lineWidth = self == .saturn ? 1.2 : 0.5
            ring.stroke()
        default:
            NSBezierPath(ovalIn: body).fill()
        }
        cutout.setStroke()
        cutout.setFill()
        switch self {
        case .venus:
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: body.minX, y: c.y))
            wave.curve(to: NSPoint(x: body.maxX, y: c.y), controlPoint1: NSPoint(x: c.x - 1, y: c.y + 3),
                       controlPoint2: NSPoint(x: c.x + 1, y: c.y - 3))
            wave.lineWidth = 0.7
            wave.stroke()
        case .earth:
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: body.minX - 1.8, y: body.minY - 1.2, width: 1.2, height: 1.2)).fill()
        case .mars:
            for y in [body.minY + 0.9, body.maxY - 0.9] {
                let cap = NSBezierPath()
                cap.move(to: NSPoint(x: c.x - 1.5, y: y))
                cap.line(to: NSPoint(x: c.x + 1.5, y: y))
                cap.lineWidth = 0.5
                cap.stroke()
            }
        case .jupiter:
            NSBezierPath(ovalIn: NSRect(x: c.x + 1.4, y: c.y - 4.4, width: 2.8, height: 2.8)).fill()
        default: break
        }
    }
}

// Renders the Super Notes app icon into an .iconset directory: an index card on a warm field, a few ink lines and a
// single teal check — "jot it down, tick it off".
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.098
    let body = CGRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Field: deep teal-ink.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.3))
    ctx.addPath(squircle); ctx.setFillColor(color(0x173B36)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let field = CGGradient(colorsSpace: srgb, colors: [color(0x1F4E47), color(0x123029)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(field, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // Card, tilted slightly.
    let card = CGRect(x: body.midX - body.width * 0.31, y: body.midY - body.height * 0.34,
                      width: body.width * 0.62, height: body.height * 0.68)
    ctx.saveGState()
    ctx.translateBy(x: card.midX, y: card.midY); ctx.rotate(by: -0.07); ctx.translateBy(x: -card.midX, y: -card.midY)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.035, color: color(0x000000, 0.35))
    let cardPath = CGPath(roundedRect: card, cornerWidth: s * 0.035, cornerHeight: s * 0.035, transform: nil)
    ctx.addPath(cardPath); ctx.setFillColor(color(0xF7F4EC)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // Ink lines.
    ctx.setStrokeColor(color(0x1C1B17)); ctx.setLineCap(.round); ctx.setLineWidth(s * 0.028)
    let left = card.minX + card.width * 0.16
    for (i, w) in [0.62, 0.48, 0.55].enumerated() {
        let y = card.maxY - card.height * (0.24 + Double(i) * 0.17)
        ctx.move(to: CGPoint(x: left, y: y)); ctx.addLine(to: CGPoint(x: left + card.width * w, y: y))
    }
    ctx.strokePath()
    // Teal check at the bottom.
    ctx.setStrokeColor(color(0x18A383)); ctx.setLineWidth(s * 0.045); ctx.setLineJoin(.round)
    let c = CGPoint(x: left + card.width * 0.08, y: card.minY + card.height * 0.2)
    ctx.move(to: CGPoint(x: c.x - card.width * 0.02, y: c.y + card.height * 0.05))
    ctx.addLine(to: CGPoint(x: c.x + card.width * 0.07, y: c.y - card.height * 0.03))
    ctx.addLine(to: CGPoint(x: c.x + card.width * 0.26, y: c.y + card.height * 0.15))
    ctx.strokePath()
    ctx.restoreGState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

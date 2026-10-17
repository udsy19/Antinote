import AppKit
import UniformTypeIdentifiers
import JotterCore

/// Alternate app icons, drawn in code, plus a user-supplied image (`Defaults[.appIcon] == "custom"`).
@MainActor
enum AppIcons {
    struct Style: Identifiable, Sendable {
        let id: String
        let name: String
        let top: String
        let bottom: String
        let paper: String
        let ink: String
    }

    static let styles: [Style] = [
        Style(id: "default", name: "Classic", top: "#FF7A59", bottom: "#E5484D", paper: "#FBF8F1", ink: "#C9C2B3"),
        Style(id: "midnight", name: "Midnight", top: "#2B3A67", bottom: "#0F1626", paper: "#1E2944", ink: "#F2B544"),
        Style(id: "mint", name: "Mint", top: "#5FD3A0", bottom: "#16875B", paper: "#F2FBF6", ink: "#9CCDB4"),
        Style(id: "sunset", name: "Sunset", top: "#FFC86B", bottom: "#B4572E", paper: "#FFF6E6", ink: "#E0B98A"),
    ]
    static let customID = "custom"

    static var customIconURL: URL { JotterPaths.support.appendingPathComponent("AppIcon.png") }

    static func apply() {
        let id = Defaults[.appIcon]
        if id == customID, let image = NSImage(contentsOf: customIconURL) {
            NSApp.applicationIconImage = image
        } else if id == "default", Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
                    || Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil {
            NSApp.applicationIconImage = nil   // the bundle's own icon
        } else {
            NSApp.applicationIconImage = image(for: styles.first { $0.id == id } ?? styles[0])
        }
    }

    static func select(_ id: String) {
        Defaults[.appIcon] = id
        apply()
        HUD.show("App icon updated")
    }

    /// Copies the chosen image into Application Support and selects it.
    static func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.message = "Choose an image to use as the Jotter app icon"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            Alerts.error("That file couldn't be read as an image.")
            return
        }
        do {
            try png.write(to: customIconURL, options: .atomic)
            select(customID)
        } catch {
            Alerts.error("The icon couldn't be saved.", error)
        }
    }

    /// The status-item glyph: an outlined equilateral triangle (1.5 pt stroke, mitred corners) in a 16 pt template.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 8.25, y: 3))
            triangle.line(to: NSPoint(x: 14.45, y: 14))
            triangle.line(to: NSPoint(x: 2.05, y: 14))
            triangle.close()
            triangle.lineWidth = 1.5
            triangle.lineJoinStyle = .miter
            NSColor.black.setStroke()
            triangle.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jotter"
        return image
    }()

    /// A rounded tile with a gradient, a sheet of paper with a folded corner, ruled lines and a checkbox.
    static func image(for style: Style, size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.1, dy: s * 0.1), xRadius: s * 0.18, yRadius: s * 0.18)
            NSGradient(starting: NSColor(hex: style.top), ending: NSColor(hex: style.bottom))?.draw(in: tile, angle: -90)

            let sheet = NSRect(x: s * 0.27, y: s * 0.22, width: s * 0.46, height: s * 0.56)
            let fold = s * 0.12
            let paper = NSBezierPath()
            paper.move(to: NSPoint(x: sheet.minX, y: sheet.minY))
            paper.line(to: NSPoint(x: sheet.maxX, y: sheet.minY))
            paper.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
            paper.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
            paper.line(to: NSPoint(x: sheet.minX, y: sheet.maxY))
            paper.close()
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
            shadow.shadowBlurRadius = s * 0.03
            shadow.set()
            NSColor(hex: style.paper).setFill()
            paper.fill()
            NSGraphicsContext.restoreGraphicsState()

            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
            corner.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
            corner.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
            corner.close()
            NSColor(hex: style.ink).withAlphaComponent(0.6).setFill()
            corner.fill()

            let ink = NSColor(hex: style.ink)
            for i in 0..<4 {
                let y = sheet.maxY - fold - s * 0.06 - CGFloat(i) * s * 0.085
                let start = i == 0 ? sheet.minX + s * 0.11 : sheet.minX + s * 0.05
                let line = NSBezierPath(roundedRect: NSRect(x: start, y: y, width: sheet.maxX - s * 0.06 - start, height: s * 0.022),
                                        xRadius: s * 0.011, yRadius: s * 0.011)
                ink.setFill()
                line.fill()
            }
            let box = NSBezierPath(roundedRect: NSRect(x: sheet.minX + s * 0.05, y: sheet.maxY - fold - s * 0.075,
                                                       width: s * 0.045, height: s * 0.045), xRadius: s * 0.01, yRadius: s * 0.01)
            box.lineWidth = s * 0.01
            NSColor(hex: style.bottom).setStroke()
            box.stroke()
            return true
        }
    }
}

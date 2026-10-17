import AppKit
import UniformTypeIdentifiers
import SuperNotesCore

/// Alternate app icons, drawn in code, plus a user-supplied image (`Defaults[.appIcon] == "custom"`).
@MainActor
enum AppIcons {
    struct Style: Identifiable, Sendable {
        let id: String
        let name: String
        let top: String
        let bottom: String
        let ink: String
    }

    /// Colourways of the lines icon; "default" is the bundle's own icon.
    static let styles: [Style] = [
        Style(id: "default", name: "Light", top: "#FFFFFF", bottom: "#EFEFEF", ink: "#141414"),
        Style(id: "dark", name: "Dark", top: "#1C1C1C", bottom: "#0A0A0A", ink: "#F5F5F5"),
        Style(id: "paper", name: "Paper", top: "#F7F3EA", bottom: "#ECE5D6", ink: "#2B2621"),
        Style(id: "sage", name: "Sage", top: "#E4ECE5", bottom: "#CCDACF", ink: "#1E3A2C"),
    ]
    static let customID = "custom"

    static var customIconURL: URL { SuperNotesPaths.support.appendingPathComponent("AppIcon.png") }

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
        panel.message = "Choose an image to use as the Super Notes app icon"
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

    /// The status-item glyph: the icon's three lines (the last one short) as a 16 pt template.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, width) in [(3.5, 11.0), (7.25, 11.0), (11.0, 6.5)] {
                NSBezierPath(roundedRect: NSRect(x: 2.5, y: y, width: width, height: 1.75), xRadius: 0.875, yRadius: 0.875).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Super Notes"
        return image
    }()

    /// The lines icon in a colourway: a squircle with three ink lines, the last one short.
    static func image(for style: Style, size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let body = NSRect(x: s * 0.098, y: s * 0.113, width: s * 0.804, height: s * 0.804)
            let tile = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
            shadow.shadowBlurRadius = s * 0.03
            shadow.set()
            NSColor(hex: style.top).setFill()
            tile.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: NSColor(hex: style.top), ending: NSColor(hex: style.bottom))?.draw(in: tile, angle: -90)

            let x = body.minX + body.width * 0.25, w = body.width * 0.5, h = body.height * 0.07
            NSColor(hex: style.ink).setFill()
            for (dy, width) in [(1.75, w), (-0.5, w), (-2.75, w * 0.58)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: body.midY + h * dy, width: width, height: h),
                             xRadius: h / 2, yRadius: h / 2).fill()
            }
            return true
        }
    }
}

import AppKit
import SuperNotesCore
import StorageKit
import NoteEngine
import EditorKit
import ShellKit
import ToolsKit
import AIKit

// Renders Super Notes' views offscreen to PNG files for visual checks. Nothing is ever shown on screen: windows are
// created but never ordered front, and the app never runs or activates.
//
//     swift build && .build/debug/SuperNotesRender <out-dir> [scene-prefix …]
//
// With no prefixes every scene is rendered. Preferences go to a throwaway defaults suite and notes to a
// temporary database, so the user's own data is never touched.

@MainActor
struct Scene {
    var name: String
    var size: NSSize
    var dark = false
    /// Builds the view to render (called after the appearance is set).
    var make: () -> NSView
}

@MainActor
enum Render {
    static let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                                 styleMask: [.borderless], backing: .buffered, defer: false)

    /// Lays `view` out at `size` and writes it, at the screen's backing scale, as a PNG.
    static func png(_ view: NSView, size: NSSize, to url: URL) throws {
        window.setContentSize(size)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        drawCarets(in: view, onto: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }

    /// Renders an AppKit view tree by calling each view's `draw(_:)` (filling layer background colours; shadows
    /// are skipped). Used for window frames, where layer-backed text views stay blank in `cacheDisplay` because
    /// the window has never been on screen. Returns an image view of the result.
    static func drawn(_ root: NSView) -> NSView {
        root.layoutSubtreeIfNeeded()
        let scale = max(root.window?.backingScaleFactor ?? 2, 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width * scale),
                                         pixelsHigh: Int(root.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSView() }
        rep.size = root.bounds.size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return NSView() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        drawTree(root, root: root, alpha: 1)
        NSGraphicsContext.restoreGraphicsState()
        drawCarets(in: root, onto: rep)
        let image = NSImage(size: root.bounds.size)
        image.addRepresentation(rep)
        let view = NSImageView(image: image)
        view.imageScaling = .scaleNone
        view.imageAlignment = .alignTop
        return view
    }

    private static func drawTree(_ v: NSView, root: NSView, alpha: CGFloat) {
        let a = alpha * v.alphaValue
        // The scroll edge effect (macOS 26) only shows once content scrolls under the title bar.
        guard !v.isHidden, a > 0.01, "\(type(of: v))" != "NSScrollPocket", let outer = NSGraphicsContext.current else { return }
        let cg = outer.cgContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: v.isFlipped)
        transform(from: v, to: root).concat()
        let visible = v.visibleRect.intersection(v.bounds)
        NSBezierPath(rect: visible).addClip()
        cg.setAlpha(a)
        let isGlass: Bool = if #available(macOS 26, *) { v is NSGlassEffectView } else { false }
        if !isGlass, let layer = v.layer, let fill = layer.backgroundColor, fill.alpha > 0, let color = NSColor(cgColor: fill) {
            color.setFill()
            NSBezierPath(roundedRect: v.bounds, xRadius: layer.cornerRadius, yRadius: layer.cornerRadius).fill()
        }
        // Liquid Glass can't be captured offscreen: a tinted glass shape stands in as a frosted fill of its tint
        // colour with a hairline edge.
        if #available(macOS 26, *), let glass = v as? NSGlassEffectView, let tint = glass.tintColor {
            let shape = NSBezierPath(roundedRect: v.bounds, xRadius: glass.cornerRadius, yRadius: glass.cornerRadius)
            tint.withAlphaComponent(0.85).setFill()
            shape.fill()
            NSColor.gray.withAlphaComponent(0.25).setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
        v.draw(visible)
        cg.setAlpha(1)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.current = outer
        // Glass draws its own private layers; only its content view (if any) is ours.
        if #available(macOS 26, *), let glass = v as? NSGlassEffectView {
            if let content = glass.contentView { drawTree(content, root: root, alpha: a) }
            return
        }
        for sub in v.subviews { drawTree(sub, root: root, alpha: a) }
    }

    /// Maps `v`'s coordinates onto a bottom-left-origin context covering `root`.
    private static func transform(from v: NSView, to root: NSView) -> NSAffineTransform {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            let q = v.convert(NSPoint(x: x, y: y), to: root)
            return root.isFlipped ? NSPoint(x: q.x, y: root.bounds.height - q.y) : q
        }
        let o = p(0, 0), ex = p(1, 0), ey = p(0, 1)
        let xf = NSAffineTransform()
        xf.transformStruct = NSAffineTransformStruct(m11: ex.x - o.x, m12: ex.y - o.y, m21: ey.x - o.x, m22: ey.y - o.y,
                                                     tX: o.x, tY: o.y)
        return xf
    }

    /// Text views don't draw their caret unless they're first responder in a key window, so draw it here.
    private static func drawCarets(in root: NSView, onto rep: NSBitmapImageRep) {
        for tv in textViews(in: root) where tv.isEditable && tv.selectedRange().length == 0 && !tv.isHiddenOrHasHiddenAncestor {
            guard let caret = caretRect(tv), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
            transform(from: tv, to: root).concat()
            tv.drawInsertionPoint(in: caret, color: tv.insertionPointColor, turnedOn: true)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    /// The insertion-point rect AppKit would use: the line fragment's height at the caret's x.
    private static func caretRect(_ tv: NSTextView) -> NSRect? {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        lm.ensureLayout(for: tc)
        let index = tv.selectedRange().location
        let length = (tv.string as NSString).length
        let origin = tv.textContainerOrigin
        if index == length, length == 0 || tv.string.hasSuffix("\n") {
            let frag = lm.extraLineFragmentRect == .zero ? NSRect(x: 0, y: 0, width: 0, height: 20) : lm.extraLineFragmentRect
            return NSRect(x: frag.minX + origin.x, y: frag.minY + origin.y, width: 1, height: frag.height)
        }
        let atEnd = index >= length
        let glyph = lm.glyphIndexForCharacter(at: atEnd ? length - 1 : index)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        var x = lm.location(forGlyphAt: glyph).x
        if atEnd { x = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc).maxX - frag.minX }
        return NSRect(x: frag.minX + x + origin.x, y: frag.minY + origin.y, width: 1, height: frag.height)
    }
}

// MARK: - Setup

let app = NSApplication.shared
let args = Array(CommandLine.arguments.dropFirst())
guard let outPath = args.first else {
    print("usage: SuperNotesRender <out-dir> [scene-prefix …]")
    exit(2)
}
let filters = Array(args.dropFirst())
let out = URL(fileURLWithPath: outPath, isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let suite = "com.udsy.supernotes.render"
UserDefaults().removePersistentDomain(forName: suite)
Defaults.store = UserDefaults(suiteName: suite)!
Defaults[.onboardingCompleted] = true

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SuperNotesRender-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
SuperNotesPaths.base = temp   // custom themes, rates cache and extensions resolve inside the temporary folder
MainActor.assumeIsolated {
    Services.store = try! SQLiteNoteStore(url: temp.appendingPathComponent("notes.sqlite"),
                                          backupsFolder: temp.appendingPathComponent("Backups"))
    Services.analyzer = NoteEngine(rates: { ExchangeRates(perUSD: ["EUR": 0.92, "CAD": 1.37, "JPY": 148.6, "GBP": 0.79]) })
    Services.editorFactory = SuperNotesEditorFactory()
    // Settings → AI over an empty Models folder; nothing is downloaded (the service is never started).
    let models = ModelDownloader(spec: ModelCatalog.default, folder: temp.appendingPathComponent("Models"),
                                 conditions: { DownloadConditions(networkOK: true, lowPowerMode: false, freeDiskBytes: 100_000_000_000) })
    Services.ai = AIService(downloader: models, tools: [])
}

// MARK: - Run

MainActor.assumeIsolated {
    let scenes = Scenes.all.filter { s in filters.isEmpty || filters.contains { s.name.hasPrefix($0) } }
    for scene in scenes {
        app.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
        let url = out.appendingPathComponent(scene.name + ".png")
        do {
            try Render.png(scene.make(), size: scene.size, to: url)
            print("wrote \(url.path)")
        } catch {
            print("failed \(scene.name): \(error.localizedDescription)")
        }
    }
}
try? FileManager.default.removeItem(at: temp)
UserDefaults().removePersistentDomain(forName: suite)

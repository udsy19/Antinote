import AppKit
import JotterCore
import SwiftUI

/// Full-screen timer surfaces on a dark, softly lit backdrop: the pomodoro break screen, the completion alerts,
/// the breathing exercise and the live "full screen" timer.
@MainActor
final class TimerOverlay {
    static let shared = TimerOverlay()

    struct Live { var title: String; var subtitle: String; var progress: Double }

    /// What the break screen reads and does for the pomodoro whose work session just ended.
    struct Break {
        var noteID: UUID
        var fact: String
        /// Seconds of break left (nil once the break is over).
        var remaining: () -> TimeInterval?
        var isPaused: () -> Bool
        var togglePause: () -> Void
        /// "End Pomodoro": stops the timer.
        var end: () -> Void
        /// "Sneak a peek" (or Esc): closes the screen and breaks the no-peek streak.
        var peek: () -> Void
        var streak: () -> NoPeekStreak
    }

    private var panel: KeyPanel?
    /// The note whose break screen is showing.
    private(set) var breakNoteID: UUID?

    func showBreak(_ model: Break) {
        present(OverlayView(mode: .breakTime(model), close: { [weak self] in self?.close() })) {
            model.peek()
        }
        breakNoteID = model.noteID
    }

    func showAlert(title: String, subtitle: String, message: String) {
        present(OverlayView(mode: .alert(title: title, subtitle: subtitle, message: message),
                            close: { [weak self] in self?.close() }))
    }

    func showBreathing() {
        present(OverlayView(mode: .breathe(started: Date()), close: { [weak self] in self?.close() }))
    }

    func showLive(_ provider: @escaping () -> Live?) {
        present(OverlayView(mode: .live(provider), close: { [weak self] in self?.close() }))
    }

    func close() {
        breakNoteID = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// `onEscape` runs before the overlay closes on Esc (the break screen counts Esc as a peek).
    private func present(_ view: OverlayView, onEscape: (() -> Void)? = nil) {
        panel?.orderOut(nil)
        breakNoteID = nil
        let screen = NSScreen.active
        let p = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.onEscape = { [weak self] in onEscape?(); self?.close() }
        p.contentView = Self.hosting(view)
        p.setFrame(screen.frame, display: true)
        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; p.animator().alphaValue = 1 }
        panel = p
    }

    private static func hosting(_ view: OverlayView) -> NSView {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        return host
    }

    /// The overlay content for offscreen renders.
    static func preview(_ mode: OverlayView.Mode) -> NSView { hosting(OverlayView(mode: mode, close: {})) }
}

/// Colours of the overlay (it is always dark, whatever the theme).
private enum Palette {
    static let backdrop = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x33 / 255)
    static let title = Color(white: 0xE6 / 255)
    static let subtitle = Color(white: 0xBD / 255)
    static let message = Color(white: 0xED / 255)
    static let caption = Color(white: 0x9A / 255)
    static let streak = Color(red: 0xF5 / 255, green: 0xD9 / 255, blue: 0x0A / 255)
}

struct OverlayView: View {
    enum Mode {
        case breakTime(TimerOverlay.Break)
        case alert(title: String, subtitle: String, message: String)
        case breathe(started: Date)
        case live(() -> TimerOverlay.Live?)
    }

    @State var mode: Mode
    let close: () -> Void
    private let accent = Color(nsColor: NSColor(hex: Theme.defaultDark.accent1Main))

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) { content }
                .padding(40)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case let .breakTime(model):
            Mark()
            Spacer().frame(height: 40)
            Title("Break Time")
            Spacer().frame(height: 10)
            Subtitle("Wildlife fact-file")
            Spacer().frame(height: 30)
            Message(model.fact)
            Spacer().frame(height: 18)
            Text("Break time remaining:").font(.system(size: 13)).foregroundStyle(Palette.caption)
            Spacer().frame(height: 6)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 14) {
                    Button(action: model.togglePause) {
                        Image(systemName: model.isPaused() ? "play.fill" : "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.title)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(model.isPaused() ? "Resume" : "Pause")
                    Text(TimerFormat.clock((model.remaining() ?? 0).rounded(.up)))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.title)
                }
            }
            Spacer().frame(height: 24)
            HStack(spacing: 40) {
                Pill("Sneak a peek") { model.peek(); close() }
                Pill("End Pomodoro") { model.end(); close() }
            }
            Spacer().frame(height: 12)
            let streak = model.streak()
            (Text("No-Peek Streak: ") + Text("\(streak.current)").bold().foregroundColor(Palette.streak)
                + Text(" (Best: ") + Text("\(streak.best)").bold().foregroundColor(Palette.streak) + Text(")"))
                .font(.system(size: 13))
                .foregroundStyle(Palette.caption)
        case let .alert(title, subtitle, message):
            Mark()
            Spacer().frame(height: 40)
            Title(title)
            Spacer().frame(height: 10)
            Subtitle(subtitle)
            Spacer().frame(height: 30)
            Message(message)
            Spacer().frame(height: 28)
            HStack(spacing: 40) {
                Pill("Breathe") { mode = .breathe(started: Date()) }
                Pill("Dismiss", action: close).keyboardShortcut(.defaultAction)
            }
        case let .breathe(started):
            BreathingCircle(started: started, color: accent)
            Spacer().frame(height: 40)
            Pill("Done", action: close)
        case let .live(provider):
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let live = provider()
                VStack(spacing: 18) {
                    Text(live?.title ?? "Timer stopped")
                        .font(.system(size: 140, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.title)
                        .minimumScaleFactor(0.3).lineLimit(1)
                    Subtitle(live?.subtitle ?? "")
                    ProgressView(value: live?.progress ?? 0).frame(maxWidth: 420).tint(accent)
                }
            }
            Spacer().frame(height: 40)
            Pill("Dismiss", action: close)
        }
    }
}

/// The dark translucent field with soft colour bloom in the lower corners.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            VisualEffect().ignoresSafeArea()
            Palette.backdrop.opacity(0.85).ignoresSafeArea()
            GeometryReader { geo in
                let r = max(geo.size.width, geo.size.height) * 0.55
                RadialGradient(colors: [Color(red: 0.36, green: 0.16, blue: 0.78).opacity(0.5), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: r)
                RadialGradient(colors: [Color(red: 0.24, green: 0.33, blue: 0.45).opacity(0.45), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: r * 0.8)
            }
            .ignoresSafeArea()
        }
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Jotter's own app icon as the overlay's mark.
private struct Mark: View {
    var body: some View {
        Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: 72, height: 72)
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 44, weight: .bold)).foregroundStyle(Palette.title).multilineTextAlignment(.center)
    }
}

private struct Subtitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 13)).tracking(3).foregroundStyle(Palette.subtitle)
    }
}

private struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 20)).foregroundStyle(Palette.message).multilineTextAlignment(.center)
            .frame(maxWidth: 620)
    }
}

/// A rounded bezel button: 18 pt text on 25 % white.
private struct Pill: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 18)).foregroundStyle(Palette.message)
                .padding(.horizontal, 16).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.25)))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// A circle that grows while breathing in and shrinks while breathing out (`TimerRun` breathing rhythm).
private struct BreathingCircle: View {
    let started: Date
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let breath = TimerRun(spec: TimerSpec(kind: .breathe), now: started).snapshot(at: context.date)
            let eased = 0.5 - cos(breath.progress * .pi) / 2
            let inhaling = breath.phase == .breatheIn
            let scale = inhaling ? 0.35 + 0.65 * eased : 1 - 0.65 * eased
            VStack(spacing: 36) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 320, height: 320)
                    Circle().fill(color.opacity(0.75)).frame(width: 320, height: 320).scaleEffect(scale)
                }
                Title(inhaling ? "Breathe in." : "Breathe out.")
            }
        }
    }
}

/// Borderless panel that can become key and closes on Esc.
@MainActor
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

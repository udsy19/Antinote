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

    private static func hosting(_ view: OverlayView) -> NSView { NSHostingView(rootView: view) }

    /// The overlay content for offscreen renders.
    static func preview(_ mode: OverlayView.Mode) -> NSView { hosting(OverlayView(mode: mode, close: {})) }
}

/// The full-screen surfaces: an ultra-thin material over the whole screen with a centred column (at most 400 pt
/// wide) of the app mark, a 34 pt bold title, a 10 pt thin tracked caption, a 14 pt message and small standard
/// buttons, in the system's primary and secondary colours.
struct OverlayView: View {
    enum Mode {
        case breakTime(TimerOverlay.Break)
        case alert(title: String, subtitle: String, message: String)
        case breathe(started: Date)
        case live(() -> TimerOverlay.Live?)
    }

    @State var mode: Mode
    let close: () -> Void
    private var accent: Color { Color(nsColor: NSColor(hex: Theme.current.accent1Main)) }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 0) { content }
                .frame(maxWidth: 400)
                .padding(40)
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case let .breakTime(model):
            Mark()
            Title("Break Time")
            Caption("Wildlife fact-file")
            Message(model.fact)
            Text("Break time remaining:").font(.system(size: 10)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 8) {
                    Button(action: model.togglePause) {
                        Image(systemName: model.isPaused() ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(8)
                            .background(Circle().fill(Color.secondary.opacity(0.1)))
                    }
                    .buttonStyle(.borderless)
                    .help(model.isPaused() ? "Resume Break" : "Pause Break")
                    Text(TimerFormat.clock((model.remaining() ?? 0).rounded(.up)))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .frame(width: 50, alignment: .leading)
                }
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                SmallButton("Sneak a peek") { model.peek(); close() }
                SmallButton("End Pomodoro") { model.end(); close() }
            }
            .padding(.bottom, 4)
            let streak = model.streak()
            (Text("No-Peek Streak: ") + Text("\(streak.current)").bold().foregroundColor(accent)
                + Text(" (Best: ") + Text("\(streak.best)").bold().foregroundColor(accent) + Text(")"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
        case let .alert(title, subtitle, message):
            Mark()
            Title(title)
            Caption(subtitle)
            Message(message)
            SmallButton("Nice", action: close).keyboardShortcut(.defaultAction)
        case let .breathe(started):
            BreathingCircle(started: started, color: accent)
            Spacer().frame(height: 40)
            SmallButton("Done", action: close)
        case let .live(provider):
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let live = provider()
                VStack(spacing: 18) {
                    Text(live?.title ?? "Timer stopped")
                        .font(.system(size: 140, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.3).lineLimit(1)
                    Caption(live?.subtitle ?? "")
                    ProgressView(value: live?.progress ?? 0).frame(maxWidth: 400).tint(accent)
                }
            }
            Spacer().frame(height: 40)
            SmallButton("Dismiss", action: close)
        }
    }
}

/// Jotter's own app icon as the overlay's mark (80 pt).
private struct Mark: View {
    var body: some View {
        Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: 80, height: 80)
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.center).padding(.bottom, 5)
    }
}

/// "WILDLIFE FACT-FILE": 10 pt thin capitals tracked 2 pt.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .thin)).tracking(2).padding(.bottom, 20)
    }
}

private struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).multilineTextAlignment(.center)
            .frame(maxWidth: 400).padding(.bottom, 10)
    }
}

/// A standard push button with a 12 pt label.
private struct SmallButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).padding(.vertical, 2).padding(.horizontal, 5)
        }
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

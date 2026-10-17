import AppKit
import JotterCore
import SwiftUI

/// Full-screen timer surfaces: the completion alert (with the breathing exercise) and the live "full screen" timer.
@MainActor
final class TimerOverlay {
    static let shared = TimerOverlay()

    struct Live { var title: String; var subtitle: String; var progress: Double }

    private var panel: KeyPanel?

    func showAlert(title: String, message: String, encouragement: String, live: (() -> String?)?) {
        present(OverlayView(mode: .alert(title: title, message: message, encouragement: encouragement, live: live),
                            close: { [weak self] in self?.close() }))
    }

    func showBreathing() {
        present(OverlayView(mode: .breathe(started: Date()), close: { [weak self] in self?.close() }))
    }

    func showLive(_ provider: @escaping () -> Live?) {
        present(OverlayView(mode: .live(provider), close: { [weak self] in self?.close() }))
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func present(_ view: OverlayView) {
        panel?.orderOut(nil)
        let screen = NSScreen.active
        let p = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.onEscape = { [weak self] in self?.close() }
        p.contentView = NSHostingView(rootView: view)
        p.setFrame(screen.frame, display: true)
        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p
    }
}

private struct OverlayView: View {
    enum Mode {
        case alert(title: String, message: String, encouragement: String, live: (() -> String?)?)
        case breathe(started: Date)
        case live(() -> TimerOverlay.Live?)
    }

    @State var mode: Mode
    let close: () -> Void
    private let theme = Theme.current

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(hex: theme.background)).opacity(0.94).ignoresSafeArea()
            VStack(spacing: 28) {
                content
                HStack(spacing: 14) {
                    if case .alert = mode {
                        Button("Breathe") { mode = .breathe(started: Date()) }
                    }
                    Button("Dismiss", action: close).keyboardShortcut(.cancelAction)
                }
                .controlSize(.large)
                Text("Esc to close").font(.caption).foregroundStyle(color(theme.secondaryText))
            }
            .padding(60)
        }
        .foregroundStyle(color(theme.text))
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case let .alert(title, message, encouragement, live):
            Text(title).font(.system(size: 64, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text(message).font(.title2).foregroundStyle(color(theme.secondaryText)).multilineTextAlignment(.center)
            if let live {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(live() ?? "").font(.system(size: 48, weight: .medium, design: .monospaced))
                }
            }
            Text(encouragement).font(.title3).foregroundStyle(color(theme.accent))
        case let .breathe(started):
            BreathingCircle(started: started, color: color(theme.accent))
        case let .live(provider):
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let live = provider()
                VStack(spacing: 18) {
                    Text(live?.title ?? "Timer stopped")
                        .font(.system(size: 140, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.3).lineLimit(1)
                    Text(live?.subtitle ?? "").font(.title2).foregroundStyle(color(theme.secondaryText))
                    ProgressView(value: live?.progress ?? 0).frame(maxWidth: 420).tint(color(theme.accent))
                }
            }
        }
    }

    private func color(_ hex: String) -> Color { Color(nsColor: NSColor(hex: hex)) }
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
                Text(inhaling ? "Breathe in." : "Breathe out.").font(.system(size: 34, weight: .medium, design: .rounded))
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

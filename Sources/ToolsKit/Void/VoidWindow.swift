import AppKit
import Combine
import SuperNotesCore
import SwiftUI

/// The Void: deleted notes waiting to be recovered or erased. A black, always-dark window: "THE VOID" and a count
/// of deleted notes on top, the notes in monospace with outlined Restore / delete buttons, "Empty The Void" and "Done"
/// along the bottom.
@MainActor
final class VoidWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 520),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "The Void"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: VoidView.minSize.width, height: VoidView.minSize.height)
            w.contentViewController = NSHostingController(rootView: VoidView(model: VoidModel(), close: { [weak w] in w?.close() }))
            w.setFrameAutosaveName("SuperNotesVoidWindow")
            if !w.setFrameUsingName("SuperNotesVoidWindow") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class VoidModel: ObservableObject {
    @Published var notes: [Note] = []
    /// "Now" for the "Deleted 3 days ago" lines (fixed in renders).
    let now: () -> Date
    private var cancellable: AnyCancellable?

    init() {
        now = Date.init
        reload()
        cancellable = Services.store?.changes.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
    }

    /// Fixed notes, for offscreen renders.
    init(notes: [Note], now: Date) {
        self.notes = notes
        self.now = { now }
    }

    /// "Deleted 3 days ago".
    func lostText(_ note: Note) -> String? {
        guard let deleted = note.deletedAt else { return nil }
        let format = RelativeDateTimeFormatter()
        format.unitsStyle = .full
        return "Deleted " + format.localizedString(for: deleted, relativeTo: now())
    }

    func reload() { notes = Services.store?.void ?? [] }

    func recover(_ note: Note) {
        Services.store.restoreFromVoid(note.id)
        HUD.show("Note restored", kind: .success)
    }

    func open(_ note: Note) {
        Services.store.restoreFromVoid(note.id)
        Services.windows?.show(noteID: note.id)
    }

    func delete(_ note: Note) {
        guard Alerts.confirm("Delete this note forever?", info: "This can't be undone.",
                             confirmTitle: "Delete", destructive: true) else { return }
        Services.store.deletePermanently(note.id)
        HUD.show("Note permanently deleted")
    }

    func emptyVoid() {
        guard !notes.isEmpty else { HUD.show("Nothing to delete"); return }
        let count = notes.count
        guard Alerts.confirm("Empty The Void?",
                             info: "\(count) note\(count == 1 ? "" : "s") will be deleted forever. This can't be undone.",
                             confirmTitle: "Empty The Void", destructive: true) else { return }
        for note in notes { Services.store.deletePermanently(note.id) }
        HUD.show("Emptied \(count) note\(count == 1 ? "" : "s") from The Void")
    }
}

/// The Void's palette and type: white text at 55 % and 40 % on black, red (1, 0.4, 0.4) for destroying, monospace
/// body / caption / medium title 2.
private enum VoidStyle {
    static let text = Color(white: 0.55)
    static let faint = Color(white: 0.4)
    static let destroy = Color(red: 1, green: 0.4, blue: 0.4)
    static let body = Font.system(.body, design: .monospaced)
    static let caption = Font.system(.caption, design: .monospaced)
    static let title = Font.system(.title2, design: .monospaced).weight(.medium)
}

struct VoidView: View {
    static let minSize = CGSize(width: 450, height: 400)
    @ObservedObject var model: VoidModel
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("THE VOID").font(VoidStyle.title).tracking(4).foregroundStyle(VoidStyle.text)
                    Text(model.notes.count == 1 ? "1 deleted note" : "\(model.notes.count) deleted notes").font(VoidStyle.caption).foregroundStyle(VoidStyle.faint)
                }
                .padding()
                .padding(.top, 12)
                rule
                if model.notes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(VoidStyle.faint)
                        Text("The Void is empty").font(VoidStyle.body).foregroundStyle(VoidStyle.text)
                        Text("Notes you delete wait here until The Void is emptied").font(VoidStyle.caption).foregroundStyle(VoidStyle.faint)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.notes) { note in VoidRow(note: note, model: model) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                rule
                HStack(spacing: 12) {
                    Spacer()
                    Button("Empty The Void") { model.emptyVoid() }
                        .buttonStyle(VoidButtonStyle(tint: VoidStyle.destroy))
                        .opacity(model.notes.isEmpty ? 0.5 : 1)
                    Button("Done", action: close)
                        .buttonStyle(VoidButtonStyle(tint: .white))
                        .keyboardShortcut(.defaultAction)
                }
                .font(VoidStyle.caption)
                .padding()
            }
        }
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .environment(\.colorScheme, .dark)
    }

    private var rule: some View { VoidStyle.faint.opacity(0.3).frame(height: 1) }
}

private struct VoidRow: View {
    let note: Note
    let model: VoidModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview).font(VoidStyle.body).foregroundStyle(VoidStyle.text).lineLimit(2)
                if let lost = model.lostText(note) {
                    Text(lost).font(VoidStyle.caption).foregroundStyle(VoidStyle.faint)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Restore") { model.recover(note) }
                    .buttonStyle(VoidButtonStyle(tint: .white))
                    .help("Put the note back at the front of the deck")
                Button { model.delete(note) } label: { Image(systemName: "xmark") }
                    .buttonStyle(VoidButtonStyle(tint: VoidStyle.destroy))
                    .help("Delete forever")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(note) }
        .contextMenu {
            Button("Restore") { model.recover(note) }
            Button("Restore and Open") { model.open(note) }
            Divider()
            Button("Delete Forever…", role: .destructive) { model.delete(note) }
        }
    }

    private var preview: String {
        let lines = note.content.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? "(Empty note)" : lines.prefix(2).joined(separator: " ")
    }
}

/// An outlined button in the tint colour: 4 pt corners, a 1 pt border at 25 % (50 % on hover), a 15 % wash on hover,
/// and a slight shrink while pressed.
private struct VoidButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View { Outlined(configuration: configuration, tint: tint) }

    private struct Outlined: View {
        let configuration: Configuration
        let tint: Color
        @State private var hovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(hovered ? 0.15 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(hovered ? 0.5 : 0.25), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

extension VoidView {
    /// The Void listing `notes`, for offscreen renders.
    static func preview(notes: [Note], now: Date) -> NSView {
        let host = NSHostingView(rootView: VoidView(model: VoidModel(notes: notes, now: now), close: {}))
        host.appearance = NSAppearance(named: .darkAqua)
        return host
    }
}

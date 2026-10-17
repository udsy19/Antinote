import AppKit
import Combine
import JotterCore
import SwiftUI

/// The Void: deleted notes waiting to be recovered or erased.
@MainActor
final class VoidWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "The Void"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 380, height: 320)
            w.contentViewController = NSHostingController(rootView: VoidView(model: VoidModel()))
            w.setFrameAutosaveName("JotterVoidWindow")
            if !w.setFrameUsingName("JotterVoidWindow") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class VoidModel: ObservableObject {
    @Published var notes: [Note] = []
    private var cancellable: AnyCancellable?

    init() {
        reload()
        cancellable = Services.store?.changes.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
    }

    func reload() { notes = Services.store?.void ?? [] }

    func recover(_ note: Note) {
        Services.store.restoreFromVoid(note.id)
        HUD.show("Note recovered", symbol: "arrow.uturn.backward.circle.fill")
    }

    func open(_ note: Note) {
        Services.store.restoreFromVoid(note.id)
        Services.windows?.show(noteID: note.id)
    }

    func delete(_ note: Note) {
        guard Alerts.confirm("Delete from The Void?", info: "There is no recovery beyond The Void.",
                             confirmTitle: "Delete", destructive: true) else { return }
        Services.store.deletePermanently(note.id)
    }

    func emptyVoid() {
        guard !notes.isEmpty else { HUD.show("The Void is already empty", symbol: "tornado"); return }
        let count = notes.count
        guard Alerts.confirm("Empty The Void?",
                             info: "\(count) note\(count == 1 ? "" : "s") will be erased. There is no recovery beyond The Void.",
                             confirmTitle: "Empty The Void", destructive: true) else { return }
        for note in notes { Services.store.deletePermanently(note.id) }
        HUD.show("The Void is empty", symbol: "tornado")
    }

    var retentionText: String {
        let days = Defaults[.voidRetentionDays]
        return days == 0 ? "Notes stay in The Void until you erase them."
            : "Notes are erased \(days) day\(days == 1 ? "" : "s") after they drift in."
    }
}

private struct VoidView: View {
    @ObservedObject var model: VoidModel

    var body: some View {
        VStack(spacing: 0) {
            if model.notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tornado").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                    Text("Deleted notes will drift here").font(.title3.weight(.medium))
                    Text("Recover them, or erase them permanently.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.notes) { note in
                    VoidRow(note: note, model: model)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text(model.retentionText).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Empty The Void…", role: .destructive) { model.emptyVoid() }
                    .disabled(model.notes.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

private struct VoidRow: View {
    let note: Note
    let model: VoidModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview).lineLimit(2).font(.body)
                if let deleted = note.deletedAt {
                    Text("Deleted \(deleted.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Recover") { model.recover(note) }
            Button { model.delete(note) } label: { Image(systemName: "trash") }
                .help("Delete permanently")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(note) }
        .contextMenu {
            Button("Recover") { model.recover(note) }
            Button("Recover and Open") { model.open(note) }
            Divider()
            Button("Delete Permanently…", role: .destructive) { model.delete(note) }
        }
    }

    private var preview: String {
        let lines = note.content.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? "Empty note" : lines.prefix(2).joined(separator: " · ")
    }
}

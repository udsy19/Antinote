import AppKit
import JotterCore

/// A parsed `jotter://` URL.
public enum URLCommand: Equatable, Sendable {
    case new(String)
    case append(String)
    case overwrite(String)
    case show(UUID)
    case promote(UUID)
    case togglePin
    case palette
    case search(String)
    case void

    public static let scheme = "jotter"

    /// `jotter://new?text=…`, `append?text=…`, `overwrite?text=…`, `show?id=…`, `promote?id=…`, `togglepin`,
    /// `palette`, `search?q=…`, `void`. Command names are case-insensitive; `jotter:new?…` works too.
    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let name = (components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .lowercased()
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] where params[item.name.lowercased()] == nil {
            params[item.name.lowercased()] = item.value ?? ""
        }
        let text = params["text"] ?? ""
        let id = params["id"].flatMap(UUID.init(uuidString:))
        switch name {
        case "new", "create", "createnote": return .new(text)
        case "append": return .append(text)
        case "overwrite": return .overwrite(text)
        case "show", "open": return id.map(URLCommand.show)
        case "promote": return id.map(URLCommand.promote)
        case "togglepin", "pin": return .togglePin
        case "palette": return .palette
        case "search": return .search(params["q"] ?? params["query"] ?? "")
        case "void": return .void
        default: return nil
        }
    }

    /// `existing` with `text` appended on its own line.
    public static func appending(_ text: String, to existing: String) -> String {
        guard !existing.isEmpty else { return text }
        return existing.hasSuffix("\n") ? existing + text : existing + "\n" + text
    }
}

/// Receives `kAEGetURL` Apple events and runs them through `Services`. URLs that arrive before the services exist
/// are queued and replayed once the app has finished launching.
@MainActor
final class URLSchemeHandler: NSObject {
    private var pending: [URL] = []
    private var launched = false

    func install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handle(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.launched = true
                let queued = self.pending
                self.pending = []
                queued.forEach(self.open)
            }
        }
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        if launched && Services.store != nil && Services.windows != nil { open(url) } else { pending.append(url) }
    }

    func open(_ url: URL) {
        guard let command = URLCommand.parse(url) else {
            HUD.show("Unknown Jotter link", symbol: "exclamationmark.triangle.fill"); return
        }
        let store = Services.store!, windows = Services.windows!
        switch command {
        case let .new(text):
            windows.show(noteID: store.create(content: text).id)
        case let .append(text):
            guard let id = windows.currentNoteID, var note = store.note(id) else {
                windows.show(noteID: store.create(content: text).id); return
            }
            note.content = URLCommand.appending(text, to: note.content)
            store.update(note)
            windows.show(noteID: id)
        case let .overwrite(text):
            guard let id = windows.currentNoteID, var note = store.note(id) else {
                windows.show(noteID: store.create(content: text).id); return
            }
            note.content = text
            store.update(note)
            windows.show(noteID: id)
        case let .show(id):
            if store.note(id) != nil { windows.show(noteID: id) } else { windows.showMain() }
        case let .promote(id):
            guard let note = store.note(id) else { windows.showMain(); return }
            if note.slot != nil { HUD.show("Slotted notes cannot be promoted", symbol: "exclamationmark.triangle.fill") }
            else { store.promoteToFront(id) }
            windows.show(noteID: id)
        case .togglePin:
            Defaults[.pinOnTop].toggle()
        case .palette:
            Services.panels.showCommandPalette()
        case let .search(query):
            (Services.panels as? ToolsPanels)?.showSearch(query: query) ?? Services.panels.showSearch()
        case .void:
            Services.panels.showVoid()
        }
    }
}

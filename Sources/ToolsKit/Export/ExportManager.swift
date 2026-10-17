import AppKit
import JotterCore
import UniformTypeIdentifiers

/// Sends notes to other apps and files.
@MainActor
public final class ExportManager: ExportServicing {
    /// URL-scheme exports longer than this are refused (apps truncate or reject huge URLs).
    static let maxURLLength = 60_000

    public init() {}

    public func export(_ note: Note, to destination: ExportDestination) {
        let omit = Defaults[.omitKeywordInExport]
        let body = ExportText.body(note.content, omitKeyword: omit)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            HUD.show("No note to export", kind: .warning); return
        }
        let title = Defaults[.exportFirstLineAsTitle] ? ExportText.title(of: body) : ExportText.datedTitle(note.modified)
        let markdown = ExportText.markdownDocument(note.content, omitKeyword: omit)
        switch destination {
        case .appleNotes:
            exportToAppleNotes(body)
        case .obsidian:
            var query = ["name=" + ExportText.queryValue(ExportText.baseName(title)),
                         "content=" + ExportText.queryValue(markdown)]
            let vault = Defaults[.obsidianVault].trimmingCharacters(in: .whitespaces)
            if !vault.isEmpty { query.insert("vault=" + ExportText.queryValue(vault), at: 0) }
            openURL("obsidian://new?" + query.joined(separator: "&"), app: "Obsidian")
        case .bear:
            openURL("bear://x-callback-url/create?text=" + ExportText.queryValue(markdown), app: "Bear")
        case .plainText:
            save(body, name: ExportText.fileName(title, ext: "txt"), type: .plainText)
        case .markdown:
            save(markdown, name: ExportText.fileName(title, ext: "md"), type: UTType(filenameExtension: "md") ?? .plainText)
        case .pdf:
            exportPDF(body, name: ExportText.fileName(title, ext: "pdf"))
        case .customURL:
            let date = ISO8601DateFormatter().string(from: note.modified)
            guard let url = ExportText.customURL(template: Defaults[.customURLTemplate], title: title, content: body, date: date)
            else { Alerts.error("Add the custom URL in Settings → Export first."); return }
            openURL(url, app: "The app for this URL scheme")
        }
    }

    public func exportAll(to folder: URL) throws {
        let omit = Defaults[.omitKeywordInExport]
        var used = Set<String>()
        for note in Services.store.deck + Services.store.archived {
            let text = ExportText.markdownDocument(note.content, omitKeyword: omit)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let base = ExportText.baseName(ExportText.title(of: text))
            var name = base + ".md", n = 2
            while used.contains(name.lowercased()) { name = "\(base) \(n).md"; n += 1 }
            used.insert(name.lowercased())
            let url = folder.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.creationDate: note.created, .modificationDate: note.modified],
                                                   ofItemAtPath: url.path)
        }
        // Full-fidelity copy (slots, links, dates) that Jotter can import again.
        try Services.store.exportJSON().write(to: folder.appendingPathComponent("Jotter Notes.json"), options: .atomic)
    }

    /// Asks for a folder, then writes every note as Markdown.
    public func exportAllInteractively() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for your notes (one Markdown file per note)."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try exportAll(to: folder)
            HUD.show("Notes exported", kind: .success)
        } catch {
            Alerts.error("Couldn't export the notes.", error)
        }
    }

    /// Prints a note with the editor font.
    public func print(_ note: Note) {
        let body = ExportText.body(note.content, omitKeyword: Defaults[.omitKeywordInExport])
        guard !body.isEmpty else { HUD.show("No note to print", kind: .warning); return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        let op = printOperation(body, info: info)
        op.showsPrintPanel = true
        op.run()
    }

    // MARK: Destinations

    private func exportToAppleNotes(_ body: String) {
        let html = ExportText.html(body).replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Notes\" to make new note with properties {body:\"\(html)\"}"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { HUD.show("Sent to Apple Notes", kind: .success); return }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 {
            Alerts.error("Jotter isn't allowed to control Notes.",
                         AutomationDenied())
        } else {
            Alerts.error("Couldn't send the note to Apple Notes: \(error[NSAppleScript.errorMessage] as? String ?? "error \(code)")")
        }
    }

    private struct AutomationDenied: LocalizedError {
        var errorDescription: String? {
            "Open System Settings → Privacy & Security → Automation, find Jotter and turn on Notes, then export again."
        }
    }

    private func openURL(_ string: String, app: String) {
        guard string.count <= Self.maxURLLength else {
            Alerts.error("Note is too long. Export to txt, md, or copy/paste."); return
        }
        guard let url = URL(string: string), NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            Alerts.error("\(app) doesn't seem to be installed."); return
        }
        NSWorkspace.shared.open(url)
    }

    private func save(_ text: String, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            HUD.show("Note exported", kind: .success)
        } catch {
            Alerts.error("Couldn't save the note.", error)
        }
    }

    private func exportPDF(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.pdf]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = printOperation(text, info: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        if op.run() { HUD.show("PDF exported", kind: .success) } else { Alerts.error("Failed to export PDF") }
    }

    /// A paginated text view in the editor font, black on white.
    private func printOperation(_ text: String, info: NSPrintInfo) -> NSPrintOperation {
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let font = Typography.font()
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Typography.lineHeight(for: font)
        style.maximumLineHeight = style.minimumLineHeight
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.black, .paragraphStyle: style,
        ]))
        view.backgroundColor = .white
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = ExportText.title(of: text)
        return op
    }
}

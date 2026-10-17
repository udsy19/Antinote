import AppKit
import Combine
import JotterCore

@MainActor
public final class JotterEditorFactory: EditorFactory {
    public init() {}
    public func makeEditor() -> NoteEditing { JotterEditor() }
}

/// The plain-text note editor: styling, lists, inline results, short links, code, paste/OCR, AutoPaste,
/// extension commands, copy rules, Vim mode and autosave. See docs/specs/editorkit.md.
@MainActor
public final class JotterEditor: NSObject, NoteEditing, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    public let view: NSView = NSView()
    public private(set) var note: Note?
    public var onAnalysis: ((NoteAnalysis) -> Void)?

    let textView: EditorTextView
    private let storage = NSTextStorage()
    private let scrollView = NSScrollView()
    private let undo = UndoManager()
    private let modeLabel = PillLabel(fontSize: 10, weight: .semibold, monospaced: true)
    private let pill = PillView()
    private let dropOverlay = DropOverlayView()
    private let linkTip = LinkTipView()
    private let completion = CompletionPanel()
    private let autoPaste = AutoPasteMonitor()
    let vim = VimEngine()

    private(set) var links: [TrackedLink] = []
    private var allLinksExpanded = false
    /// Links (absolute ranges) added by the edit in progress; merged in after existing links are adjusted.
    private var pendingInsertedLinks: [TrackedLink]?
    /// > 0 while the editor makes its own edits (they skip the short-link guard).
    private var programmaticEdits = 0
    private var isLoading = false
    private var isNormalizing = false
    private var applyingVim = false
    private var saveWork: DispatchWorkItem?
    /// Container width the inline results were last placed for (re-placed when it changes).
    private var placedWidth: CGFloat = 0
    /// Baseline positions within a line fragment, per font and line height.
    private var baselineCache: [String: CGFloat] = [:]
    private(set) var analysis = NoteAnalysis.plain
    private var mode: NoteMode = .plain
    /// Code ranges (whole fenced blocks, or the body of a code note) for "paste as-is".
    private var codeRanges: [NSRange] = []
    private var cancellables: Set<AnyCancellable> = []
    private var storeSubscription: AnyCancellable?

    public override init() {
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        super.init()
        configureTextView()
        configureLayout()
        observeSettings()
        applyAppearance()
    }

    private func configureTextView() {
        textView.editor = self
        textView.delegate = self
        storage.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 44, height: 28)
    }

    private func configureLayout() {
        scrollView.documentView = textView
        // The note runs under the floating title bar; the editor's own insets place the first line.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = ThinScroller()
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.findBarPosition = .belowContent
        dropOverlay.isHidden = true
        modeLabel.isHidden = true
        linkTip.isHidden = true
        for v in [scrollView, modeLabel, pill, dropOverlay] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        view.addSubview(linkTip, positioned: .below, relativeTo: dropOverlay)   // placed by frame
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            modeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            modeLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -PillView.bottomInset),
            pill.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            dropOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dropOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dropOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            dropOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeSettings() {
        let keys: [Defaults.Keys] = [.fontName, .textSize, .doubleFontSize, .lineSpacing, .paperType, .paperOpacity, .forceRTL, .lightTheme,
                                     .darkTheme, .vimMode, .detectLinks, .allowTextReplacements]
        let names = Set(keys.map(\.name))
        Defaults.changes.filter { names.contains($0) }.receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyAppearance() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Theme.didChange).receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyAppearance() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.save() } }
            .store(in: &cancellables)
        // Keep the text view (and its paper) at least as tall as the visible area.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: scrollView.contentView)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.visibleAreaChanged() } }
            .store(in: &cancellables)
        completion.onAccept = { [weak self] item in self?.acceptCompletion(item) }
        autoPaste.onNewString = { [weak self] s in self?.appendAutoPaste(s) }
    }

    /// Keeps the text view at least as tall as the visible area; re-places inline results after a width change.
    private func visibleAreaChanged() {
        textView.setFrameSize(textView.frame.size)
        if abs((textView.textContainer?.size.width ?? 0) - placedWidth) > 0.5 { restyle() }
    }

    // MARK: - NoteEditing

    public func load(_ note: Note) {
        save()
        stopAutoPaste(announce: false)
        completion.hide()
        isLoading = true
        self.note = note
        links = []
        allLinksExpanded = false
        // "List updated to the new checkbox format.": list notes get their markers on load.
        var content = note.content
        if NoteMode.detect(firstLine: EditorLogic.Lines.ranges(content as NSString).first.map { (content as NSString).substring(with: $0) } ?? "").mode == .list,
           !note.isReadOnly {
            content = EditorLogic.Lists.normalizedListNote(TextState(content)).text
        }
        textView.string = content
        links = EditorLogic.Links.locate(note.links, in: content)
        undo.removeAllActions()
        textView.isEditable = !note.isReadOnly
        isLoading = false
        refresh()
        let end = NSRange(location: (content as NSString).length, length: 0)
        textView.setSelectedRange(end)
        textView.scrollRangeToVisible(end)
        vim.selectionChanged(end, text: textView.string)
        updateModeLabel()
        subscribeToStore()
        if content != note.content { scheduleSave() }
    }

    public func focus() { textView.window?.makeFirstResponder(textView) }

    public func insert(_ text: String) {
        guard textView.isEditable, !text.isEmpty else { return }
        let sel = textView.selectedRange()
        replace(sel, with: text, selection: NSRange(location: sel.location + (text as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    public func perform(_ command: EditorCommand) {
        let editable = textView.isEditable
        switch command {
        case .toggleCheckbox:
            guard editable else { return }
            let st = state, lines = EditorLogic.Lines.covered(st.ns, st.selection)
            if lines.count == 1, case .checkbox? = ListLine.parse(st.ns.substring(with: EditorLogic.Lines.range(st.ns, at: st.selection.location)))?.kind {
                apply(EditorLogic.Lists.check(st, line: lines.lowerBound, behavior: Defaults[.checkedItemBehavior]), action: "Toggle Checklist Item")
            } else {
                apply(EditorLogic.Lists.toggle(st), action: "Toggle Checklist Item")
            }
        case .cycleListStyle: if editable { apply(EditorLogic.Lists.cycle(state), action: "Change List Style") }
        case .indent: if editable { apply(EditorLogic.Lists.indent(state, outdent: false), action: "Indent") }
        case .outdent: if editable { apply(EditorLogic.Lists.indent(state, outdent: true), action: "Outdent") }
        case .moveLineUp, .moveLineDown:
            if editable, let st = EditorLogic.Lines.move(state, up: command == .moveLineUp) { apply(st, action: "Move Line") }
        case .duplicateLineUp, .duplicateLineDown:
            if editable { apply(EditorLogic.Lines.duplicate(state, up: command == .duplicateLineUp), action: "Duplicate Line") }
        case .strikethrough:
            if editable, let st = EditorLogic.Lines.strikethrough(state) { apply(st, action: "Strikethrough") }
        case .find: textFinder(.showFindInterface)
        case .findAndReplace: textFinder(.showReplaceInterface)
        case .findNext: textFinder(.nextMatch)
        case .findPrevious: textFinder(.previousMatch)
        case .increaseTextSize: stepTextSize(1)
        case .decreaseTextSize: stepTextSize(-1)
        case .resetTextSize: Defaults.reset(.textSize); Defaults.reset(.doubleFontSize)
        case .copyAll: copySelection(cut: false, wholeNote: true)
        case .selectLine:
            let st = state
            textView.setSelectedRange(EditorLogic.Lines.block(st.ns, EditorLogic.Lines.covered(st.ns, st.selection)))
        case .expandAllLinks: if editable { toggleAllLinks() }
        case .showExtensionAutocomplete:
            guard editable, Services.extensions != nil else { return }
            if completionToken() == nil { insert("::") }
            updateCompletion()
        }
    }

    /// ⌘+ / ⌘− step through the size presets.
    private func stepTextSize(_ delta: Int) {
        let all = TextSize.allCases
        let i = all.firstIndex(of: Defaults[.textSize]) ?? 2
        Defaults[.textSize] = all[min(max(i + delta, 0), all.count - 1)]
    }

    private func textFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    // MARK: - Editing primitives

    private var state: TextState { TextState(textView.string, textView.selectedRange()) }

    /// Replaces `range` as one undoable edit made by the editor. `newLinks` use absolute ranges in the new text.
    private func replace(_ range: NSRange, with string: String, links newLinks: [TrackedLink] = [],
                         selection: NSRange? = nil, action: String? = nil, breakCoalescing: Bool = true) {
        let old = textView.selectedRange()
        programmaticEdits += 1
        defer { programmaticEdits -= 1 }
        if breakCoalescing { textView.breakUndoCoalescing() }
        pendingInsertedLinks = newLinks
        guard textView.shouldChangeText(in: range, replacementString: string) else { pendingInsertedLinks = nil; return }
        storage.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        if let action { undo.setActionName(action) }
        let length = (textView.string as NSString).length
        var sel = selection ?? {
            let delta = (string as NSString).length - range.length
            var s = old
            if s.location >= NSMaxRange(range) { s.location += delta } else if s.location > range.location { s.location = range.location + (string as NSString).length; s.length = 0 }
            return s
        }()
        sel.location = min(sel.location, length)
        sel.length = min(sel.length, length - sel.location)
        textView.setSelectedRange(sel)
    }

    /// Applies a whole-text transform as its minimal replacement.
    private func apply(_ st: TextState, action: String?, breakCoalescing: Bool = true) {
        let change = EditorLogic.minimalChange(from: textView.string, to: st.text)
        if change.range.length == 0 && change.replacement.isEmpty {
            textView.setSelectedRange(st.selection)
            return
        }
        replace(change.range, with: change.replacement, selection: st.selection, action: action, breakCoalescing: breakCoalescing)
    }

    // MARK: - Delegates

    public func undoManager(for view: NSTextView) -> UndoManager? { undo }

    public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
        guard let string, programmaticEdits == 0, !isLoading, !undo.isUndoing, !undo.isRedoing else { return true }
        switch EditorLogic.Links.check(range, against: links) {
        case .inside: toast("Cannot edit within shortened links. Expand before editing."); return false
        case .partial: toast("Cannot partially edit shortened links. Expand before editing."); return false
        case .allowed: break
        }
        if range.length == 0, string == " " || string == "\n" || string == "\t" { shrinkTypedURL(endingAt: range.location) }
        return true
    }

    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isLoading else { return }
        let text = textStorage.string
        let pre = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let replacement = (text as NSString).substring(with: editedRange)
        var adjusted = EditorLogic.Links.adjust(links, edited: pre, replacement: replacement, text: text)
        let lost = links.filter { l in !l.expanded && !adjusted.contains { $0.link == l.link } }
        if !lost.isEmpty { adjusted = EditorLogic.Links.locate(lost.map(\.link), in: text, existing: adjusted) }
        if let added = pendingInsertedLinks { adjusted += added; pendingInsertedLinks = nil }
        links = adjusted.sorted { $0.range.location < $1.range.location }
    }

    public func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }
        if !isNormalizing, NoteMode.detect(firstLine: firstLine).mode == .list {
            let normalized = EditorLogic.Lists.normalizedListNote(state)
            if normalized.text != textView.string {
                isNormalizing = true
                apply(normalized, action: nil, breakCoalescing: false)
                isNormalizing = false
                return   // the nested change already refreshed
            }
        }
        refresh()
        scheduleSave()
        updateCompletion()
    }

    /// The caret never stops inside a hidden checkbox/bullet marker (nil = keep `new`).
    func clampedCaret(from old: NSRange, to new: NSRange) -> NSRange? {
        guard new.length == 0, programmaticEdits == 0, !isLoading, !(Defaults[.vimMode] && vim.mode != .insert) else { return nil }
        guard let m = textView.model.markers.first(where: { new.location > $0.range.location && new.location < NSMaxRange($0.range) })
        else { return nil }
        let movingLeft = old.length == 0 && old.location == NSMaxRange(m.range)
        return NSRange(location: movingLeft ? m.range.location : NSMaxRange(m.range), length: 0)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        if Defaults[.vimMode], !applyingVim { vim.selectionChanged(textView.selectedRange(), text: textView.string) }
        updateModeLabel()
        guard programmaticEdits == 0, !isLoading else { return }
        collapseLinksAwayFromCaret()
        if completion.isVisible, completionToken() == nil { completion.hide() }
    }

    // MARK: - Analysis, styling, saving

    private var firstLine: String {
        let s = textView.string as NSString
        return s.substring(with: EditorLogic.Lines.range(s, at: 0))
    }

    private func refresh() {
        analyze()
        restyle()
    }

    private func analyze() {
        let text = textView.string
        if let analyzer = Services.analyzer {
            analysis = analyzer.analyze(text)
        } else {
            let d = NoteMode.detect(firstLine: firstLine)
            analysis = NoteAnalysis(mode: d.mode, arguments: d.arguments)
        }
        if analysis.mode != mode {
            mode = analysis.mode
            textView.isContinuousSpellCheckingEnabled = mode != .code
        }
        if mode != .autopaste, autoPaste.isRunning { stopAutoPaste(announce: false) }
        onAnalysis?(analysis)
    }

    private func restyle() {
        guard !textView.hasMarkedText(), let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        let s = textView.string as NSString
        let theme = Theme.current
        let font = Typography.font()
        let codeFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        let advance = ("m" as NSString).size(withAttributes: [.font: font]).width
        // List notes: tighter wrapped lines, extra space between items.
        let isList = mode == .list
        let lineHeight = isList ? font.pointSize * 1.35 : Typography.lineHeight(for: font)
        let rtl = Defaults[.forceRTL]
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        para.paragraphSpacing = isList ? font.pointSize * 0.65 : 0
        para.tabStops = []
        para.defaultTabInterval = advance * 4
        para.baseWritingDirection = rtl ? .rightToLeft : .natural
        let text = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight)
        let lines = EditorLogic.Lines.ranges(s)
        let hasKeyword = mode != .plain
        let full = NSRange(location: 0, length: s.length)

        // The text starts 44 pt in (scaled with the font) and, at the regular line pitch, the first line's
        // capitals sit ~37 pt down; list notes keep that inset, so their tighter first line sits a little higher.
        let baselineOffset = self.baselineOffset(font: font, lineHeight: lineHeight)
        let regularBaseline = self.baselineOffset(font: font, lineHeight: Typography.lineHeight(for: font))
        let inset = NSSize(width: Gutter.inset(font),
                           height: max(4, (27 + 10 * Gutter.scale(font) - regularBaseline + font.capHeight).rounded()))
        if textView.textContainerInset != inset { textView.textContainerInset = inset }

        var model = RenderModel()
        model.theme = theme
        model.paper = Defaults[.paperType]
        model.paperOpacity = Defaults[.paperOpacity]
        model.lineHeight = lineHeight
        model.baselineOffset = baselineOffset
        model.font = font
        model.rightToLeft = rtl
        model.autoPasting = autoPaste.isRunning

        // Code: the body of a code note, or ``` fenced blocks elsewhere.
        var code: [(range: NSRange, language: CodeLanguage, block: NSRange)] = []
        if mode == .code, lines.count > 1 {
            let body = NSRange(location: lines[1].location, length: s.length - lines[1].location)
            let lang = CodeLanguage(name: analysis.arguments) ?? CodeTokenizer.detect(s.substring(with: body))
            code.append((body, lang, body))
        } else {
            var open: (line: Int, lang: CodeLanguage?)?
            for (i, line) in lines.enumerated() {
                let t = s.substring(with: line).trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("```") else { continue }
                if let o = open {
                    let start = lines[o.line].location, inner = NSRange(location: NSMaxRange(lines[o.line]) + 1, length: 0)
                    let content = NSRange(location: inner.location, length: max(0, line.location - 1 - inner.location))
                    let lang = o.lang ?? CodeTokenizer.detect(s.substring(with: content))
                    code.append((content, lang, NSRange(location: start, length: NSMaxRange(line) - start)))
                    open = nil
                } else {
                    open = (i, CodeLanguage(name: String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        codeRanges = code.map(\.block)
        model.codeBlocks = mode == .code ? [] : codeRanges
        func inCode(_ r: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, r).length > 0 || NSLocationInRange(r.location, $0) } }
        func matches(_ regex: NSRegularExpression) -> [NSTextCheckingResult] {
            regex.matches(in: textView.string, range: full).filter { !inCode($0.range) }
        }

        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: text, .paragraphStyle: para], range: full)

        // First line: only the keyword is coloured; a timer command is coloured whole.
        if hasKeyword, let first = lines.first, first.length > 0 {
            let line = s.substring(with: first)
            let lead = line.prefix { $0.isWhitespace }.utf16.count
            let word = line.dropFirst(line.prefix { $0.isWhitespace }.count).prefix { !$0.isWhitespace && $0 != ":" }.utf16.count
            let range = mode == .timer ? first : NSRange(location: first.location + lead, length: word)
            storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.keyword(mode)), range: range)
        }

        // Markdown: headings, // comments, and emphasis with dimmed markers (not in math-like notes).
        let mathish: Set<NoteMode> = [.math, .sum, .average, .count]
        if mode != .code {
            let headingColors = [theme.accent1Main, theme.accent1Secondary, theme.accent1Tertiary]
            for m in matches(Self.headingRegex) where !(hasKeyword && m.range.location < NSMaxRange(lines[0])) {
                storage.addAttributes([.font: bold, .foregroundColor: NSColor(hex: headingColors[m.range(at: 1).length - 1])],
                                      range: m.range)
            }
            for m in matches(Self.commentRegex) { storage.addAttributes([.font: italic, .foregroundColor: light], range: m.range) }
            if !mathish.contains(mode) {
                let styles: [(NSRegularExpression, Int, [NSAttributedString.Key: Any])] = [
                    (Self.boldRegex, 2, [.font: bold]),
                    (Self.italicRegex, 1, [.font: italic]),
                    (Self.underlineRegex, 2, [.underlineStyle: NSUnderlineStyle.single.rawValue]),
                    (Self.strikeRegex, 2, [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: text]),
                ]
                for (regex, marker, attrs) in styles {
                    for m in matches(regex) {
                        storage.addAttributes(attrs, range: m.range(at: 1))
                        storage.addAttribute(.foregroundColor, value: light, range: NSRange(location: m.range.location, length: marker))
                        storage.addAttribute(.foregroundColor, value: light,
                                             range: NSRange(location: NSMaxRange(m.range) - marker, length: marker))
                    }
                }
                for m in matches(Self.inlineCodeRegex) {
                    storage.addAttribute(.font, value: codeFont, range: m.range)
                    model.inlineCode.append(m.range)
                }
            }
        }

        // List markers: hidden and zero-width, drawn in the left gutter; wrapped lines align with the item text.
        for (i, line) in lines.enumerated() where !(hasKeyword && i == 0) && line.length > 0 && !inCode(line) {
            guard let item = ListLine.parse(s.substring(with: line)) else { continue }
            let isCheckbox: Bool = { if case .checkbox = item.kind { return true }; return false }()
            if mathish.contains(mode) && !isCheckbox { continue }
            let markerStart = line.location + (item.indent as NSString).length
            let marker = NSRange(location: markerStart, length: min(item.markerLength, NSMaxRange(line) - markerStart))
            for offset in 0..<marker.length {
                let r = NSRange(location: marker.location + offset, length: 1)
                let width = s.substring(with: r).size(withAttributes: [.font: font]).width
                storage.addAttributes([.foregroundColor: NSColor.clear, .kern: -width], range: r)
            }
            let kind: RenderModel.Marker
            switch item.kind {
            case .checkbox(let checked):
                kind = .checkbox(checked: checked)
                if checked, NSMaxRange(marker) < NSMaxRange(line) {
                    let content = NSRange(location: NSMaxRange(marker), length: NSMaxRange(line) - NSMaxRange(marker))
                    storage.addAttributes([.foregroundColor: light, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .strikethroughColor: light], range: content)
                }
            case .bullet: kind = .bullet
            case .numbered(let n): kind = .number("\(n).")
            }
            model.markers.append((marker, kind, i))
            let hang = para.mutableCopy() as! NSMutableParagraphStyle
            hang.headIndent = item.indent.reduce(0) { $0 + ($1 == "\t" ? advance * 4 : advance) }
            storage.addAttribute(.paragraphStyle, value: hang, range: line)
        }

        // Math variables: the defined name in accent 1 secondary, its colon in accent 2, later uses in accent 1 tertiary.
        if mode == .math, !analysis.definitions.isEmpty {
            let names = Set(analysis.definitions.values)
            var definedNames: [NSRange] = []
            for (index, _) in analysis.definitions where lines.indices.contains(index) {
                let line = s.substring(with: lines[index])
                guard let sep = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }
                let lead = line.prefix { $0.isWhitespace }.utf16.count
                let nameEnd = line[..<sep].trimmingCharacters(in: .whitespaces).utf16.count + lead
                let name = NSRange(location: lines[index].location + lead, length: nameEnd - lead)
                definedNames.append(name)
                storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.accent1Secondary), range: name)
                if line[sep] == ":" {
                    storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.accent2Main),
                                         range: NSRange(location: lines[index].location + line[..<sep].utf16.count, length: 1))
                }
            }
            let pattern = names.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            if let uses = try? NSRegularExpression(pattern: "(?<![\\w])(?:\(pattern))(?![\\w])", options: [.caseInsensitive]) {
                let body = NSRange(location: NSMaxRange(lines[0]), length: s.length - NSMaxRange(lines[0]))
                for m in uses.matches(in: textView.string, range: body)
                where !definedNames.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                    storage.addAttribute(.foregroundColor, value: NSColor(hex: theme.accent1Tertiary), range: m.range)
                }
            }
        }

        let tokenColors: [CodeToken.Kind: NSColor] = [.keyword: NSColor(hex: theme.accent2Main), .string: NSColor(hex: theme.accent3Main),
                                                      .comment: light, .number: NSColor(hex: theme.accent4Main)]
        for block in code {
            storage.addAttribute(.font, value: codeFont, range: block.block)
            for t in CodeTokenizer.tokens(s.substring(with: block.range), language: block.language) {
                let r = NSRange(location: block.range.location + t.range.location, length: t.range.length)
                storage.addAttribute(.foregroundColor, value: tokenColors[t.kind] ?? text, range: r)
            }
        }

        // Links: a dotted underline; shortened links in their own colour.
        let dotted = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
        let underline: [NSAttributedString.Key: Any] = [.underlineStyle: dotted, .underlineColor: NSColor(hex: theme.typeSuperlight)]
        if Defaults[.detectLinks] {
            for r in EditorLogic.Links.urls(in: textView.string) where !inCode(r) {
                storage.addAttributes(underline.merging([.foregroundColor: NSColor(hex: theme.typeSubtle)]) { $1 }, range: r)
            }
        }
        for l in links where NSMaxRange(l.range) <= s.length {
            let color = NSColor(hex: l.expanded ? theme.typeSubtle : theme.typeSubtlePlus)
            storage.addAttributes(underline.merging([.foregroundColor: color]) { $1 }, range: l.range)
        }
        storage.endEditing()

        // Results follow their line; one that doesn't fit gets a reserved row below it.
        lm.ensureLayout(for: tc)
        placedWidth = tc.size.width
        let edges = (start: inset.width, end: inset.width + tc.size.width)
        var wrapped: [NSRange] = []
        for a in analysis.annotations where lines.indices.contains(a.line) {
            let line = lines[a.line]
            let display = EditorLogic.Annotations.display(a.text, after: s.substring(with: line))
            let width = display.size(withAttributes: [.font: font]).width
            var wraps = false
            if tc.size.width > 4 * advance {
                let end = textView.lineEnd(line).x
                wraps = EditorLogic.Annotations.place(lineEnd: end, width: width, textStart: edges.start, textEnd: edges.end,
                                                      rightToLeft: rtl).wraps
            }
            if wraps { wrapped.append(line) }
            model.annotations.append((line, display, wraps, a))
        }
        if !wrapped.isEmpty {
            storage.beginEditing()
            for line in wrapped {
                let style = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle ?? para)
                    .mutableCopy() as! NSMutableParagraphStyle
                style.paragraphSpacing += lineHeight
                storage.addAttribute(.paragraphStyle, value: style, range: line)
            }
            storage.endEditing()
        }

        switch mode {
        case .sum: model.summary = analysis.summary.map { ($0, theme.accent3Secondary) }
        case .average: model.summary = analysis.summary.map { ($0, theme.accent4Secondary) }
        case .count: model.summary = analysis.summary.map { ($0, theme.accent5Secondary) }
        default: break
        }
        textView.typingAttributes = [.font: font, .foregroundColor: text, .paragraphStyle: para]
        model.blockCaret = Defaults[.vimMode] && vim.mode != .insert
        textView.model = model
    }

    /// Where TextKit puts the baseline inside a fixed-height line fragment (measured on a scratch layout).
    private func baselineOffset(font: NSFont, lineHeight: CGFloat) -> CGFloat {
        let key = "\(font.fontName)/\(font.pointSize)/\(lineHeight)"
        if let offset = baselineCache[key] { return offset }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let storage = NSTextStorage(string: "X", attributes: [.font: font, .paragraphStyle: paragraph])
        let lm = NSLayoutManager(), tc = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        storage.addLayoutManager(lm)
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        let offset = lm.location(forGlyphAt: 0).y
        baselineCache[key] = offset
        return offset
    }

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,3})[ \t]+\S.*$"#, options: .anchorsMatchLines)
    private static let commentRegex = try! NSRegularExpression(pattern: #"^[ \t]*//.*$"#, options: .anchorsMatchLines)
    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(?=\S)([^\n]+?)(?<=\S)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![*\w])"#)
    private static let underlineRegex = try! NSRegularExpression(pattern: #"__(?=\S)([^\n]+?)(?<=\S)__"#)
    private static let strikeRegex = try! NSRegularExpression(pattern: #"~~(?=\S)([^\n]+?)~~"#)
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)

    func applyAppearance() {
        let theme = Theme.current
        let background = NSColor(hex: theme.background)
        textView.insertionPointColor = NSColor(hex: theme.accent1Main)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.typeHighlight)]
        textView.backgroundColor = background
        scrollView.backgroundColor = background
        (scrollView.verticalScroller as? ThinScroller)?.knobColor = NSColor(hex: theme.typeHighlight)
        textView.isAutomaticTextReplacementEnabled = Defaults[.allowTextReplacements]
        modeLabel.fill = NSColor(hex: theme.typeHyperLight)
        modeLabel.label.textColor = NSColor(hex: theme.typeLight)
        dropOverlay.theme = theme
        if !Defaults[.vimMode] { vim.reset() }
        updateModeLabel()
        restyle()
    }

    private func updateModeLabel() {
        let on = Defaults[.vimMode]
        modeLabel.isHidden = !on
        modeLabel.label.stringValue = vim.status
        let block = on && vim.mode != .insert
        if textView.model.blockCaret != block { textView.model.blockCaret = block }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The note as stored: expanded links collapsed back to their short text.
    private var persistedContent: String { EditorLogic.Links.collapsed(textView.string, links: links) }

    public func flush() { save() }

    private func save() {
        saveWork?.cancel()
        saveWork = nil
        guard var n = note, let store = Services.store else { return }
        var seen = Set<ShortLink>()
        let shortLinks = links.map(\.link).filter { seen.insert($0).inserted }
        let content = persistedContent
        guard content != n.content || shortLinks != n.links else { return }
        n.content = content
        n.links = shortLinks
        note = n
        store.update(n)
    }

    private func subscribeToStore() {
        guard storeSubscription == nil, let store = Services.store else { return }
        storeSubscription = store.changes.receive(on: RunLoop.main).sink { [weak self] change in
            MainActor.assumeIsolated { self?.storeChanged(change) }
        }
    }

    /// Sync or another window changed the current note: reload it unless a local edit is pending.
    private func storeChanged(_ change: NoteStoreChange) {
        guard case .updated(let id) = change, id == note?.id, saveWork == nil, let fresh = Services.store?.note(id) else { return }
        guard fresh.content != persistedContent || fresh.isReadOnly != note?.isReadOnly else { note = fresh; return }
        let sel = textView.selectedRange()
        load(fresh)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(sel.location, length), length: 0))
    }

    // MARK: - Keys

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if completion.isVisible {
            switch event.keyCode {
            case 126: completion.move(-1); return true
            case 125: completion.move(1); return true
            case 48, 36, 76: acceptCompletion(nil); return true
            case 53: completion.hide(); return true
            default: break
            }
        }
        if event.keyCode == 53, autoPaste.isRunning { stopAutoPaste(announce: true); return true }
        guard Defaults[.vimMode], !mods.contains(.command) else { return false }
        guard let key = vimKey(event, mods: mods) else {
            // Normal/Visual: navigation keys work, anything else that would type is swallowed.
            let navigation: Set<NSEvent.SpecialKey> = [.upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown, .home, .end]
            return vim.mode != .insert && !(event.specialKey.map(navigation.contains) ?? false)
        }
        guard vim.mode != .insert || key == "<Esc>" else { return false }
        let out = vim.handle(key, text: textView.string, selection: textView.selectedRange())
        guard out.handled else { return false }
        applyVim(out)
        return true
    }

    private func vimKey(_ event: NSEvent, mods: NSEvent.ModifierFlags) -> String? {
        switch event.keyCode {
        case 53: return "<Esc>"
        case 36, 76: return "<CR>"
        case 51: return "<BS>"
        default: break
        }
        if mods == .control { return event.charactersIgnoringModifiers == "r" ? "<C-r>" : nil }
        guard event.specialKey == nil, let c = event.characters, c.count == 1 else { return nil }
        return c
    }

    private func applyVim(_ out: VimEngine.Output) {
        applyingVim = true
        defer { applyingVim = false; updateModeLabel() }
        if out.undo || out.redo {
            if out.undo { undo.undo() } else { undo.redo() }
            let sel = textView.selectedRange()
            textView.setSelectedRange(NSRange(location: sel.location, length: 0))
            vim.selectionChanged(textView.selectedRange(), text: textView.string)
            return
        }
        if let text = out.text {
            guard textView.isEditable else { vim.reset(); return }
            let change = EditorLogic.minimalChange(from: textView.string, to: text)
            if EditorLogic.Links.check(change.range, against: links) != .allowed {
                toast("Cannot edit within shortened links. Expand before editing.")
                vim.reset()
                return
            }
            replace(change.range, with: change.replacement, selection: out.selection, action: "Edit")
        } else {
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(out.selection.location, length),
                                              length: min(out.selection.length, max(0, length - out.selection.location))))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == .command, event.keyCode == 36 || event.keyCode == 76 { openLinkAtCaret(); return true }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "m", textView.isEditable {
            perform(.cycleListStyle); return true
        }
        return false
    }

    func handleReturn() -> Bool {
        if completion.isVisible { acceptCompletion(nil); return true }
        guard textView.isEditable else { return false }
        if runExtensionCommandOnCurrentLine() { return true }
        let st = state
        if mode == .autopaste, EditorLogic.Lines.index(st.ns, at: st.selection.location) == 0, !autoPaste.isRunning {
            startAutoPaste()
        }
        if mode != .code, Defaults[.listContinuity], let next = EditorLogic.Lists.continued(st) {
            apply(next, action: "Typing")
            return true
        }
        if Defaults[.keepIndentOnReturn] {
            let line = EditorLogic.Lines.range(st.ns, at: st.selection.location)
            let beforeCaret = st.ns.substring(with: NSRange(location: line.location, length: st.selection.location - line.location))
            let indent = String(beforeCaret.prefix { $0 == " " || $0 == "\t" })
            if !indent.isEmpty { textView.insertText("\n" + indent, replacementRange: st.selection); return true }
        }
        return false
    }

    func handleTab(backwards: Bool) -> Bool {
        if completion.isVisible, !backwards { acceptCompletion(nil); return true }
        guard textView.isEditable else { return false }
        let st = state
        let lines = EditorLogic.Lines.covered(st.ns, st.selection)
        let isList = ListLine.parse(st.ns.substring(with: EditorLogic.Lines.range(st.ns, at: st.selection.location))) != nil
        guard backwards || lines.count > 1 || (isList && mode != .code) else { return false }
        apply(EditorLogic.Lists.indent(st, outdent: backwards), action: backwards ? "Outdent" : "Indent")
        return true
    }

    /// Backspace right after a list marker removes the marker (list notes: joins with the previous item).
    func handleDeleteBackward() -> Bool {
        let st = state
        guard textView.isEditable, st.selection.length == 0, mode != .code else { return false }
        let line = EditorLogic.Lines.range(st.ns, at: st.selection.location)
        guard let item = ListLine.parse(st.ns.substring(with: line)) else { return false }
        let markerStart = line.location + (item.indent as NSString).length
        guard st.selection.location == markerStart + item.markerLength else { return false }
        if mode == .list {
            let index = EditorLogic.Lines.index(st.ns, at: line.location)
            if index > 1 {
                let join = NSRange(location: line.location - 1, length: st.selection.location - line.location + 1)
                replace(join, with: "", selection: NSRange(location: line.location - 1, length: 0), action: "Delete")
            } else if item.content.isEmpty {
                replace(line, with: "", selection: NSRange(location: line.location, length: 0), action: "Delete")
            }
            return true
        }
        let removed = TextState(st.ns.replacingCharacters(in: NSRange(location: markerStart, length: item.markerLength), with: ""),
                                NSRange(location: markerStart, length: 0))
        apply(EditorLogic.Lists.renumbered(removed), action: "Delete")
        return true
    }

    // MARK: - Mouse

    func handleClick(at p: NSPoint, event: NSEvent) -> Bool {
        if let hit = textView.annotationHits.first(where: { $0.rect.contains(p) }) {
            if event.modifierFlags.contains(.option) {
                if Defaults[.preventEditingAnswers] || !textView.isEditable {
                    toast("Calculated results can't be edited.")
                } else {
                    replace(NSRange(location: NSMaxRange(hit.line), length: 0), with: " " + hit.annotation.text, action: "Insert Result")
                }
            } else {
                writeToPasteboard(hit.annotation.text.trimmingCharacters(in: CharacterSet(charactersIn: "= ")))
                toast("Copied to clipboard")
            }
            return true
        }
        if textView.isEditable, let i = textView.checkbox(at: p) {
            let line = textView.model.markers[i].line
            apply(EditorLogic.Lists.check(state, line: line, behavior: Defaults[.checkedItemBehavior]), action: "Toggle Checklist Item")
            return true
        }
        guard let index = characterIndex(at: p) else { return false }
        if let i = links.firstIndex(where: { !$0.expanded && NSLocationInRange(index, $0.range) }) {
            if event.modifierFlags.contains(.command) || !textView.isEditable {
                open(links[i].link.url)
            } else {
                let link = links[i]
                setLink(at: link.range, expanded: true)
                textView.setSelectedRange(NSRange(location: link.range.location + (link.link.url as NSString).length, length: 0))
            }
            return true
        }
        if event.modifierFlags.contains(.command),
           let r = EditorLogic.Links.urls(in: textView.string).first(where: { NSLocationInRange(index, $0) }) {
            open((textView.string as NSString).substring(with: r))
            return true
        }
        return false
    }

    /// The character under `p` (nil over empty space).
    private func characterIndex(at p: NSPoint) -> Int? {
        guard let lm = textView.layoutManager, let tc = textView.textContainer, storage.length > 0 else { return nil }
        let origin = textView.textContainerOrigin
        let glyph = lm.glyphIndex(for: NSPoint(x: p.x - origin.x, y: p.y - origin.y), in: tc)
        let index = lm.characterIndexForGlyph(at: glyph)
        return textView.rect(for: NSRange(location: index, length: 1)).contains(p) ? index : nil
    }

    // MARK: - Links

    /// Hovering a link shows its full address and what clicks do, just below the link and ending at the pointer.
    func hover(at p: NSPoint?) {
        guard let p, let index = characterIndex(at: p) else { linkTip.isHidden = true; return }
        let hint: String, range: NSRange, url: String
        if let l = links.first(where: { NSLocationInRange(index, $0.range) }) {
            (url, range) = (l.link.url, l.range)
            hint = l.expanded ? "⌘+Click to open." : "⌘+Click to open | Click to expand."
        } else if Defaults[.detectLinks], let r = EditorLogic.Links.urls(in: textView.string).first(where: { NSLocationInRange(index, $0) }) {
            (url, range) = ((textView.string as NSString).substring(with: r), r)
            hint = "⌘+Click to open."
        } else {
            linkTip.isHidden = true
            return
        }
        let below = textView.convert(NSPoint(x: p.x, y: textView.rect(for: range).maxY + 4), to: view)
        linkTip.show(url + "\n" + hint, theme: Theme.current, endingAt: below, in: view.bounds)
    }

    private func open(_ string: String) {
        if let url = URL(string: string.trimmingCharacters(in: .whitespaces)) { NSWorkspace.shared.open(url) }
    }

    /// ⌘Return: opens the short link or raw URL under the caret.
    private func openLinkAtCaret() {
        let loc = textView.selectedRange().location
        if let l = links.first(where: { loc >= $0.range.location && loc <= NSMaxRange($0.range) }) { return open(l.link.url) }
        if let r = EditorLogic.Links.urls(in: textView.string).first(where: { loc >= $0.location && loc <= NSMaxRange($0) }) {
            open((textView.string as NSString).substring(with: r))
        }
    }

    /// Expands (shows the URL) or collapses (re-shortens) the link occupying `range`.
    private func setLink(at range: NSRange, expanded: Bool) {
        guard let i = links.firstIndex(where: { $0.range == range }) else { return }
        var link = links[i]
        if !expanded {
            let url = link.link.url.trimmingCharacters(in: .whitespaces)
            guard url.lowercased().hasPrefix("http"), url.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                links.remove(at: i); restyle(); return
            }
            link.link = ShortLink(url: url, short: Services.analyzer?.shorten(url: url) ?? link.link.short)
        }
        link.expanded = expanded
        let display = link.displayed
        link.range = NSRange(location: range.location, length: (display as NSString).length)
        links.remove(at: i)
        replace(range, with: display, links: [link], action: expanded ? "Expand Link" : "Shorten Link")
    }

    private func collapseLinksAwayFromCaret() {
        guard !allLinksExpanded else { return }
        let sel = textView.selectedRange()
        let away = links.filter { $0.expanded && !(sel.location >= $0.range.location && sel.location <= NSMaxRange($0.range)) }
        guard !away.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sel = self.textView.selectedRange()
            for l in self.links.reversed() where l.expanded && !(sel.location >= l.range.location && sel.location <= NSMaxRange(l.range)) {
                self.setLink(at: l.range, expanded: false)
            }
        }
    }

    private func toggleAllLinks() {
        allLinksExpanded.toggle()
        undo.beginUndoGrouping()
        for l in links.reversed() where l.expanded != allLinksExpanded { setLink(at: l.range, expanded: allLinksExpanded) }
        undo.endUndoGrouping()
        undo.setActionName(allLinksExpanded ? "Expand Links" : "Shorten Links")
    }

    /// A URL typed and followed by space/Return becomes a short link (after the keystroke lands).
    private func shrinkTypedURL(endingAt location: Int) {
        guard Defaults[.shortenLinks], mode != .code, let analyzer = Services.analyzer,
              let r = EditorLogic.Links.url(endingAt: location, in: textView.string),
              !codeRanges.contains(where: { NSLocationInRange(r.location, $0) }),
              !links.contains(where: { NSIntersectionRange($0.range, r).length > 0 }) else { return }
        let url = (textView.string as NSString).substring(with: r)
        DispatchQueue.main.async { [weak self] in
            guard let self, NSMaxRange(r) <= (self.textView.string as NSString).length,
                  (self.textView.string as NSString).substring(with: r) == url else { return }
            let short = analyzer.shorten(url: url)
            guard !short.isEmpty, short != url else { return }
            let link = TrackedLink(link: ShortLink(url: url, short: short), range: NSRange(location: r.location, length: (short as NSString).length))
            self.replace(r, with: short, links: [link], action: "Shorten Link")
        }
    }

    // MARK: - Clipboard

    private func writeToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        autoPaste.ignoreCurrentContents()
    }

    func copySelection(cut: Bool, wholeNote forceWhole: Bool = false) {
        let s = textView.string as NSString
        var sel = textView.selectedRange()
        var whole = forceWhole
        if forceWhole {
            sel = NSRange(location: 0, length: s.length)
        } else if sel.length == 0 {
            if cut {
                guard Defaults[.cutLineWhenNoSelection], textView.isEditable else { return }
                let line = EditorLogic.Lines.range(s, at: sel.location)
                sel = NSRange(location: line.location, length: min(line.length + 1, s.length - line.location))
                if NSMaxRange(sel) == s.length, line.location > 0, line.length + 1 > sel.length {
                    sel = NSRange(location: line.location - 1, length: line.length + 1)   // last line: take the newline before it
                }
            } else {
                guard Defaults[.copyWholeNoteWhenNoSelection] else { return }
                sel = NSRange(location: 0, length: s.length); whole = true
            }
        }
        guard sel.length > 0 else { return }
        if cut, EditorLogic.Links.check(sel, against: links) != .allowed {
            return toast("Cannot partially edit shortened links. Expand before editing.")
        }
        let raw = EditorLogic.Links.expanded(textView.string, range: sel, links: links)
        var options = EditorLogic.Copy.Options.current
        if mode == .code { options.uncheck = false; options.skipMarkers = false }
        let filtered = EditorLogic.Copy.filter(raw, wholeNote: whole && sel.location == 0, options: options)
        writeToPasteboard(filtered.text)
        if cut {
            replace(sel, with: "", selection: NSRange(location: sel.location, length: 0), action: "Cut")
        } else if let notice = filtered.notices.first {
            toast(notice)
        } else if whole {
            toast("Copied all to clipboard")
        }
    }

    func paste(from pb: NSPasteboard) {
        guard textView.isEditable else { return }
        let string = pb.string(forType: .string)
        if string == nil || pb.types?.contains(.fileURL) == true, OCR.hasImage(pb) { return recognizeImage(from: pb) }
        guard let string else { return }
        let sel = textView.selectedRange()
        guard EditorLogic.Links.check(sel, against: links) == .allowed else {
            return toast("Cannot partially edit shortened links. Expand before editing.")
        }
        var text = string.replacingOccurrences(of: "\r\n", with: "\n")
        var newLinks: [TrackedLink] = []
        if mode == .code || codeRanges.contains(where: { NSLocationInRange(sel.location, $0) }) {
            if text.contains("\n") { toast(mode == .code ? "Pasted as-is in code note" : "Pasted as-is in code block") }
        } else {
            if Defaults[.cleanPaste], let analyzer = Services.analyzer {
                let cleaned = analyzer.cleanPaste(text)
                if cleaned != text { text = cleaned; toast("Pasted content optimized.") }
            }
            if Defaults[.shortenLinks], let analyzer = Services.analyzer {
                let shrunk = EditorLogic.Links.shrink(text) { analyzer.shorten(url: $0) }
                text = shrunk.text
                newLinks = shrunk.links.map { var l = $0; l.range.location += sel.location; return l }
            }
        }
        replace(sel, with: text, links: newLinks, selection: NSRange(location: sel.location + (text as NSString).length, length: 0),
                action: "Paste")
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // MARK: - OCR

    func recognizeImage(from pb: NSPasteboard) {
        guard let image = OCR.image(from: pb) else { return toast("Unable to load image. Try copy/pasting.") }
        toast("Capturing text…")
        OCR.recognize(image) { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else { return self.toast("No text found in the image.") }
            self.insert(text)
            self.toast("Extracted text.", kind: .success)
        }
    }

    func setDropOverlay(visible: Bool) { dropOverlay.isHidden = !visible }

    // MARK: - AutoPaste

    private func startAutoPaste() {
        autoPaste.start()
        toast("AutoPasting clipboard...", kind: .success)
        refresh()
    }

    private func stopAutoPaste(announce: Bool) {
        guard autoPaste.isRunning else { return }
        autoPaste.stop()
        if announce { toast("AutoPaste stopped") }
        refresh()
    }

    private func appendAutoPaste(_ copied: String) {
        guard textView.isEditable else { return }
        var text = copied
        if Defaults[.cleanPaste], let analyzer = Services.analyzer { text = analyzer.cleanPaste(text) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let s = textView.string as NSString
        let prefix = s.length == 0 || s.hasSuffix("\n") ? "" : "\n"
        replace(NSRange(location: s.length, length: 0), with: prefix + text, action: "AutoPaste")
        textView.scrollRangeToVisible(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    // MARK: - Extensions

    /// `::prefix` immediately before the caret.
    private func completionToken() -> (range: NSRange, prefix: String)? {
        let st = state
        guard st.selection.length == 0 else { return nil }
        let line = EditorLogic.Lines.range(st.ns, at: st.selection.location)
        let before = st.ns.substring(with: NSRange(location: line.location, length: st.selection.location - line.location))
        guard let m = Self.tokenRegex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) else { return nil }
        return (NSRange(location: line.location + m.range.location, length: m.range.length),
                (before as NSString).substring(with: m.range(at: 1)))
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: #"::([A-Za-z0-9_-]*)$"#)
    private static let invocationRegex = try! NSRegularExpression(pattern: #"::[A-Za-z_][A-Za-z0-9_-]*\([^()\n]*\)"#)

    private func updateCompletion() {
        guard textView.isEditable, Defaults[.extensionsEnabled], let ext = Services.extensions,
              let token = completionToken() else { return completion.hide() }
        let caret = textView.firstRect(forCharacterRange: NSRange(location: NSMaxRange(token.range), length: 0), actualRange: nil)
        completion.show(ext.complete(token.prefix), below: caret, parent: textView.window)
    }

    private func acceptCompletion(_ chosen: ExtensionCommandInfo?) {
        let items = completion.items
        let item = chosen ?? (items.indices.contains(completion.selectedIndex) ? items[completion.selectedIndex] : nil)
        completion.hide()
        guard let item, let token = completionToken() else { return }
        let takesArguments = item.signature.contains("(") && !item.signature.contains("()")
        let insertion = "::" + item.name + "()"
        let caret = token.range.location + (insertion as NSString).length - (takesArguments ? 1 : 0)
        replace(token.range, with: insertion, selection: NSRange(location: caret, length: 0), action: "Insert Command")
    }

    /// Return on a line with `::name(args)` (caret after it) runs the command.
    private func runExtensionCommandOnCurrentLine() -> Bool {
        guard Defaults[.extensionsEnabled], let ext = Services.extensions else { return false }
        let st = state
        let line = EditorLogic.Lines.range(st.ns, at: st.selection.location)
        let lineText = st.ns.substring(with: line)
        let caret = st.selection.location - line.location
        guard let m = Self.invocationRegex.matches(in: lineText, range: NSRange(location: 0, length: line.length))
            .last(where: { NSMaxRange($0.range) <= caret }) else { return false }
        let invocation = (lineText as NSString).substring(with: m.range)
        let location = line.location + m.range.location
        ext.run(invocation: invocation, line: lineText, note: textView.string) { [weak self] edit in
            Task { @MainActor in self?.applyExtensionEdit(edit, invocation: invocation, near: location) }
        }
        return true
    }

    private func applyExtensionEdit(_ edit: ExtensionEdit, invocation: String, near location: Int) {
        let s = textView.string as NSString
        var found: NSRange?
        var from = 0
        while from < s.length {
            let r = s.range(of: invocation, range: NSRange(location: from, length: s.length - from))
            guard r.location != NSNotFound else { break }
            if found == nil || abs(r.location - location) < abs(found!.location - location) { found = r }
            from = NSMaxRange(r)
        }
        let editable = textView.isEditable
        switch edit {
        case .insert(let text):
            if editable, let r = found {
                replace(r, with: text, selection: NSRange(location: r.location + (text as NSString).length, length: 0), action: "Run Command")
            }
        case .replaceLine(let text):
            if editable {
                let line = EditorLogic.Lines.range(s, at: found?.location ?? min(location, s.length))
                replace(line, with: text, selection: NSRange(location: line.location + (text as NSString).length, length: 0), action: "Run Command")
            }
        case .replaceAll(let text):
            if editable { replace(NSRange(location: 0, length: s.length), with: text, action: "Run Command") }
        case .openURL(let url):
            NSWorkspace.shared.open(url)
            if editable, let r = found { replace(r, with: "", action: "Run Command") }
        case .message(let message): toast(message, kind: .success)
        case .failure(let message): toast(message, kind: .error)
        }
    }

    // MARK: - Toast

    /// Shows a message pill at the bottom of the note.
    func toast(_ message: String, kind: PillKind = .info) {
        pill.show(message, kind: kind, theme: Theme.current)
    }
}

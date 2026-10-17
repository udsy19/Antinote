import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key + modifier combination.
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue, device-independent bits only

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }
    public init(key: Int, modifiers: NSEvent.ModifierFlags) { self.init(keyCode: UInt32(key), modifiers: modifiers) }
    public init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    /// The menu-item key equivalent for this shortcut: its character, or the function-key character for arrows,
    /// Return, Tab, Delete, Escape and F-keys ("" when there is none).
    public var keyEquivalent: String {
        if let special = Shortcut.functionKeys.first(where: { $0.code == Int(keyCode) }) {
            return String(Character(UnicodeScalar(special.character)!))
        }
        let name = Shortcut.keyName(keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }

    /// The shortcut for a menu item's key equivalent and modifiers: the key that types `keyEquivalent` on the
    /// current layout. Nil when no key does.
    public init?(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        guard let scalar = keyEquivalent.unicodeScalars.first, keyEquivalent.unicodeScalars.count == 1 else { return nil }
        if let special = Shortcut.functionKeys.first(where: { $0.character == Int(scalar.value) }) {
            self.init(key: special.code, modifiers: modifiers); return
        }
        let wanted = keyEquivalent.lowercased()
        guard let code = (0..<128).first(where: { !Shortcut.isSpecial($0) && Shortcut.keyName(UInt32($0)).lowercased() == wanted })
        else { return nil }
        self.init(key: code, modifiers: modifiers)
    }

    /// Keys whose key equivalent is a function-key character rather than what they type.
    private static let functionKeys: [(code: Int, character: Int)] = [
        (kVK_UpArrow, NSUpArrowFunctionKey), (kVK_DownArrow, NSDownArrowFunctionKey),
        (kVK_LeftArrow, NSLeftArrowFunctionKey), (kVK_RightArrow, NSRightArrowFunctionKey),
        (kVK_Return, 0x0D), (kVK_Tab, 0x09), (kVK_Delete, 0x08), (kVK_Escape, 0x1B), (kVK_Space, 0x20),
        (kVK_ForwardDelete, NSDeleteFunctionKey), (kVK_Home, NSHomeFunctionKey), (kVK_End, NSEndFunctionKey),
        (kVK_PageUp, NSPageUpFunctionKey), (kVK_PageDown, NSPageDownFunctionKey),
        (kVK_F1, NSF1FunctionKey), (kVK_F2, NSF2FunctionKey), (kVK_F3, NSF3FunctionKey), (kVK_F4, NSF4FunctionKey),
        (kVK_F5, NSF5FunctionKey), (kVK_F6, NSF6FunctionKey), (kVK_F7, NSF7FunctionKey), (kVK_F8, NSF8FunctionKey),
        (kVK_F9, NSF9FunctionKey), (kVK_F10, NSF10FunctionKey), (kVK_F11, NSF11FunctionKey), (kVK_F12, NSF12FunctionKey),
    ]
    private static func isSpecial(_ code: Int) -> Bool { functionKeys.contains { $0.code == code } }


    public static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
            kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let s = special[Int(code)] { return s }
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &len, &chars)
        }
        guard status == noErr, len > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }
}



/// Global hotkeys via Carbon `RegisterEventHotKey` (works without Accessibility permission).
@MainActor
public final class HotkeyCenter {
    public static let shared = HotkeyCenter()

    private struct Registration { let ref: EventHotKeyRef; let handler: () -> Void }
    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    /// While a shortcut recorder is focused, hotkeys are suspended so they can be re-recorded.
    public var isSuspended = false

    private init() {}

    /// Registers a hotkey and returns a token for `unregister`. Returns nil if the combo is taken.
    @discardableResult
    public func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_4354) /* 'SHCT' */, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    public func unregister(_ token: UInt32) {
        if let r = registrations.removeValue(forKey: token) { UnregisterEventHotKey(r.ref) }
    }

    public func unregisterAll() {
        for (_, r) in registrations { UnregisterEventHotKey(r.ref) }
        registrations.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard !isSuspended, let r = registrations[id] else { return }
        r.handler()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - Recorder control

/// Click-to-record shortcut field. Esc cancels, ⌫ clears.
public final class ShortcutRecorderView: NSView {
    public var shortcut: Shortcut? { didSet { needsDisplay = true } }
    public var onChange: ((Shortcut?) -> Void)?
    /// Return a reason string to reject a shortcut (e.g. already used).
    public var validator: ((Shortcut) -> String?)?

    private var recording = false { didSet { needsDisplay = true; HotkeyCenter.shared.isSuspended = recording } }
    private var monitor: Any?

    public override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if recording { stop(); return }
        // Clear button region (right 20pt) when a shortcut exists.
        let p = convert(event.locationInWindow, from: nil)
        if shortcut != nil, p.x > bounds.maxX - 22 { set(nil); return }
        window?.makeFirstResponder(self)
        start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self, self.recording else { return e }
            if e.type == .flagsChanged { self.needsDisplay = true; return nil }
            if e.keyCode == UInt16(kVK_Escape) && e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stop(); return nil
            }
            if e.keyCode == UInt16(kVK_Delete) && e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                self.set(nil); self.stop(); return nil
            }
            guard let s = Shortcut(event: e) else { return nil }
            let fnKey = (UInt32(kVK_F1)...UInt32(kVK_F20)).contains(s.keyCode)
            if s.modifiers.intersection([.command, .option, .control]).isEmpty && !fnKey {
                NSSound.beep(); return nil  // require a real modifier
            }
            if let reason = self.validator?(s) {
                let alert = NSAlert(); alert.messageText = reason; alert.runModal()
                return nil
            }
            self.set(s); self.stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func set(_ s: Shortcut?) { shortcut = s; onChange?(s) }

    public override func resignFirstResponder() -> Bool { stop(); return true }

    public override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text: String
        let color: NSColor
        if recording {
            let mods = Shortcut(keyCode: 0, modifiers: NSEvent.modifierFlags).displayString.dropLast()
            text = mods.isEmpty ? "Type shortcut…" : String(mods)
            color = .secondaryLabelColor
        } else if let shortcut {
            text = shortcut.displayString; color = .labelColor
        } else {
            text = "Record Shortcut"; color = .tertiaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)

        if shortcut != nil && !recording {
            let x = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
            x?.draw(in: NSRect(x: bounds.maxX - 19, y: (bounds.height - 13) / 2, width: 13, height: 13))
        }
    }
}

/// SwiftUI wrapper around ShortcutRecorderView bound to an optional shortcut.
public struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    let validator: ((Shortcut) -> String?)?
    public init(shortcut: Binding<Shortcut?>, validator: ((Shortcut) -> String?)? = nil) {
        _shortcut = shortcut; self.validator = validator
    }
    public func makeNSView(context: Context) -> ShortcutRecorderView {
        let v = ShortcutRecorderView()
        v.shortcut = shortcut
        v.validator = validator
        v.onChange = { shortcut = $0 }
        return v
    }
    public func updateNSView(_ v: ShortcutRecorderView, context: Context) { v.shortcut = shortcut }
}

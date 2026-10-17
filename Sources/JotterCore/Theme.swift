import AppKit

/// A colour theme. Jotter picks one theme for light mode and one for dark mode (Settings → Appearance).
/// Custom themes are JSON files with these fields in `JotterPaths.themes`.
public struct Theme: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isDark: Bool
    public var background: String      // hex, e.g. "#F5F3EE"
    public var text: String
    public var secondaryText: String
    public var accent: String          // cursor, selection tint, checkboxes
    public var link: String
    public var result: String          // math results / summaries
    public var error: String
    public var paperLines: String      // ruled / grid / dot colour

    public init(id: String, name: String, isDark: Bool, background: String, text: String, secondaryText: String,
                accent: String, link: String, result: String, error: String, paperLines: String) {
        self.id = id; self.name = name; self.isDark = isDark; self.background = background; self.text = text
        self.secondaryText = secondaryText; self.accent = accent; self.link = link; self.result = result
        self.error = error; self.paperLines = paperLines
    }

    public static let builtIn: [Theme] = [
        Theme(id: "paper", name: "Paper", isDark: false, background: "#F7F5F0", text: "#1C1B17", secondaryText: "#8A857A",
              accent: "#E5484D", link: "#2F6FDB", result: "#2F7A55", error: "#C93C3C", paperLines: "#E4DFD3"),
        Theme(id: "snow", name: "Snow", isDark: false, background: "#FFFFFF", text: "#16181D", secondaryText: "#8B909A",
              accent: "#2F6FDB", link: "#2F6FDB", result: "#0F8B72", error: "#D23F3F", paperLines: "#E9ECF0"),
        Theme(id: "sand", name: "Sand", isDark: false, background: "#F1E8D6", text: "#2B2418", secondaryText: "#8C7B5E",
              accent: "#B4572E", link: "#1F6F8B", result: "#5E7F2A", error: "#B8402E", paperLines: "#E0D3B8"),
        Theme(id: "mint", name: "Mint", isDark: false, background: "#EEF6F1", text: "#14261C", secondaryText: "#6F8C7B",
              accent: "#16875B", link: "#1D6FB8", result: "#16875B", error: "#C2453D", paperLines: "#D6E8DD"),
        Theme(id: "ink", name: "Ink", isDark: true, background: "#16150F", text: "#ECE8DE", secondaryText: "#8D887B",
              accent: "#FF6B6F", link: "#7FB2FF", result: "#7FD3A7", error: "#FF7A7A", paperLines: "#2A2820"),
        Theme(id: "graphite", name: "Graphite", isDark: true, background: "#1E1F22", text: "#E6E6E6", secondaryText: "#8E9096",
              accent: "#5EA1FF", link: "#5EA1FF", result: "#6CD3B0", error: "#FF6E6E", paperLines: "#2C2E32"),
        Theme(id: "midnight", name: "Midnight", isDark: true, background: "#0F1626", text: "#DDE5F2", secondaryText: "#7C8AA3",
              accent: "#F2B544", link: "#7EB6FF", result: "#8BD9A6", error: "#FF7B7B", paperLines: "#1C2538"),
        Theme(id: "forest", name: "Forest", isDark: true, background: "#13201A", text: "#E2ECE5", secondaryText: "#7E978A",
              accent: "#F0B35B", link: "#8CC4FF", result: "#9EDB9A", error: "#FF8A80", paperLines: "#20302A"),
    ]

    /// Built-ins plus valid custom theme files.
    public static var all: [Theme] {
        let dir = JotterPaths.themes
        let custom = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Theme.self, from: Data(contentsOf: $0)) }
        return builtIn + custom
    }

    /// The theme for the current appearance.
    @MainActor public static var current: Theme {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let id = dark ? Defaults[.darkTheme] : Defaults[.lightTheme]
        return all.first { $0.id == id } ?? builtIn.first { $0.isDark == dark }!
    }

    public static let didChange = Notification.Name("JotterThemeDidChange")
}

public extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA".
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xff) / 255, g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xff) / 255, a = hasAlpha ? CGFloat(v & 0xff) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

import AppKit

/// A colour theme. Jotter picks one theme for light mode and one for dark mode (Settings → Appearance).
///
/// Every colour in the UI comes from one of the 24 roles below. A theme file is a flat JSON object with these
/// keys plus `name` and `isDarkTheme` (the format theme makers export); custom themes live in `JotterPaths.themes`.
/// Keys a file leaves out fall back to the default light or dark theme.
public struct Theme: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var isDark: Bool

    /// Main background colour.
    public var background: String
    /// Inline code and code blocks.
    public var backgroundFade: String
    /// Primary text colour for content.
    public var typeMain: String
    /// Hyperlinks.
    public var typeSubtle: String
    /// Shortened hyperlinks.
    public var typeSubtlePlus: String
    /// Highlighted text background, scrollbar colour.
    public var typeHighlight: String
    /// Checked items, strikethrough text, search secondary, UI button click.
    public var typeLight: String
    /// The `/x` check tag, hyperlink underline.
    public var typeSuperlight: String
    /// UI button hover, search bar background.
    public var typeHyperLight: String
    /// Text in message pills and on other opposite backgrounds.
    public var typeReverse: String
    /// `math` keyword, caret, success pills, H1.
    public var accent1Main: String
    /// Variable assignment, H2.
    public var accent1Secondary: String
    /// Variable use, H3.
    public var accent1Tertiary: String
    /// `list` keyword, variable colon, timer time, checkbox hover.
    public var accent2Main: String
    /// Checked checkbox.
    public var accent2Secondary: String
    /// Pinned button, `sum` and `paste` keywords, math results.
    public var accent3Main: String
    /// Pinned button hover, sum total.
    public var accent3Secondary: String
    /// Warning pills, `avg`, `code` and `timer` keywords.
    public var accent4Main: String
    /// Average total.
    public var accent4Secondary: String
    /// Error pills, `count` keyword.
    public var accent5Main: String
    /// Count total.
    public var accent5Secondary: String
    /// Paper lines at "Subtle" opacity.
    public var gridSuperlight: String
    /// Paper lines at "Clear" opacity.
    public var gridClear: String
    /// Paper lines at "Bold" opacity.
    public var gridBold: String

    /// The file-name form of the name ("Neon Night" → "neon-night"); stored in `Defaults[.lightTheme]`.
    public var id: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    // MARK: Built-in themes

    public static let defaultLight = Theme(
        name: "Default Light", isDark: false,
        background: "#FFFFFF", backgroundFade: "#ECECEC", typeMain: "#473F37", typeSubtle: "#1F4F79",
        typeSubtlePlus: "#085EA3", typeHighlight: "#FFEBCF", typeLight: "#B2B2B2", typeSuperlight: "#DAD9D7",
        typeHyperLight: "#F2F2F2", typeReverse: "#FFFFFF", accent1Main: "#0B486B", accent1Secondary: "#0F8C8C",
        accent1Tertiary: "#417863", accent2Main: "#C14DFB", accent2Secondary: "#C14DFB", accent3Main: "#4DA425",
        accent3Secondary: "#3C7F1C", accent4Main: "#FF9E3C", accent4Secondary: "#CE741A", accent5Main: "#FF3B30",
        accent5Secondary: "#AC2E27", gridSuperlight: "#D9EEFA", gridClear: "#CBE1ED", gridBold: "#ABCBDD")

    public static let defaultDark = Theme(
        name: "Default Dark", isDark: true,
        background: "#2A2626", backgroundFade: "#302F2F", typeMain: "#EBE3DB", typeSubtle: "#B2E2EC",
        typeSubtlePlus: "#97DDD6", typeHighlight: "#746550", typeLight: "#7B7B7B", typeSuperlight: "#524D4D",
        typeHyperLight: "#343434", typeReverse: "#2A2626", accent1Main: "#58C2FF", accent1Secondary: "#0F8C8C",
        accent1Tertiary: "#73B0B0", accent2Main: "#DA93FE", accent2Secondary: "#C14DFB", accent3Main: "#39DB62",
        accent3Secondary: "#469521", accent4Main: "#FF9E3C", accent4Secondary: "#CE741A", accent5Main: "#FF7C75",
        accent5Secondary: "#C95B55", gridSuperlight: "#303336", gridClear: "#404448", gridBold: "#575B5F")

    /// The default pair plus the themes whose colours were sampled from published screenshots. Roles the
    /// screenshots don't show keep the default light/dark values.
    public static let builtIn: [Theme] = [
        defaultLight,
        defaultDark,
        derived("Neon Night", from: defaultDark) {
            $0.background = "#2B2626"; $0.typeMain = "#F3ECE5"; $0.accent1Main = "#69C4F4"
            $0.accent1Secondary = "#1C8989"; $0.accent1Tertiary = "#7EB2B2"; $0.accent2Main = "#DA98FB"
            $0.accent3Main = "#49D86C"; $0.gridSuperlight = "#302D31"
        },
        derived("Mecha", from: defaultLight) {
            $0.background = "#F6F6F6"; $0.typeMain = "#2C2C2C"; $0.accent1Main = "#175D97"
            $0.accent1Secondary = "#0C376C"; $0.accent1Tertiary = "#507BC0"; $0.accent2Main = "#DF4444"
            $0.accent3Main = "#F2BD5B"; $0.typeSubtlePlus = "#B81D3C"; $0.typeSuperlight = "#D2D3D3"
            $0.gridSuperlight = "#ECECEC"
        },
        derived("Masquerade", from: defaultDark) {
            $0.background = "#131313"; $0.typeMain = "#E0E0E0"; $0.accent1Main = "#AC1919"
            $0.typeHighlight = "#781414"; $0.gridSuperlight = "#272727"
        },
        derived("Cedar", from: defaultDark) {
            $0.background = "#181818"; $0.typeMain = "#F2F2F2"; $0.accent1Main = "#2C652C"
            $0.accent1Secondary = "#9CE3D7"; $0.accent1Tertiary = "#627F85"; $0.accent2Main = "#954322"
            $0.accent3Main = "#D74A4B"; $0.typeHighlight = "#ED735B"
        },
        derived("Arthouse", from: defaultDark) {
            $0.background = "#0E1511"; $0.typeMain = "#EBE0C5"; $0.accent1Main = "#587C6E"
            $0.accent2Main = "#712125"; $0.accent3Main = "#BA5F34"; $0.typeSuperlight = "#1E2A23"
            $0.gridClear = "#2B2F2D"
        },
        derived("Dune", from: defaultDark) {
            $0.background = "#0B0B28"; $0.typeMain = "#FBFCFF"; $0.accent1Main = "#F5E540"
            $0.accent1Secondary = "#CCBC33"; $0.accent1Tertiary = "#FBF687"; $0.accent2Main = "#A85BE3"
            $0.accent3Main = "#25C8CC"; $0.typeSubtlePlus = "#24B0B5"; $0.typeHighlight = "#993056"
            $0.gridSuperlight = "#1C1D34"
        },
        derived("Fern", from: defaultLight) {
            $0.background = "#F5FFF5"; $0.typeMain = "#282928"; $0.accent1Main = "#8D329C"
            $0.accent1Secondary = "#82518E"; $0.accent1Tertiary = "#4CB33E"; $0.accent2Main = "#56BB3D"
            $0.accent3Main = "#E5527C"; $0.typeHighlight = "#B2F82C"; $0.typeLight = "#8D948E"
            $0.gridClear = "#DFE3DE"
        },
        derived("Highland", from: defaultLight) {
            $0.background = "#F4F1EB"; $0.typeMain = "#362408"; $0.typeHighlight = "#F5BE9E"
            $0.gridSuperlight = "#EAE8E5"
        },
    ]

    /// A theme that starts from `base`; pill text (`typeReverse`) follows the new background.
    private static func derived(_ name: String, from base: Theme, _ edit: (inout Theme) -> Void) -> Theme {
        var theme = base
        theme.name = name
        edit(&theme)
        theme.typeReverse = theme.background
        return theme
    }

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
        return all.first { $0.id == id } ?? (dark ? defaultDark : defaultLight)
    }

    public static let didChange = Notification.Name("JotterThemeDidChange")

    // MARK: Paper and keywords

    /// The paper-line colour for an opacity setting.
    public func grid(_ opacity: PaperOpacity) -> String {
        switch opacity {
        case .subtle: gridSuperlight
        case .clear: gridClear
        case .bold: gridBold
        }
    }

    /// The colour of a first-line keyword.
    public func keyword(_ mode: NoteMode) -> String {
        switch mode {
        case .plain: typeMain
        case .math: accent1Main
        case .list: accent2Main
        case .sum, .autopaste: accent3Main
        case .average, .code, .timer: accent4Main
        case .count: accent5Main
        }
    }
}

// MARK: - Coding (theme-maker JSON)

extension Theme {
    private enum CodingKeys: String, CodingKey {
        case name, isDarkTheme
        case background, backgroundFade, typeMain, typeSubtle, typeSubtlePlus, typeHighlight, typeLight, typeSuperlight
        case typeHyperLight, typeReverse, accent1Main, accent1Secondary, accent1Tertiary, accent2Main, accent2Secondary
        case accent3Main, accent3Secondary, accent4Main, accent4Secondary, accent5Main, accent5Secondary
        case gridSuperlight, gridClear, gridBold
    }

    private static let roles: [(CodingKeys, WritableKeyPath<Theme, String>)] = [
        (.background, \.background), (.backgroundFade, \.backgroundFade), (.typeMain, \.typeMain),
        (.typeSubtle, \.typeSubtle), (.typeSubtlePlus, \.typeSubtlePlus), (.typeHighlight, \.typeHighlight),
        (.typeLight, \.typeLight), (.typeSuperlight, \.typeSuperlight), (.typeHyperLight, \.typeHyperLight),
        (.typeReverse, \.typeReverse), (.accent1Main, \.accent1Main), (.accent1Secondary, \.accent1Secondary),
        (.accent1Tertiary, \.accent1Tertiary), (.accent2Main, \.accent2Main), (.accent2Secondary, \.accent2Secondary),
        (.accent3Main, \.accent3Main), (.accent3Secondary, \.accent3Secondary), (.accent4Main, \.accent4Main),
        (.accent4Secondary, \.accent4Secondary), (.accent5Main, \.accent5Main), (.accent5Secondary, \.accent5Secondary),
        (.gridSuperlight, \.gridSuperlight), (.gridClear, \.gridClear), (.gridBold, \.gridBold),
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dark = try c.decodeIfPresent(Bool.self, forKey: .isDarkTheme) ?? false
        self = dark ? Self.defaultDark : Self.defaultLight
        name = try c.decode(String.self, forKey: .name)
        isDark = dark
        for (key, path) in Self.roles {
            if let hex = try c.decodeIfPresent(String.self, forKey: key) { self[keyPath: path] = hex }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(isDark, forKey: .isDarkTheme)
        for (key, path) in Self.roles { try c.encode(self[keyPath: path], forKey: key) }
    }
}

/// Editor type sizes and spacing (Settings → Appearance → Text).
public enum Typography {
    /// The editor's point size: the size preset, doubled by "Double font size".
    public static var pointSize: CGFloat {
        Defaults[.textSize].points * (Defaults[.doubleFontSize] ? 2 : 1)
    }

    /// The editor font (`Defaults[.fontName]`, Menlo by default) at `pointSize`.
    public static func font(size: CGFloat? = nil) -> NSFont {
        let size = size ?? pointSize
        return NSFont(name: Defaults[.fontName], size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Line pitch: 1.6 × the font size plus the user's extra spacing.
    public static func lineHeight(for font: NSFont) -> CGFloat {
        font.pointSize * 1.6 + CGFloat(Defaults[.lineSpacing])
    }
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

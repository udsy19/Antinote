import AppKit

/// A colour theme. Super Notes picks one theme for light mode and one for dark mode (Settings → Appearance).
///
/// Every colour in the UI comes from one of the 24 roles below. A theme file is a flat JSON object with these
/// keys plus `name` and `isDarkTheme` (the format theme makers export); custom themes live in `SuperNotesPaths.themes`.
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

    /// The file-name form of the name ("Default Dark" → "default-dark"); stored in `Defaults[.lightTheme]`.
    public var id: String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    // MARK: Built-in themes
    // Colour values are the reference app's built-in themes, role for role (alpha where it uses one).
    public static let defaultLight = Theme(
        name: "Default Light", isDark: false,
        background: "#FFFFFF", backgroundFade: "#ECECEC", typeMain: "#473F37", typeSubtle: "#1F4F79",
        typeSubtlePlus: "#085EA3", typeHighlight: "#FFEBCF", typeLight: "#B2B2B2", typeSuperlight: "#DAD9D7",
        typeHyperLight: "#F2F2F2", typeReverse: "#FFFFFF", accent1Main: "#0B486B", accent1Secondary: "#0F8C8C",
        accent1Tertiary: "#417863", accent2Main: "#C14DFB", accent2Secondary: "#C14DFB80", accent3Main: "#4DA425",
        accent3Secondary: "#3C7F1C", accent4Main: "#FF9E3C", accent4Secondary: "#CE741A", accent5Main: "#FF3B30",
        accent5Secondary: "#AC2E27", gridSuperlight: "#D9EEFACC", gridClear: "#CBE1EDCC", gridBold: "#ABCBDDCC")

    public static let defaultDark = Theme(
        name: "Default Dark", isDark: true,
        background: "#2A2626", backgroundFade: "#302F2F", typeMain: "#EBE3DB", typeSubtle: "#B2E2EC",
        typeSubtlePlus: "#97DDD6", typeHighlight: "#746550", typeLight: "#7B7B7B", typeSuperlight: "#524D4D",
        typeHyperLight: "#343434", typeReverse: "#2A2626", accent1Main: "#58C2FF", accent1Secondary: "#0F8C8C",
        accent1Tertiary: "#73B0B0", accent2Main: "#DA93FE", accent2Secondary: "#C14DFB80", accent3Main: "#39DB62",
        accent3Secondary: "#469521", accent4Main: "#FF9E3C", accent4Secondary: "#CE741A", accent5Main: "#FF7C75",
        accent5Secondary: "#C95B55", gridSuperlight: "#303336", gridClear: "#404448", gridBold: "#575B5F")

    /// The default pair plus twelve named themes, in the reference app's order.
    public static let builtIn: [Theme] = [
        defaultLight,
        defaultDark,
        Theme(
            name: "Mecha", isDark: false,
            background: "#F5F5F5", backgroundFade: "#E4E2E2", typeMain: "#323232", typeSubtle: "#3255AA",
            typeSubtlePlus: "#DC143C", typeHighlight: "#FFDF5A", typeLight: "#969696", typeSuperlight: "#C8C8C8",
            typeHyperLight: "#E6E6E6", typeReverse: "#FFFFFF", accent1Main: "#E664B4", accent1Secondary: "#E63C82",
            accent1Tertiary: "#4B82DC", accent2Main: "#FF3232", accent2Secondary: "#C8282880", accent3Main: "#FFBE46",
            accent3Secondary: "#D7A03C", accent4Main: "#646464", accent4Secondary: "#4B4B4B", accent5Main: "#2D78DC",
            accent5Secondary: "#2364C8", gridSuperlight: "#DCDCDC99", gridClear: "#BFBFBF99", gridBold: "#AAAAAA99"),
        Theme(
            name: "Masquerade", isDark: true,
            background: "#141414", backgroundFade: "#330404", typeMain: "#DCDCDC", typeSubtle: "#8C0A0A",
            typeSubtlePlus: "#A00A0A", typeHighlight: "#781414", typeLight: "#787878", typeSuperlight: "#B4B4B4",
            typeHyperLight: "#343434", typeReverse: "#000000", accent1Main: "#BA0B0B", accent1Secondary: "#FFE1BE",
            accent1Tertiary: "#85ABA3", accent2Main: "#3C3C3C", accent2Secondary: "#282828B2", accent3Main: "#DC5A1E",
            accent3Secondary: "#B43C14", accent4Main: "#FF4514", accent4Secondary: "#C83214", accent5Main: "#F01414",
            accent5Secondary: "#B40F0F", gridSuperlight: "#30333699", gridClear: "#464B5099", gridBold: "#636A7199"),
        Theme(
            name: "Meadow", isDark: false,
            background: "#FAF5EB", backgroundFade: "#E8DECD", typeMain: "#46321E", typeSubtle: "#5F8750",
            typeSubtlePlus: "#6E5541", typeHighlight: "#FFE6A0", typeLight: "#B4B4B4", typeSuperlight: "#DCDCDC",
            typeHyperLight: "#F0F0F0", typeReverse: "#FFFFFF", accent1Main: "#557D69", accent1Secondary: "#3C6450",
            accent1Tertiary: "#8CAA64", accent2Main: "#D2B48C", accent2Secondary: "#A08264", accent3Main: "#FFA59B",
            accent3Secondary: "#F0B4A0", accent4Main: "#C8A078", accent4Secondary: "#AA8264", accent5Main: "#78AA5A",
            accent5Secondary: "#649650", gridSuperlight: "#D7D7C999", gridClear: "#BBBBAF99", gridBold: "#AAAAA599"),
        Theme(
            name: "Cedar", isDark: true,
            background: "#03180C", backgroundFade: "#0D2819", typeMain: "#DCDCDC", typeSubtle: "#85620F",
            typeSubtlePlus: "#B18112", typeHighlight: "#F06446", typeLight: "#A0A0A0", typeSuperlight: "#C8C8C8",
            typeHyperLight: "#343434", typeReverse: "#000000", accent1Main: "#289A28", accent1Secondary: "#7FD4C7",
            accent1Tertiary: "#51767C", accent2Main: "#963C14", accent2Secondary: "#64280F", accent3Main: "#DC3C3C",
            accent3Secondary: "#B42828", accent4Main: "#827864", accent4Secondary: "#645A50", accent5Main: "#3C823C",
            accent5Secondary: "#2D642D", gridSuperlight: "#30333699", gridClear: "#464B5099", gridBold: "#636A7199"),
        Theme(
            name: "Arthouse", isDark: true,
            background: "#0F1612", backgroundFade: "#23332A", typeMain: "#E3D4B4", typeSubtle: "#BCB483",
            typeSubtlePlus: "#948B50", typeHighlight: "#493B59", typeLight: "#828282", typeSuperlight: "#505050",
            typeHyperLight: "#3C3C3C", typeReverse: "#000000", accent1Main: "#4D7967", accent1Secondary: "#2A5D4F",
            accent1Tertiary: "#465C8B", accent2Main: "#732023", accent2Secondary: "#BD657E", accent3Main: "#C55623",
            accent3Secondary: "#8C4626", accent4Main: "#CE9B35", accent4Secondary: "#917641", accent5Main: "#3CDCDC",
            accent5Secondary: "#28B4B4", gridSuperlight: "#32323299", gridClear: "#323232CC", gridBold: "#323232"),
        Theme(
            name: "Dune", isDark: true,
            background: "#0A0A28", backgroundFade: "#1B1943", typeMain: "#F0F0F0", typeSubtle: "#CEACF0",
            typeSubtlePlus: "#CEB4B4", typeHighlight: "#993055", typeLight: "#828282", typeSuperlight: "#505050",
            typeHyperLight: "#3C3C3C", typeReverse: "#000000", accent1Main: "#F5DC3C", accent1Secondary: "#C8B43C",
            accent1Tertiary: "#FFF05A", accent2Main: "#B450FF", accent2Secondary: "#8C3CC880", accent3Main: "#8CC8C8",
            accent3Secondary: "#8C9696", accent4Main: "#FF64C8", accent4Secondary: "#C83C8C", accent5Main: "#FF8C3C",
            accent5Secondary: "#C86428", gridSuperlight: "#3A3D4099", gridClear: "#3A3D40CC", gridBold: "#3A3D40"),
        Theme(
            name: "Armor", isDark: true,
            background: "#0A0A0F", backgroundFade: "#161822", typeMain: "#585858", typeSubtle: "#324664",
            typeSubtlePlus: "#283C5A", typeHighlight: "#1C4B63", typeLight: "#828282", typeSuperlight: "#505050",
            typeHyperLight: "#323232", typeReverse: "#000000", accent1Main: "#3C5082", accent1Secondary: "#3C5082B2",
            accent1Tertiary: "#506496", accent2Main: "#32C832", accent2Secondary: "#28962880", accent3Main: "#FF3C3C",
            accent3Secondary: "#B42828", accent4Main: "#FFC83C", accent4Secondary: "#C89628", accent5Main: "#B43CFF",
            accent5Secondary: "#8C28C8", gridSuperlight: "#3A3D4099", gridClear: "#3A3D40CC", gridBold: "#3A3D40"),
        Theme(
            name: "Stealth", isDark: true,
            background: "#292D2D", backgroundFade: "#374041", typeMain: "#CADEE8", typeSubtle: "#B5C2C8",
            typeSubtlePlus: "#94AAB5", typeHighlight: "#7BC290", typeLight: "#859393", typeSuperlight: "#5C6464",
            typeHyperLight: "#484E4E", typeReverse: "#000000", accent1Main: "#9BC6D3", accent1Secondary: "#5F9199",
            accent1Tertiary: "#395458", accent2Main: "#850E17", accent2Secondary: "#9C131D", accent3Main: "#63907C",
            accent3Secondary: "#A3C1B7", accent4Main: "#918070", accent4Secondary: "#66574B", accent5Main: "#F2F6F7",
            accent5Secondary: "#F2F6F7CC", gridSuperlight: "#4E515499", gridClear: "#4E5154CC", gridBold: "#4E5154"),
        Theme(
            name: "Fern", isDark: false,
            background: "#F5FFF5", backgroundFade: "#CEECCE", typeMain: "#323232", typeSubtle: "#821EA0",
            typeSubtlePlus: "#32C832", typeHighlight: "#B3F92C", typeLight: "#969696", typeSuperlight: "#C8C8C8",
            typeHyperLight: "#E6E6E6", typeReverse: "#FFFFFF", accent1Main: "#A032B4", accent1Secondary: "#78288CCC",
            accent1Tertiary: "#46BE37", accent2Main: "#50C832", accent2Secondary: "#3C8C28", accent3Main: "#FF5082",
            accent3Secondary: "#C83C64", accent4Main: "#6492E0", accent4Secondary: "#402559", accent5Main: "#FF3C3C",
            accent5Secondary: "#B42828", gridSuperlight: "#DCDCDC99", gridClear: "#DCDCDCCC", gridBold: "#DCDCDC"),
        Theme(
            name: "Highland", isDark: false,
            background: "#F3F1EB", backgroundFade: "#FFFFF0", typeMain: "#3C280A", typeSubtle: "#C85A14",
            typeSubtlePlus: "#8C460F", typeHighlight: "#F6BF9F", typeLight: "#828282", typeSuperlight: "#B4B4B4",
            typeHyperLight: "#E6E6E6", typeReverse: "#FFFFFF", accent1Main: "#FF7828", accent1Secondary: "#C85A1E",
            accent1Tertiary: "#FFA050", accent2Main: "#50AA50", accent2Secondary: "#3C823C80", accent3Main: "#7391A8",
            accent3Secondary: "#3B5A72", accent4Main: "#503214", accent4Secondary: "#3C1E0A", accent5Main: "#452423",
            accent5Secondary: "#7A3331", gridSuperlight: "#D2D2D299", gridClear: "#D2D2D2CC", gridBold: "#D2D2D2"),
        Theme(
            name: "Spice", isDark: false,
            background: "#E1D2B4", backgroundFade: "#EDDEBF", typeMain: "#9F865E", typeSubtle: "#85704F",
            typeSubtlePlus: "#78603A", typeHighlight: "#EFD978", typeLight: "#AE9C7E", typeSuperlight: "#B5A990",
            typeHyperLight: "#CDBFA4", typeReverse: "#FFFFFF", accent1Main: "#99501A", accent1Secondary: "#5D3112",
            accent1Tertiary: "#421F0E", accent2Main: "#2E92E5", accent2Secondary: "#2775B6", accent3Main: "#2A3735",
            accent3Secondary: "#5A7378", accent4Main: "#C8B478", accent4Secondary: "#AA9664", accent5Main: "#401F0D",
            accent5Secondary: "#642706", gridSuperlight: "#BEBEBE99", gridClear: "#BEBEBECC", gridBold: "#BEBEBE"),
        Theme(
            name: "Bubblegum", isDark: false,
            background: "#FFFFFF", backgroundFade: "#F4E7ED", typeMain: "#E876B2", typeSubtle: "#F1BFDC",
            typeSubtlePlus: "#D4A3BF", typeHighlight: "#CCE1D1", typeLight: "#9CCCE8", typeSuperlight: "#B1D3E7",
            typeHyperLight: "#C4D9E5", typeReverse: "#FFFFFF", accent1Main: "#84B0DD", accent1Secondary: "#A9BDE1",
            accent1Tertiary: "#B9CCD7", accent2Main: "#8EC58E", accent2Secondary: "#69A76980", accent3Main: "#A1BAA7",
            accent3Secondary: "#6B918A", accent4Main: "#E9BFC3", accent4Secondary: "#E78AB9", accent5Main: "#D29BCB",
            accent5Secondary: "#CC669A", gridSuperlight: "#DCDCDC99", gridClear: "#DCDCDCCC", gridBold: "#DCDCDC"),
    ]

    /// Built-ins plus valid custom theme files.
    public static var all: [Theme] {
        let dir = SuperNotesPaths.themes
        let custom = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Theme.self, from: Data(contentsOf: $0)) }
        return builtIn + custom
    }

    /// The theme for the current appearance (ephemeral notes and the window chrome).
    @MainActor public static var current: Theme { current(slotted: false) }

    /// The theme for the current appearance; slotted notes use their own pair when one is chosen.
    @MainActor public static func current(slotted: Bool) -> Theme {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let id = selectedID(dark: dark, slotted: slotted)
        return all.first { $0.id == id } ?? (dark ? defaultDark : defaultLight)
    }

    /// The chosen theme id: the slotted pair's when `slotted` and it is set, otherwise the ephemeral pair's.
    public static func selectedID(dark: Bool, slotted: Bool) -> String {
        let own = slotted ? Defaults[dark ? .slottedDarkTheme : .slottedLightTheme] : ""
        return own.isEmpty ? Defaults[dark ? .darkTheme : .lightTheme] : own
    }

    public static let didChange = Notification.Name("SuperNotesThemeDidChange")

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

    /// Line pitch: the font's natural height (ascender − descender + leading, rounded) times `multiple` (1.4 for
    /// notes), plus the user's extra spacing.
    public static func lineHeight(for font: NSFont, multiple: CGFloat = 1.4) -> CGFloat {
        lineHeight(natural: font.ascender - font.descender + font.leading, multiple: multiple) + CGFloat(Defaults[.lineSpacing])
    }

    /// `natural` rounded to whole points, times `multiple`.
    public static func lineHeight(natural: CGFloat, multiple: CGFloat) -> CGFloat {
        natural.rounded() * multiple
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

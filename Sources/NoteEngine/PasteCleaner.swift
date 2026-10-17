import Foundation
import JotterCore

/// Cleans pasted text per Settings → Copy & Paste.
public enum PasteCleaner {
    public struct Options: Sendable, Equatable {
        public var enabled = true
        public var removeMarkdown = true
        public var removeBullets = true
        public var removeNumbering = true
        public var removeLeadingWhitespace = true
        public var removeEmptyLines = false

        public init(enabled: Bool = true, removeMarkdown: Bool = true, removeBullets: Bool = true,
                    removeNumbering: Bool = true, removeLeadingWhitespace: Bool = true, removeEmptyLines: Bool = false) {
            self.enabled = enabled; self.removeMarkdown = removeMarkdown; self.removeBullets = removeBullets
            self.removeNumbering = removeNumbering; self.removeLeadingWhitespace = removeLeadingWhitespace
            self.removeEmptyLines = removeEmptyLines
        }

        public static var current: Options {
            Options(enabled: Defaults[.cleanPaste], removeMarkdown: Defaults[.pasteRemoveMarkdown],
                    removeBullets: Defaults[.pasteRemoveBullets], removeNumbering: Defaults[.pasteRemoveNumbering],
                    removeLeadingWhitespace: Defaults[.pasteRemoveLeadingWhitespace],
                    removeEmptyLines: Defaults[.pasteRemoveEmptyLines])
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
    private static let markdownRules: [(NSRegularExpression, String)] = [
        (regex(#"^[ \t]*(```|~~~).*$\n?"#), ""),                        // code fences
        (regex(#"!\[([^\]]*)\]\([^)]*\)"#), "$1"),                 // images → alt text
        (regex(#"\[([^\]]+)\]\(([^)\s]+)[^)]*\)"#), "$1 ($2)"),     // links → text (url)
        (regex(#"^[ \t]{0,3}#{1,6}[ \t]+"#), ""),                          // headers
        (regex(#"^[ \t]{0,3}>[ \t]?"#), ""),                               // blockquotes
        (regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), "$2"),            // bold
        (regex(#"~~(?=\S)(.+?)(?<=\S)~~"#), "$1"),                   // strikethrough
        (regex(#"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#), "$1"),  // *italic*
        (regex(#"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#), "$1"),    // _italic_
        (regex("`{1,3}([^`\n]+)`{1,3}"), "$1"),                      // inline code
    ]
    private static let checkbox = regex(#"^([ \t]*)(?:[-*+•][ \t]+)?\[[ xX]\][ \t]+"#)
    private static let bullet = regex(#"^([ \t]*)[-*+•◦▪‣][ \t]+"#)
    private static let numbering = regex(#"^([ \t]*)(?:\d{1,4}[.)]|\(\d{1,4}\))[ \t]+"#)
    private static let spaces = regex(#"(?<=\S) {2,}"#)
    private static let trailing = regex(#"[ \t]+$"#)

    public static func clean(_ text: String, options: Options) -> String {
        guard options.enabled else { return text }
        var s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        s.removeAll { $0 == "\u{200B}" || $0 == "\u{200C}" || $0 == "\u{200D}" || $0 == "\u{FEFF}" }
        func apply(_ re: NSRegularExpression, _ template: String) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        if options.removeMarkdown { for (re, template) in markdownRules { apply(re, template) } }
        if options.removeBullets { apply(checkbox, "$1"); apply(bullet, "$1") }
        if options.removeNumbering { apply(numbering, "$1") }
        apply(spaces, " ")
        apply(trailing, "")
        var lines = s.components(separatedBy: "\n")
        if options.removeLeadingWhitespace { lines = lines.map { String($0.drop { $0 == " " || $0 == "\t" }) } }
        if options.removeEmptyLines { lines = lines.filter { !$0.isEmpty } }
        return lines.joined(separator: "\n")
    }
}

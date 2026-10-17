import Foundation
import SuperNotesCore

/// A short link located in the editor text. `expanded` links show their full URL while the caret is inside.
public struct TrackedLink: Equatable {
    public var link: ShortLink
    public var range: NSRange
    public var expanded: Bool
    public init(link: ShortLink, range: NSRange, expanded: Bool = false) {
        self.link = link; self.range = range; self.expanded = expanded
    }
    public var displayed: String { expanded ? link.url : link.short }
}

extension EditorLogic {
    public enum Links {
        public enum EditCheck: Equatable { case allowed, inside, partial }

        /// Finds each stored link's short text in order, skipping ranges already taken (by `existing` or earlier
        /// links). Links whose text is gone are dropped; `existing` links are kept.
        public static func locate(_ links: [ShortLink], in text: String, existing: [TrackedLink] = []) -> [TrackedLink] {
            let s = text as NSString
            var out = existing
            for link in links where !link.short.isEmpty {
                var from = 0
                while from < s.length {
                    let r = s.range(of: link.short, range: NSRange(location: from, length: s.length - from))
                    guard r.location != NSNotFound else { break }
                    if !out.contains(where: { NSIntersectionRange($0.range, r).length > 0 }) {
                        out.append(TrackedLink(link: link, range: r)); break
                    }
                    from = NSMaxRange(r)
                }
            }
            return out.sorted { $0.range.location < $1.range.location }
        }

        /// Whether replacing `range` would cut into a (collapsed) short link. Removing a whole link is allowed.
        public static func check(_ range: NSRange, against links: [TrackedLink]) -> EditCheck {
            for l in links where !l.expanded {
                let r = l.range
                if range.length == 0 {
                    if range.location > r.location && range.location < NSMaxRange(r) { return .inside }
                    continue
                }
                if range.location <= r.location && NSMaxRange(range) >= NSMaxRange(r) { continue }
                if NSIntersectionRange(range, r).length > 0 {
                    return range.location >= r.location && NSMaxRange(range) <= NSMaxRange(r) ? .inside : .partial
                }
            }
            return .allowed
        }

        /// Updates link ranges after `edited` (pre-edit range) was replaced by `replacement`; `text` is the new text.
        /// Expanded links absorb edits inside them (and non-space insertions at their end) and update their URL.
        public static func adjust(_ links: [TrackedLink], edited: NSRange, replacement: String, text: String) -> [TrackedLink] {
            let s = text as NSString
            let insertedLength = (replacement as NSString).length
            let delta = insertedLength - edited.length
            return links.compactMap { l in
                var l = l
                let r = l.range
                if NSMaxRange(edited) <= r.location {
                    l.range.location += delta
                } else if edited.location >= NSMaxRange(r) {
                    let extendsEnd = l.expanded && edited.length == 0 && edited.location == NSMaxRange(r)
                        && !replacement.isEmpty && replacement.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                    guard extendsEnd else { return l }
                    l.range.length += delta
                } else if l.expanded, edited.location >= r.location, NSMaxRange(edited) <= NSMaxRange(r) {
                    l.range.length += delta
                } else {
                    return nil
                }
                guard l.range.length > 0, NSMaxRange(l.range) <= s.length else { return nil }
                let current = s.substring(with: l.range)
                if l.expanded { l.link.url = current; return l }
                return current == l.link.short ? l : nil
            }
        }

        /// Raw `http(s)://` URLs in `text` (trailing punctuation excluded).
        public static func urls(in text: String) -> [NSRange] {
            let s = text as NSString
            return urlRegex.matches(in: text, range: NSRange(location: 0, length: s.length)).map { m in
                var r = m.range
                while r.length > 0, let last = s.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1)).unicodeScalars.first,
                      ".,;:!?'\")]}".unicodeScalars.contains(last) {
                    // Keep a closing parenthesis that balances one inside the URL (Wikipedia-style links).
                    if last == ")", s.substring(with: r).filter({ $0 == "(" }).count >= s.substring(with: r).filter({ $0 == ")" }).count { break }
                    r.length -= 1
                }
                return r
            }
        }

        private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s<>"]+"#, options: [.caseInsensitive])

        /// The URL token ending exactly at `caret` (used when a space or Return follows a typed URL).
        public static func url(endingAt caret: Int, in text: String) -> NSRange? {
            urls(in: text).first { NSMaxRange($0) == caret }
        }

        /// Replaces every raw URL with `shorten(url)` and returns the links at their new positions.
        public static func shrink(_ text: String, shorten: (String) -> String) -> (text: String, links: [TrackedLink]) {
            let s = text as NSString
            var out = "", links: [TrackedLink] = [], cursor = 0
            for r in urls(in: text) {
                out += s.substring(with: NSRange(location: cursor, length: r.location - cursor))
                let url = s.substring(with: r), short = shorten(url)
                if short.isEmpty || short == url {
                    out += url
                } else {
                    let at = (out as NSString).length
                    out += short
                    links.append(TrackedLink(link: ShortLink(url: url, short: short),
                                             range: NSRange(location: at, length: (short as NSString).length)))
                }
                cursor = NSMaxRange(r)
            }
            out += s.substring(from: cursor)
            return (out, links)
        }

        /// `range` of `text` with every short link fully inside it replaced by its URL (for copying).
        public static func expanded(_ text: String, range: NSRange, links: [TrackedLink]) -> String {
            let s = text as NSString
            var out = "", cursor = range.location
            for l in links.sorted(by: { $0.range.location < $1.range.location })
            where !l.expanded && l.range.location >= range.location && NSMaxRange(l.range) <= NSMaxRange(range) {
                out += s.substring(with: NSRange(location: cursor, length: l.range.location - cursor)) + l.link.url
                cursor = NSMaxRange(l.range)
            }
            return out + s.substring(with: NSRange(location: cursor, length: NSMaxRange(range) - cursor))
        }

        /// The text as stored: expanded links collapsed back to their short form.
        public static func collapsed(_ text: String, links: [TrackedLink]) -> String {
            let s = NSMutableString(string: text)
            for l in links.sorted(by: { $0.range.location > $1.range.location }) where l.expanded {
                s.replaceCharacters(in: l.range, with: l.link.short)
            }
            return s as String
        }
    }
}

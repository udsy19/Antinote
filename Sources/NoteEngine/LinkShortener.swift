import Foundation

/// Link Shrink: readable short forms of URLs, and URL detection in plain text.
public enum LinkShortener {
    /// `https://github.com/owner/repo/pull/42` → `github.com/…/pull/42`.
    public static func shorten(_ address: String) -> String {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        else if s.lowercased().hasPrefix("mailto:") { return String(s.dropFirst(7)) }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        var query = false
        if let q = s.firstIndex(of: "?") {
            query = s.index(after: q) < s.endIndex
            s = String(s[..<q])
        }
        while s.hasSuffix("/") { s.removeLast() }
        let parts = s.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let host = parts.first else { return address }
        let path = Array(parts.dropFirst())
        let suffix = query ? "?…" : ""
        let full = ([host] + path).joined(separator: "/")
        if full.count <= 24 || path.isEmpty { return full + suffix }
        var ending = path[path.count - 1]
        var endingCount = 1
        if path.count >= 2, ending.count <= 4 || Int(ending) != nil {
            ending = path[path.count - 2] + "/" + ending
            endingCount = 2
        }
        if ending.count > 28 { ending = String(ending.prefix(25)) + "…" }
        return host + (endingCount == path.count ? "/" : "/…/") + ending + suffix
    }

    public struct DetectedLink: Equatable, Sendable {
        /// UTF-16 range in the searched text (for NSTextStorage).
        public var range: NSRange
        public var url: URL
    }

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Web links in `text`: http(s) URLs, `www.` addresses and bare domains (`example.com/path`).
    public static func detect(in text: String) -> [DetectedLink] {
        detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return nil }
            return DetectedLink(range: match.range, url: url)
        }
    }
}

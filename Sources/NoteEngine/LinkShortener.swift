import Foundation

/// Link Shrink: readable short forms of URLs, and URL detection in plain text.
public enum LinkShortener {
    /// `https://github.com/owner/repo/pull/42` → `+github.com/...ull/42+`: a "+", the host, "/...", the last six
    /// characters of the path, then "+". Addresses that are short already keep their whole path between the "+"s.
    public static func shorten(_ address: String) -> String {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        else if s.lowercased().hasPrefix("mailto:") { return "+" + s.dropFirst(7) + "+" }
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
        let tail = parts.dropFirst().joined(separator: "/") + (query ? "?…" : "")
        let full = tail.isEmpty ? host : host + "/" + tail
        if full.count <= 24 || tail.count <= 6 { return "+" + full + "+" }
        return "+" + host + "/..." + tail.suffix(6) + "+"
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

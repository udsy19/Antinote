import Foundation

/// Case-insensitive subsequence matching with a score that favours exact, prefix, word-start and consecutive hits.
public enum FuzzyMatcher {
    public struct Match: Equatable, Sendable {
        public var score: Int
        /// Character offsets in the candidate that matched.
        public var indices: [Int]
    }

    public static func match(_ query: String, in candidate: String) -> Match? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return Match(score: 0, indices: []) }
        let original = Array(candidate), c = Array(candidate.lowercased())
        guard c.count == original.count else { return substringOnly(query, candidate) }

        var indices: [Int] = [], qi = 0, score = 0, previous = -2
        for (i, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            // Prefer a later word-start occurrence of this character when the next one is close by.
            if !isWordStart(original, i), previous != i - 1,
               let better = (i + 1 ..< min(c.count, i + 12)).first(where: { c[$0] == ch && isWordStart(original, $0) }),
               remainingFits(q, from: qi + 1, in: c, after: better) {
                continue
            }
            if isWordStart(original, i) { score += 10 }
            if previous == i - 1 { score += 6 }
            if previous >= 0 { score -= min(5, i - previous - 1) }
            score += 1
            indices.append(i)
            previous = i
            qi += 1
        }
        guard qi == q.count else { return nil }

        let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        let lowerCandidate = candidate.lowercased()
        if lowerCandidate == lowerQuery { score += 100 }
        else if lowerCandidate.hasPrefix(lowerQuery) { score += 50 }
        else if lowerCandidate.contains(lowerQuery) { score += 25 }
        score -= min(10, indices.first ?? 0) / 2
        return Match(score: score, indices: indices)
    }

    /// Items with a match, best first; ties keep their original order.
    public static func rank<T>(_ items: [T], query: String, text: (T) -> String) -> [(item: T, match: Match)] {
        items.enumerated()
            .compactMap { offset, item in match(query, in: text(item)).map { (offset, item, $0) } }
            .sorted { $0.2.score != $1.2.score ? $0.2.score > $1.2.score : $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }

    private static func isWordStart(_ chars: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let prev = chars[i - 1], ch = chars[i]
        return (!prev.isLetter && !prev.isNumber) || (prev.isLowercase && ch.isUppercase)
    }

    private static func remainingFits(_ q: [Character], from qi: Int, in c: [Character], after start: Int) -> Bool {
        var k = qi
        for j in (start + 1) ..< c.count where k < q.count && c[j] == q[k] { k += 1 }
        return k == q.count
    }

    /// Fallback when lower-casing changes the character count (e.g. "İ"): plain substring matching.
    private static func substringOnly(_ query: String, _ candidate: String) -> Match? {
        candidate.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? nil : Match(score: 25, indices: [])
    }
}

/// A snippet of a note around the first search hit, with every hit's range.
public struct SearchSnippet: Equatable, Sendable {
    public var text: String
    public var highlights: [Range<String.Index>]

    /// The line containing the first match (trimmed to about `radius` characters either side) plus the ranges of
    /// all case-insensitive occurrences of `query` in it.
    public static func make(_ content: String, query: String, radius: Int = 60) -> SearchSnippet {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty, let hit = content.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            let firstLine = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return SearchSnippet(text: String(firstLine.prefix(radius * 2)), highlights: [])
        }
        let line = content.lineRange(for: hit)
        let lineEnd = content[line].hasSuffix("\n") ? content.index(before: line.upperBound) : line.upperBound
        let start = content.index(hit.lowerBound, offsetBy: -radius, limitedBy: line.lowerBound) ?? line.lowerBound
        let end = content.index(hit.upperBound, offsetBy: radius, limitedBy: lineEnd) ?? lineEnd
        var text = String(content[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > line.lowerBound { text = "…" + text }
        if end < lineEnd { text += "…" }
        var ranges: [Range<String.Index>] = []
        var from = text.startIndex
        while let r = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            ranges.append(r)
            from = r.upperBound
        }
        return SearchSnippet(text: text, highlights: ranges)
    }
}

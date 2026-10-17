import Foundation

/// Lightweight syntax highlighting for code notes and fenced blocks: strings, comments, numbers, keywords.
public enum CodeLanguage: String, CaseIterable, Sendable {
    case swift, python, javascript, go, rust, c, shell, sql, ruby, json, generic

    /// Accepts the argument of a `code <lang>` first line or a fence info string.
    public init?(name: String) {
        let aliases: [String: CodeLanguage] = [
            "swift": .swift, "py": .python, "python": .python, "js": .javascript, "javascript": .javascript,
            "ts": .javascript, "typescript": .javascript, "jsx": .javascript, "tsx": .javascript, "go": .go,
            "golang": .go, "rs": .rust, "rust": .rust, "c": .c, "cpp": .c, "c++": .c, "h": .c, "java": .c,
            "kotlin": .c, "cs": .c, "csharp": .c, "objc": .c, "sh": .shell, "bash": .shell, "zsh": .shell,
            "shell": .shell, "sql": .sql, "rb": .ruby, "ruby": .ruby, "json": .json,
        ]
        guard let l = aliases[name.lowercased()] else { return nil }
        self = l
    }

    var lineComments: [String] {
        switch self {
        case .python, .shell, .ruby: ["#"]
        case .sql: ["--"]
        case .json: []
        default: ["//"]
        }
    }
    var hasBlockComments: Bool { [.swift, .javascript, .go, .rust, .c, .sql, .generic].contains(self) }
    var quotes: Set<unichar> {
        switch self {
        case .javascript, .go, .shell: [34, 39, 96]
        case .json: [34]
        default: [34, 39]
        }
    }

    var keywords: Set<String> {
        switch self {
        case .swift: ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "case", "switch",
                      "for", "in", "while", "import", "protocol", "extension", "public", "private", "static", "self",
                      "init", "true", "false", "nil", "try", "throws", "async", "await", "where", "default", "some", "any"]
        case .python: ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "not",
                       "and", "or", "is", "None", "True", "False", "with", "as", "try", "except", "finally", "raise",
                       "lambda", "yield", "pass", "break", "continue", "self", "async", "await", "global"]
        case .javascript: ["function", "const", "let", "var", "return", "if", "else", "for", "while", "of", "in",
                           "class", "extends", "new", "this", "import", "export", "from", "default", "async", "await",
                           "true", "false", "null", "undefined", "typeof", "interface", "type", "switch", "case", "try",
                           "catch", "throw"]
        case .go: ["func", "package", "import", "var", "const", "type", "struct", "interface", "return", "if", "else",
                   "for", "range", "go", "defer", "chan", "map", "switch", "case", "nil", "true", "false", "err"]
        case .rust: ["fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod", "return", "if", "else",
                     "match", "for", "in", "while", "loop", "self", "Self", "true", "false", "Some", "None", "Ok", "Err"]
        case .c: ["int", "char", "void", "float", "double", "long", "unsigned", "struct", "typedef", "return", "if",
                  "else", "for", "while", "switch", "case", "break", "const", "static", "include", "define", "class",
                  "public", "private", "new", "null", "NULL", "true", "false", "this", "import", "package"]
        case .shell: ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "echo",
                      "export", "local", "return", "in", "sudo", "cd"]
        // Matched case-insensitively (see `tokens`).
        case .sql: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table",
                    "drop", "alter", "join", "left", "right", "inner", "on", "and", "or", "not", "null", "order", "by",
                    "group", "limit", "as", "distinct", "count", "primary", "key", "having", "union"]
        case .ruby: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "do", "while", "return", "require",
                     "self", "nil", "true", "false", "yield", "puts", "attr_accessor"]
        case .json: ["true", "false", "null"]
        case .generic: ["if", "else", "for", "while", "return", "function", "class", "true", "false", "null", "nil", "def"]
        }
    }
}

public struct CodeToken: Equatable, Sendable {
    public enum Kind: Sendable { case keyword, string, comment, number }
    public var range: NSRange
    public var kind: Kind
    public init(_ range: NSRange, _ kind: Kind) { self.range = range; self.kind = kind }
}

public enum CodeTokenizer {
    /// Guesses the language from characteristic snippets.
    public static func detect(_ code: String) -> CodeLanguage {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#!"), trimmed.contains("sh") { return .shell }
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && trimmed.contains("\":") { return .json }
        let signals: [(CodeLanguage, [String])] = [
            (.swift, ["func ", "guard ", "let ", "var ", "import SwiftUI", "import Foundation", "-> ", "@MainActor"]),
            (.python, ["def ", "elif ", "self.", "import ", "print(", "None", "):\n"]),
            (.javascript, ["function ", "const ", "=> ", "console.log", "require(", "export ", "undefined"]),
            (.go, ["package ", "func ", ":= ", "fmt.", "go func"]),
            (.rust, ["fn ", "let mut ", "impl ", "pub fn", "println!", "::new("]),
            (.c, ["#include", "int main", "printf(", "public static void", "std::"]),
            (.shell, ["echo ", "$(", "fi\n", "export ", "sudo ", "brew ", "cd "]),
            (.sql, ["select ", "from ", "where ", "insert into", "create table", "group by"]),
            (.ruby, ["end\n", "puts ", "def ", "require '", "do |"]),
        ]
        let lower = code.lowercased()
        var best = (CodeLanguage.generic, 0)
        for (lang, needles) in signals {
            let haystack = lang == .sql ? lower : code
            let score = needles.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
            if score > best.1 { best = (lang, score) }
        }
        return best.0
    }

    public static func tokens(_ code: String, language: CodeLanguage) -> [CodeToken] {
        let s = code as NSString
        let n = s.length
        var out: [CodeToken] = []
        var i = 0
        let keywords = language.keywords
        let lineComments = language.lineComments
        func starts(_ prefix: String, at p: Int) -> Bool {
            let len = (prefix as NSString).length
            return p + len <= n && s.substring(with: NSRange(location: p, length: len)) == prefix
        }
        func isIdent(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
        }
        while i < n {
            let c = s.character(at: i)
            if let prefix = lineComments.first(where: { starts($0, at: i) }),
               !(prefix == "#" && language == .shell && i > 0 && s.character(at: i - 1) == 36) {
                var j = i
                while j < n, s.character(at: j) != 10 { j += 1 }
                out.append(CodeToken(NSRange(location: i, length: j - i), .comment)); i = j; continue
            }
            if language.hasBlockComments, starts("/*", at: i) {
                let end = s.range(of: "*/", range: NSRange(location: i + 2, length: n - i - 2))
                let j = end.location == NSNotFound ? n : NSMaxRange(end)
                out.append(CodeToken(NSRange(location: i, length: j - i), .comment)); i = j; continue
            }
            if language.quotes.contains(c) {
                let q = s.substring(with: NSRange(location: i, length: 1))
                let triple = language == .python && starts(q + q + q, at: i)
                var j = i + (triple ? 3 : 1)
                while j < n {
                    let d = s.character(at: j)
                    if d == 92 { j += 2; continue }                              // backslash escape
                    if triple {
                        if d == c, j + 2 < n, s.character(at: j + 1) == c, s.character(at: j + 2) == c { j += 3; break }
                    } else {
                        if d == c { j += 1; break }
                        if d == 10 && c != 96 { break }                         // unterminated: stop at line end
                    }
                    j += 1
                }
                j = min(j, n)
                out.append(CodeToken(NSRange(location: i, length: j - i), .string)); i = j; continue
            }
            if c >= 48 && c <= 57, i == 0 || !isIdent(s.character(at: i - 1)) {
                var j = i + 1
                while j < n, isIdent(s.character(at: j)) || s.character(at: j) == 46 { j += 1 }
                out.append(CodeToken(NSRange(location: i, length: j - i), .number)); i = j; continue
            }
            if isIdent(c) {
                var j = i + 1
                while j < n, isIdent(s.character(at: j)) { j += 1 }
                let word = s.substring(with: NSRange(location: i, length: j - i))
                if keywords.contains(language == .sql ? word.lowercased() : word) {
                    out.append(CodeToken(NSRange(location: i, length: j - i), .keyword))
                }
                i = j; continue
            }
            i += 1
        }
        return out
    }
}

import Foundation

/// What a command may see of the note.
public enum DataScope: String, Codable, Sendable, CaseIterable {
    case none, line, full

    public var explanation: String {
        switch self {
        case .none: "This extension does not receive any note content."
        case .line: "This extension only receives the line where the command is used."
        case .full: "This extension receives the full content of your note."
        }
    }
}

/// `extension.json` — the static contract of an extension, validated before any of its code runs.
public struct ExtensionManifest: Codable, Sendable, Equatable {
    public var name: String
    public var version: String
    public var author: String?
    public var description: String?
    public var license: String?
    public var category: String?
    public var dataScope: DataScope?
    public var dependencies: [String]?
    public var endpoints: [String]?
    public var requiredAPIKeys: [String]?
    public var files: [String]?
    public var isService: Bool?

    public var scope: DataScope { dataScope ?? .full }
    public var dependencyNames: [String] { dependencies ?? [] }
    public var endpointList: [String] { endpoints ?? [] }
    public var keyIDs: [String] { (requiredAPIKeys ?? []).map(APIKeyID.normalize) }
    /// Scripts in evaluation order.
    public var scriptFiles: [String] { (files?.isEmpty == false) ? files! : ["index.js"] }

    /// Reads and validates `extension.json` in `folder`, checking that every script file exists.
    public static func load(from folder: URL) throws -> ExtensionManifest {
        let url = folder.appendingPathComponent("extension.json")
        guard let data = try? Data(contentsOf: url) else { throw ExtensionError.manifest("Missing extension.json") }
        let manifest = try decode(data)
        for file in manifest.scriptFiles where !FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path) {
            throw ExtensionError.manifest("Missing script file '\(file)'")
        }
        return manifest
    }

    /// Decodes and validates manifest JSON (no file-system checks).
    public static func decode(_ data: Data) throws -> ExtensionManifest {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw ExtensionError.manifest("extension.json is not valid JSON")
        }
        guard let dict = object as? [String: Any] else { throw ExtensionError.manifest("extension.json must be an object") }
        if let scope = dict["dataScope"] as? String, DataScope(rawValue: scope) == nil {
            throw ExtensionError.manifest("dataScope '\(scope)' must be none, line or full")
        }
        let manifest: ExtensionManifest
        do { manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data) } catch {
            throw ExtensionError.manifest("extension.json has a missing or mistyped field: \(Self.describe(error))")
        }
        try manifest.validate()
        return manifest
    }

    public func validate() throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        if name.isEmpty || name.unicodeScalars.contains(where: { !allowed.contains($0) || !$0.isASCII }) {
            throw ExtensionError.manifest("Extension name '\(name)' may only contain letters, digits, '-' and '_'")
        }
        if Version(version) == nil {
            throw ExtensionError.manifest("Version '\(version)' is not valid (expected e.g. 1.0.0)")
        }
        for endpoint in endpointList where !Self.isAcceptableEndpoint(endpoint) {
            throw ExtensionError.manifest("Endpoint '\(endpoint)' must be an https URL (http only for localhost)")
        }
        for file in scriptFiles where file.hasPrefix("/") || file.split(separator: "/").contains("..") || !file.hasSuffix(".js") {
            throw ExtensionError.manifest("Script file '\(file)' must be a relative .js path inside the extension")
        }
        if keyIDs.contains(where: { $0 == APIKeyID.normalize("") }) {
            throw ExtensionError.manifest("requiredAPIKeys contains an empty key name")
        }
    }

    static func isAcceptableEndpoint(_ string: String) -> Bool {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return ["localhost", "127.0.0.1"].contains(host.lowercased())
        default: return false
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, _)?: return "'\(key.stringValue)' is required"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            return "'\(context.codingPath.map(\.stringValue).joined(separator: "."))' has the wrong type"
        default: return error.localizedDescription
        }
    }
}

public enum ExtensionError: Error, Equatable, LocalizedError {
    case manifest(String)
    case script(String)
    case dependency(String)
    case install(String)

    public var errorDescription: String? {
        switch self {
        case .manifest(let m), .script(let m), .dependency(let m), .install(let m): m
        }
    }
}

/// Keychain account naming for extension API keys: `apikey_<name>`.
public enum APIKeyID {
    public static func normalize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("apikey_") ? trimmed : "apikey_" + trimmed
    }
    public static func displayName(_ id: String) -> String { String(id.dropFirst("apikey_".count)) }
}

/// Dotted numeric version ("1.2" == "1.2.0"); pre-release suffixes are ignored.
public struct Version: Comparable, Sendable {
    public let parts: [Int]
    public init?(_ string: String) {
        let core = string.trimmingCharacters(in: .whitespaces).drop { $0 == "v" }.split(separator: "-").first ?? ""
        let pieces = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for p in pieces { guard let n = Int(p), n >= 0 else { return nil }; parts.append(n) }
        while parts.count < 3 { parts.append(0) }
        self.parts = parts
    }
    public static func < (a: Version, b: Version) -> Bool {
        for (x, y) in zip(a.parts, b.parts) where x != y { return x < y }
        return a.parts.count < b.parts.count
    }
    public static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}

/// Orders extensions so dependencies come first; reports missing dependencies and cycles per extension.
public enum DependencyResolver {
    public struct Resolution: Sendable {
        /// Loadable names, dependencies before dependents.
        public var order: [String]
        /// name → reason it cannot load.
        public var errors: [String: String]
    }

    public static func resolve(_ dependencies: [String: [String]]) -> Resolution {
        var order: [String] = []
        var errors: [String: String] = [:]
        var state: [String: Bool] = [:]  // false = visiting, true = done

        @discardableResult
        func visit(_ name: String, path: [String]) -> Bool {
            if state[name] == true { return errors[name] == nil }
            if state[name] == false {
                let cycle = path.drop { $0 != name } + [name]
                let message = "Dependency cycle: " + cycle.joined(separator: " → ")
                for member in cycle where errors[member] == nil { errors[member] = message }
                return false
            }
            state[name] = false
            var ok = true
            for dep in dependencies[name] ?? [] {
                guard dependencies[dep] != nil else {
                    if errors[name] == nil { errors[name] = "'\(name)' depends on '\(dep)', which is not installed" }
                    ok = false; continue
                }
                if !visit(dep, path: path + [name]) {
                    if errors[name] == nil { errors[name] = "'\(name)' depends on '\(dep)', which failed to load" }
                    ok = false
                }
            }
            state[name] = true
            if ok && errors[name] == nil { order.append(name) } else { ok = false }
            return ok
        }

        for name in dependencies.keys.sorted() { visit(name, path: []) }
        return Resolution(order: order, errors: errors)
    }

    /// All transitive dependencies of `name` in load order (excluding `name`).
    public static func closure(of name: String, in dependencies: [String: [String]], order: [String]) -> [String] {
        var seen = Set<String>()
        var stack = dependencies[name] ?? []
        while let next = stack.popLast() {
            if seen.insert(next).inserted { stack += dependencies[next] ?? [] }
        }
        return order.filter { seen.contains($0) }
    }
}

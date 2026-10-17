import Foundation
import JavaScriptCore
import JotterCore

public struct PreferenceSpec: Sendable, Equatable {
    public enum Kind: String, Sendable { case bool, string, paragraph, selectOne, selectMultiple }
    public var key: String
    public var label: String
    public var kind: Kind
    public var defaultValue: JSONValue
    public var options: [String]
    public var helpText: String?
}

/// What a context's scripts registered for one extension.
struct RegisteredExtension: Sendable {
    var name: String
    var commands: [CommandSpec]
    var preferences: [PreferenceSpec]
}

/// The `{status, message, payload}` a command returned.
struct CommandResult: Sendable, Equatable {
    var status: String
    var message: String
    var payload: String
}

/// Who may call what: the extension's (and its dependencies') declared endpoints and key grants.
public struct NetworkPolicy: Sendable {
    public var endpoints: [String]
    /// The extension and its dependencies; a key granted to any of them may be used.
    public var keyOwners: [String]

    public init(endpoints: [String], keyOwners: [String]) { self.endpoints = endpoints; self.keyOwners = keyOwners }

    /// Returns the key secret to substitute (nil when no key is needed), or a user-facing reason for refusing.
    public func authorize(keyName: String, url: String) -> Result<String?, ExtensionError> {
        guard Defaults[.allowExtensionAPIs] else {
            return .failure(.script("Extensions may not use the network. Turn on \"Let extensions call their own APIs\" in Settings → Privacy."))
        }
        guard let target = URL(string: url.replacingOccurrences(of: "{{API_KEY}}", with: "")), let host = target.host else {
            return .failure(.script("'\(url)' is not a valid URL"))
        }
        let allowed = endpoints.compactMap(URL.init(string:)).contains {
            $0.scheme?.lowercased() == target.scheme?.lowercased() && $0.host?.lowercased() == host.lowercased()
                && Self.port($0) == Self.port(target)
        }
        guard allowed else { return .failure(.script("\(host) is not one of this extension's declared endpoints")) }
        guard !keyName.isEmpty else { return .success(nil) }
        let id = APIKeyID.normalize(keyName)
        let display = APIKeyID.displayName(id)
        guard keyOwners.contains(where: ExtensionStore.grants(id).contains) else {
            return .failure(.script("This extension is not allowed to use the '\(display)' API key. Grant it in Settings → Extensions → API Keys."))
        }
        guard let secret = ExtensionStore.secret(id), !secret.isEmpty else {
            return .failure(.script("No '\(display)' API key is stored. Add it in Settings → Extensions → API Keys."))
        }
        return .success(secret)
    }

    private static func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443) }
}

/// One JSContext for one extension (plus its dependencies' scripts), used only on its own serial queue.
final class ExtensionRuntime: @unchecked Sendable {
    let name: String
    let policy: NetworkPolicy
    private let queue: DispatchQueue
    private let clock: @Sendable () -> Date
    private var context: JSContext!
    private var loading = true
    /// Extension name → preference key → default (filled after loading).
    private var preferenceDefaults: [String: [String: JSONValue]] = [:]
    static let requestTimeout: TimeInterval = 60

    private init(name: String, policy: NetworkPolicy, clock: @escaping @Sendable () -> Date) {
        self.name = name
        self.policy = policy
        self.clock = clock
        queue = DispatchQueue(label: "jotter.extension.\(name)", qos: .userInitiated)
    }

    /// Evaluates the base library and `scripts` (dependencies first) synchronously and returns what they registered.
    static func load(name: String, scripts: [(file: String, source: String)], policy: NetworkPolicy,
                     clock: @escaping @Sendable () -> Date) throws -> (ExtensionRuntime, [RegisteredExtension]) {
        let runtime = ExtensionRuntime(name: name, policy: policy, clock: clock)
        let registered = try runtime.queue.sync { () throws -> [RegisteredExtension] in
            defer { runtime.loading = false }
            return try runtime.setUp(scripts: scripts)
        }
        return (runtime, registered)
    }

    private func setUp(scripts: [(file: String, source: String)]) throws -> [RegisteredExtension] {
        guard let context = JSContext() else { throw ExtensionError.script("Could not create a JavaScript context") }
        context.name = "Jotter extension: \(name)"
        self.context = context
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() ?? "Unknown error" }
        installBridges(in: context)

        func evaluate(_ source: String, file: String) throws {
            exception = nil
            context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: file))
            if let exception { throw ExtensionError.script("\(file): \(exception)") }
        }
        try evaluate(BaseLibrary.source, file: "base.js")
        for script in scripts { try evaluate(script.source, file: script.file) }

        guard let json = context.objectForKeyedSubscript("__jotterDescribe")?.call(withArguments: [])?.toString(),
              let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ExtensionError.script(exception ?? "Could not read the registered commands")
        }
        let registered = list.map(Self.decode)
        for ext in registered {
            preferenceDefaults[ext.name] = Dictionary(ext.preferences.map { ($0.key, $0.defaultValue) }) { a, _ in a }
        }
        return registered
    }

    private static func decode(_ d: [String: Any]) -> RegisteredExtension {
        let commands = (d["commands"] as? [[String: Any]] ?? []).compactMap { c -> CommandSpec? in
            guard let name = c["name"] as? String, !name.isEmpty else { return nil }
            return CommandSpec(
                name: name,
                aliases: (c["aliases"] as? [String]) ?? [],
                type: CommandType(rawValue: c["type"] as? String ?? "") ?? .replaceLine,
                helpText: c["helpText"] as? String ?? "",
                parameters: (c["parameters"] as? [[String: Any]] ?? []).map { p in
                    ParameterSpec(name: p["name"] as? String ?? "value", type: ParameterType(js: p["type"] as? String ?? "string"),
                                  helpText: p["helpText"] as? String ?? "", defaultValue: JSONValue(any: p["defaultValue"]),
                                  required: p["required"] as? Bool ?? true)
                },
                tutorials: (c["tutorials"] as? [[String: Any]] ?? []).map {
                    TutorialSpec(command: $0["command"] as? String ?? "", description: $0["description"] as? String ?? "")
                })
        }
        let preferences = (d["preferences"] as? [[String: Any]] ?? []).compactMap { p -> PreferenceSpec? in
            guard let key = p["key"] as? String else { return nil }
            return PreferenceSpec(key: key, label: p["label"] as? String ?? key,
                                  kind: PreferenceSpec.Kind(rawValue: p["type"] as? String ?? "") ?? .string,
                                  defaultValue: JSONValue(any: p["defaultValue"]), options: p["options"] as? [String] ?? [],
                                  helpText: p["helpText"] as? String)
        }
        return RegisteredExtension(name: d["name"] as? String ?? "", commands: commands, preferences: preferences)
    }

    // MARK: Bridges

    private func installBridges(in context: JSContext) {
        let name = self.name
        let log: @convention(block) (String, String) -> Void = { level, message in
            ExtensionLogger.log(name, ExtensionLogger.Entry.Level(rawValue: level) ?? .info, message)
        }
        let math: @convention(block) (String) -> [String: Any] = { [weak self] expression in
            guard let self, !self.loading else { return ["success": false, "error": "Math is unavailable while loading"] }
            return Self.evaluateOnMain(expression)
        }
        let now: @convention(block) () -> Double = { [weak self] in
            (self?.clock() ?? Date()).timeIntervalSince1970 * 1000
        }
        let getPreference: @convention(block) (String) -> JSValue = { [weak self] key in
            self?.preferenceValue(extension: name, key: key) ?? JSValue(nullIn: JSContext.current())
        }
        let getExtensionPreference: @convention(block) (String, String) -> JSValue = { [weak self] ext, key in
            guard let self, ext == name || self.policy.keyOwners.contains(ext) else { return JSValue(nullIn: JSContext.current()) }
            return self.preferenceValue(extension: ext, key: key)
        }
        let callAPI: @convention(block) (String, String, String, JSValue?, JSValue?) -> [String: Any] = { [weak self] key, url, method, headers, body in
            guard let self else { return ["success": false, "error": "Extension unloaded"] }
            return self.callAPI(keyName: key, url: url, method: method, headers: headers, body: body)
        }
        let bridges: [String: Any] = [
            "__nativeLog": log, "__evaluateMathExpression": math, "now": now, "getPreference": getPreference,
            "getExtensionPreference": getExtensionPreference, "callAPI": callAPI,
        ]
        for (key, block) in bridges { context.setObject(block, forKeyedSubscript: key as NSString) }
    }

    private func preferenceValue(extension ext: String, key: String) -> JSValue {
        let value = ExtensionStore.preference(ext, key) ?? preferenceDefaults[ext]?[key] ?? .null
        return JSValue(object: value.foundation, in: JSContext.current())
    }

    private static func evaluateOnMain(_ expression: String) -> [String: Any] {
        var outcome: Result<Double, ExtensionError>?
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                outcome = Services.analyzer.map { analyzer in
                    analyzer.evaluate(expression).mapError { ExtensionError.script($0.localizedDescription) }
                }
            }
        }
        switch outcome {
        case .success(let value)?: return ["success": true, "value": value]
        case .failure(let error)?: return ["success": false, "error": error.localizedDescription]
        case nil: return ["success": false, "error": "Math is unavailable"]
        }
    }

    private func callAPI(keyName: String, url: String, method: String, headers: JSValue?, body: JSValue?) -> [String: Any] {
        let secret: String?
        switch policy.authorize(keyName: keyName, url: url) {
        case .failure(let error):
            ExtensionLogger.log(name, .warning, "callAPI refused: \(error.localizedDescription)")
            return ["success": false, "error": error.localizedDescription]
        case .success(let s): secret = s
        }
        let substitute = { (s: String) in secret.map { s.replacingOccurrences(of: "{{API_KEY}}", with: $0) } ?? s }
        guard let target = URL(string: substitute(url)) else { return ["success": false, "error": "Invalid URL"] }
        var request = URLRequest(url: target, timeoutInterval: Self.requestTimeout)
        request.httpMethod = method.isEmpty ? "GET" : method.uppercased()
        for (field, value) in Self.dictionary(headers) { request.setValue(substitute("\(value)"), forHTTPHeaderField: field) }
        if let body, !body.isUndefined, !body.isNull {
            if body.isString { request.httpBody = body.toString().data(using: .utf8) }
            else if let object = body.toObject(), JSONSerialization.isValidJSONObject(object) {
                request.httpBody = try? JSONSerialization.data(withJSONObject: object)
            }
        }

        let done = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data; box.status = (response as? HTTPURLResponse)?.statusCode ?? 0; box.error = error
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + Self.requestTimeout + 5) == .success else {
            return ["success": false, "error": "The request timed out"]
        }
        let text = box.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if let error = box.error { return ["success": false, "status": 0, "data": text, "error": error.localizedDescription] }
        let ok = (200..<300).contains(box.status)
        return ["success": ok, "status": box.status, "data": text, "error": ok ? NSNull() : "HTTP \(box.status)" as Any]
    }

    private final class ResponseBox: @unchecked Sendable {
        var data: Data?; var status = 0; var error: Error?
    }

    private static func dictionary(_ value: JSValue?) -> [String: Any] {
        guard let value, !value.isUndefined, !value.isNull else { return [:] }
        if value.isString {
            let data = Data(value.toString().utf8)
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        return value.toDictionary() as? [String: Any] ?? [:]
    }

    // MARK: Execution

    /// Runs a command on the extension's queue; `completion` is called on the main queue.
    func execute(command: String, extensionName: String, payload: [String: Any],
                 completion: @escaping @Sendable (CommandResult) -> Void) {
        let payloadJSON = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        queue.async { [self] in
            let result = self.runNow(command: command, extensionName: extensionName, payloadJSON: payloadJSON)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runNow(command: String, extensionName: String, payloadJSON: String) -> CommandResult {
        context.exception = nil
        let json = context.objectForKeyedSubscript("__jotterRun")?
            .call(withArguments: [extensionName, command, payloadJSON])?.toString() ?? ""
        guard let data = json.data(using: .utf8),
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let message = context.exception?.toString() ?? "The command did not return a result"
            return CommandResult(status: "error", message: message, payload: "")
        }
        return CommandResult(status: d["status"] as? String ?? "error", message: d["message"] as? String ?? "",
                             payload: d["payload"] as? String ?? "")
    }
}

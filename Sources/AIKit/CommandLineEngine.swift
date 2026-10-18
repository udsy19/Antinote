import Foundation
import SuperNotesCore

/// A command-line tool the user installed and signed in to on their own. Super Notes only finds the executable
/// and runs it in its documented non-interactive mode with the prompt; it never touches the tool's credentials
/// or its sign-in.
public struct CommandLineTool: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case codex, claude, gemini
    }

    public var kind: Kind
    public var url: URL

    public init(kind: Kind, url: URL) { self.kind = kind; self.url = url }

    public var id: String { url.path }
    public var name: String { kind.rawValue }
    public var label: String { "Use an installed command-line tool: \(name)" }
}

/// How a tool is run: its arguments, what goes to its standard input, and where the answer comes out.
public struct CommandLineInvocation: Equatable, Sendable {
    public var arguments: [String]
    public var standardInput: String?
    /// A file the tool writes its final answer to (standard output otherwise).
    public var answerFile: URL?
}

public enum CommandLineTools {
    /// Where to look, in order: the PATH, then the usual install places. `~/.local/bin` and the npm global
    /// folder hold the official installers' binaries.
    public static func searchDirectories(path: String? = ProcessInfo.processInfo.environment["PATH"],
                                         home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted { out.append(standardized) }
        }
        for entry in (path ?? "").split(separator: ":") where !entry.isEmpty { add(URL(fileURLWithPath: String(entry))) }
        add(URL(fileURLWithPath: "/opt/homebrew/bin"))
        add(URL(fileURLWithPath: "/usr/local/bin"))
        add(home.appendingPathComponent(".local/bin"))
        add(home.appendingPathComponent(".npm-global/bin"))
        add(home.appendingPathComponent(".volta/bin"))
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
        for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) { add(version.appendingPathComponent("bin")) }
        return out
    }

    /// The first executable of each kind in `directories` order.
    public static func detect(in directories: [URL]) -> [CommandLineTool] {
        var found: [CommandLineTool] = []
        for kind in CommandLineTool.Kind.allCases {
            for directory in directories {
                let url = directory.appendingPathComponent(kind.rawValue)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    found.append(CommandLineTool(kind: kind, url: url))
                    break
                }
            }
        }
        return found
    }

    /// Each tool's documented headless form. Nothing may ask a question or touch files: no tools, read-only
    /// sandbox, a throwaway working folder, no saved session.
    public static func invocation(for tool: CommandLineTool, prompt: String, scratch: URL) -> CommandLineInvocation {
        switch tool.kind {
        case .codex:
            let answer = scratch.appendingPathComponent("answer.txt")
            return CommandLineInvocation(
                arguments: ["exec", "--skip-git-repo-check", "--ephemeral", "--color", "never", "-s", "read-only",
                            "-C", scratch.path, "-o", answer.path, "-"],
                standardInput: prompt, answerFile: answer)
        case .claude:
            return CommandLineInvocation(
                arguments: ["-p", "--output-format", "text", "--tools", "", "--no-session-persistence"],
                standardInput: prompt, answerFile: nil)
        case .gemini:
            return CommandLineInvocation(arguments: ["-p", prompt], standardInput: nil, answerFile: nil)
        }
    }

    /// The prompt a tool gets: the standing instructions, then the question.
    public static func text(for request: AIRequest) -> String {
        request.system.isEmpty ? request.prompt : request.system + "\n\n" + request.prompt
    }

    public static let timeout: TimeInterval = 180

    /// Runs the tool with the prompt and captures its answer. The result comes on an arbitrary thread; `cancel()`
    /// on the handle ends the process.
    public static func run(_ tool: CommandLineTool, request: AIRequest, timeout: TimeInterval = timeout,
                           completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration {
        let generation = AIGeneration()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("supernotes-ai-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let invocation = invocation(for: tool, prompt: text(for: request), scratch: scratch)

        let process = Process()
        process.executableURL = tool.url
        process.arguments = invocation.arguments
        process.currentDirectoryURL = scratch
        var environment = ProcessInfo.processInfo.environment
        let path = ([tool.url.deletingLastPathComponent()] + searchDirectories()).map(\.path)
        environment["PATH"] = Array(NSOrderedSet(array: path)).compactMap { $0 as? String }.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let finished = Finished()
        let finish: @Sendable (Result<String, AIError>) -> Void = { result in
            guard finished.claim() else { return }
            try? FileManager.default.removeItem(at: scratch)
            completion(result)
        }
        process.terminationHandler = { process in
            let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if generation.isCancelled { return finish(.failure(.cancelled)) }
            let fromFile = invocation.answerFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let answer = (fromFile?.isEmpty == false ? fromFile! : out).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                let tail = err.split(separator: "\n").suffix(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return finish(.failure(.failed("\(tool.name) exited with status \(process.terminationStatus)" + (tail.isEmpty ? "" : ": \(tail)"))))
            }
            finish(answer.isEmpty ? .failure(.failed("\(tool.name) returned no answer")) : .success(answer))
        }
        do { try process.run() } catch {
            finish(.failure(.failed("Couldn't run \(tool.name): \(error.localizedDescription)")))
            return generation
        }
        if let text = invocation.standardInput { input.fileHandleForWriting.write(Data(text.utf8)) }
        try? input.fileHandleForWriting.close()

        generation.onCancel { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning, !finished.done else { return }
            // The verdict first, so the exit the termination handler then sees isn't reported as the failure.
            finish(.failure(.failed("\(tool.name) took longer than \(Int(timeout)) seconds")))
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        return generation
    }

    private final class Finished: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        var done: Bool { lock.withLock { claimed } }
        func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
    }
}

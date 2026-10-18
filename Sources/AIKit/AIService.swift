import AppKit
import Combine
import SwiftUI
import SuperNotesCore

/// `Services.ai`: picks the engine (Settings → AI), keeps the on-device model coming in the background and
/// answers requests. Readiness tells `::` commands whether to run now, wait for the download, or say what to do.
@MainActor
public final class AIService: ObservableObject, AIServicing {
    public static let shared = AIService()

    public let downloader: ModelDownloader
    private let system: SystemConditions?
    @Published public private(set) var readiness: AIReadiness = .unavailable("")
    @Published public private(set) var tools: [CommandLineTool] = []
    private let readinessSubject = PassthroughSubject<AIReadiness, Never>()
    private var llama: LlamaEngine?
    private var unloadWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    /// The background download starts this long after launch, so the first minutes belong to the user.
    public static let firstDownloadDelay: TimeInterval = 180
    /// The loaded model is released after this long without a request.
    public static let idleUnloadDelay: TimeInterval = 10 * 60

    /// The app's service: the real Models folder, the system's conditions, the tools on this Mac.
    private convenience init() {
        let folder = SuperNotesPaths.models
        let system = SystemConditions(folder: folder)
        self.init(downloader: ModelDownloader(spec: ModelCatalog.default, folder: folder, conditions: { system.current }),
                  system: system, tools: CommandLineTools.detect(in: CommandLineTools.searchDirectories()))
    }

    /// A service over an injected downloader and tool list (self-tests).
    public convenience init(downloader: ModelDownloader, tools: [CommandLineTool]) {
        self.init(downloader: downloader, system: nil, tools: tools)
    }

    init(downloader: ModelDownloader, system: SystemConditions?, tools: [CommandLineTool]) {
        self.downloader = downloader
        self.system = system
        self.tools = tools
        downloader.$state.dropFirst().sink { [weak self] _ in self?.refreshReadiness() }.store(in: &cancellables)
        Defaults.changes.filter { [Defaults.Keys.aiEngine.name, Defaults.Keys.aiAutoDownload.name, Defaults.Keys.aiCommandLineTool.name].contains($0) }
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
        system?.onChange = { [weak self] in
            self?.downloader.conditionsChanged()
            self?.refreshReadiness()
        }
        refreshReadiness()
    }

    /// Called once the app has launched: the download is scheduled, nothing shows.
    public func start() {
        guard !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstDownloadDelay) {
            MainActor.assumeIsolated { AIService.shared.downloadIfWanted() }
        }
    }

    // MARK: - Engine

    public var availability: EngineSelection.Availability {
        EngineSelection.Availability(appleModel: AppleModelEngine.isAvailable, commandLineTool: !tools.isEmpty)
    }

    /// The engine that answers.
    public var engine: AIEngineKind { EngineSelection.resolve(preferred: Defaults[.aiEngine], available: availability) }

    public var appleModelAvailable: Bool { AppleModelEngine.isAvailable }
    public var appleModelUnavailableReason: String { AppleModelEngine.unavailableReason }

    /// The command-line tool the `commandLine` engine runs: the chosen one when it is still there, else the first found.
    public var selectedTool: CommandLineTool? {
        let chosen = Defaults[.aiCommandLineTool]
        return tools.first { $0.url.path == chosen } ?? tools.first
    }

    /// Looks for command-line tools again (Settings → AI → Look Again).
    public func rescanTools() {
        tools = CommandLineTools.detect(in: CommandLineTools.searchDirectories())
        refreshReadiness()
    }

    private func settingsChanged() {
        if Defaults[.aiAutoDownload] { downloadIfWanted() } else { downloader.stop() }
        refreshReadiness()
    }

    /// Starts the background download when it is wanted and the chosen engine would use it.
    private func downloadIfWanted() {
        guard EngineSelection.shouldDownload(engine: engine, autoDownload: Defaults[.aiAutoDownload], installed: downloader.isInstalled)
        else { return }
        downloader.start()
    }

    func refreshReadiness() {
        let next = computeReadiness()
        guard next != readiness else { return }
        readiness = next
        readinessSubject.send(next)
    }

    private func computeReadiness() -> AIReadiness {
        switch engine {
        case .apple:
            return AppleModelEngine.isAvailable ? .ready : .unavailable(AppleModelEngine.unavailableReason + " Choose another engine in Settings → AI.")
        case .commandLine:
            return selectedTool != nil ? .ready
                : .unavailable("No supported command-line tool was found on this Mac. Install and sign in to one, then pick it in Settings → AI.")
        case .onDevice:
            if downloader.isInstalled { return .ready }
            switch downloader.state {
            case .installed: return .ready
            case .downloading, .verifying: return .preparing(downloader.state.preparingText ?? "Getting ready…")
            case .waiting(let blocker):
                return .unavailable("The AI model is still on its way (\(blocker.text.lowercased())). Try again when the download finishes.")
            case .failed(let message):
                return .unavailable("The AI model download stopped (\(message.lowercased())); it will be tried again. Try again when it finishes.")
            case .notInstalled:
                return Defaults[.aiAutoDownload]
                    ? .preparing("Getting ready…")
                    : .unavailable("Download the on-device model in Settings → AI, or turn on “Download models automatically”.")
            }
        }
    }

    // MARK: - AIServicing

    public var readinessChanges: AnyPublisher<AIReadiness, Never> { readinessSubject.eraseToAnyPublisher() }

    public func noteUsed() {
        guard engine == .onDevice, !downloader.isInstalled, Defaults[.aiAutoDownload] else { return }
        if case .notInstalled = downloader.state { downloader.start() }
        refreshReadiness()
    }

    public func complete(_ request: AIRequest, onToken: @escaping @Sendable (String) -> Void,
                         completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration {
        let deliverToken: @Sendable (String) -> Void = { piece in DispatchQueue.main.async { onToken(piece) } }
        let deliver: @Sendable (Result<String, AIError>) -> Void = { result in DispatchQueue.main.async { completion(result) } }
        unloadWork?.cancel()
        switch engine {
        case .apple:
            return AppleModelEngine.generate(request, onToken: deliverToken, completion: deliver)
        case .commandLine:
            guard let tool = selectedTool else {
                let generation = AIGeneration()
                deliver(.failure(.unavailable("No command-line tool is installed.")))
                return generation
            }
            Log.ai.info("Asking \(tool.name, privacy: .public)")
            return CommandLineTools.run(tool, request: request, completion: deliver)
        case .onDevice:
            guard let url = downloader.installedURL else {
                let generation = AIGeneration()
                deliver(.failure(.unavailable("The on-device model isn't downloaded yet.")))
                return generation
            }
            if llama?.modelURL != url { llama?.unload(); llama = LlamaEngine(modelURL: url) }
            let engine = llama!
            return engine.generate(request, onToken: deliverToken) { [weak self] result in
                deliver(result)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleUnload() } }
            }
        }
    }

    /// Frees the model after a quiet while (it holds about 1.5 GB while loaded).
    private func scheduleUnload() {
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let engine = self.llama else { return }
                self.llama = nil
                DispatchQueue.global(qos: .utility).async { engine.unload() }
            }
        }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleUnloadDelay, execute: work)
    }

    /// Removes the downloaded model (and unloads it).
    public func removeModel() {
        let engine = llama
        llama = nil
        DispatchQueue.global(qos: .utility).async { engine?.unload() }
        downloader.remove()
        refreshReadiness()
    }

    /// Fetches the model now, whatever the schedule.
    public func downloadNow() {
        downloader.retryNow()
        refreshReadiness()
    }

    public func makeSettingsView() -> NSView {
        NSHostingView(rootView: AISettingsView(service: self))
    }
}

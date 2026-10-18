import SwiftUI
import SuperNotesCore

/// Settings → AI: the engine, the on-device model's state, and the download switch.
struct AISettingsView: View {
    @ObservedObject var service: AIService
    @ObservedObject var downloader: ModelDownloader
    @Default(.aiEngine) private var preferred
    @Default(.aiAutoDownload) private var autoDownload
    @Default(.aiCommandLineTool) private var toolPath

    init(service: AIService) {
        self.service = service
        downloader = service.downloader
    }

    var body: some View {
        Form {
            Section {
                Picker("Answer with", selection: Binding(get: { service.engine }, set: { preferred = $0 })) {
                    Text("On-device model (default)").tag(AIEngineKind.onDevice)
                    Text("Apple on-device model (macOS 26)").tag(AIEngineKind.apple)
                    Text(service.selectedTool?.label ?? "Use an installed command-line tool").tag(AIEngineKind.commandLine)
                }
                Text(engineCaption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if service.engine == .commandLine { toolControls }
            } header: {
                Text("Engine")
            } footer: {
                Text("`::ask`, `::summarize`, `::rewrite` and `::translate` use this engine. With an on-device engine, nothing you write leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("On-device model") {
                LabeledContent(downloader.spec.displayName) {
                    Text(statusText).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                Text("\(downloader.spec.sizeText) · \(downloader.spec.licence) · downloaded once from \(downloader.spec.host)")
                    .font(.caption).foregroundStyle(.secondary)
                if case .downloading(let received, let total) = downloader.state {
                    ProgressView(value: Double(received), total: Double(max(1, total)))
                }
                if case .verifying = downloader.state { ProgressView() }
                HStack {
                    switch downloader.state {
                    case .installed:
                        Button("Remove", role: .destructive) { service.removeModel() }
                        Button("Re-download") { service.removeModel(); service.downloadNow() }
                    case .downloading, .verifying:
                        Button("Pause") { downloader.stop() }
                    default:
                        Button("Download Now") { service.downloadNow() }
                    }
                }
                Toggle(isOn: $autoDownload) {
                    Text("Download models automatically")
                    Text("Fetches the model a few minutes after launch, on Wi-Fi or another unmetered connection, never in Low Power Mode, and only with 10 GB free.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var engineCaption: String {
        switch service.engine {
        case .onDevice: "Runs the downloaded model on this Mac. Prompts and notes stay on it."
        case .apple: "Runs Apple's model on this Mac. Prompts and notes stay on it."
        case .commandLine:
            "Runs the tool as a separate program with the prompt, the way its own command line does. Whatever you ask goes wherever that tool sends it, under the account you signed in with there. Super Notes never reads its sign-in."
        }
    }

    @ViewBuilder private var toolControls: some View {
        if service.tools.isEmpty {
            Label("No supported command-line tool was found. Install one and sign in to it there, then look again.",
                  systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("Tool", selection: Binding(get: { service.selectedTool?.url.path ?? "" }, set: { toolPath = $0 })) {
                ForEach(service.tools) { tool in Text("\(tool.name) — \(tool.url.path)").tag(tool.url.path) }
            }
        }
        if !service.appleModelAvailable, preferred == .apple {
            Text(service.appleModelUnavailableReason).font(.caption).foregroundStyle(.secondary)
        }
        Button("Look Again") { service.rescanTools() }
    }

    private var statusText: String {
        switch downloader.state {
        case .notInstalled: autoDownload ? "Not downloaded yet" : "Not downloaded"
        case .waiting(let blocker): blocker.text
        case .downloading(let received, let total):
            "Downloading \(Int(Double(received) / Double(max(1, total)) * 100))% · \(ModelSpec.sizeText(received)) of \(ModelSpec.sizeText(total))"
        case .verifying: "Checking the download"
        case .installed: "Installed"
        case .failed(let message): "\(message). Trying again later."
        }
    }
}

import AppKit
import SwiftUI
import SuperNotesCore

/// Settings → Extensions: installed extensions, preferences, API keys, GitHub installs and logs.
struct ExtensionsSettingsView: View {
    @ObservedObject var manager: ExtensionsManager

    var body: some View {
        TabView {
            ExtensionsTab(manager: manager).tabItem { Text("Extensions") }
            APIKeysTab(manager: manager).tabItem { Text("API Keys") }
            LogsTab(logger: .shared).tabItem { Text("Logs") }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 460)
    }
}

// MARK: - Extensions

private struct ExtensionsTab: View {
    @ObservedObject var manager: ExtensionsManager
    @Default(.extensionsEnabled) private var extensionsEnabled
    @Default(.extensionLogging) private var logging
    @Default(.allowExtensionUpdates) private var allowUpdates
    @State private var selection: String?
    @State private var repoURL = ""
    @State private var busy = false
    @State private var status = ""
    @State private var updates: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Enable extensions", isOn: $extensionsEnabled)
                Toggle("Enable extension logging", isOn: $logging)
                    .help("Extension logs capture console output from JavaScript for debugging.")
                Spacer()
                Button("Reload Extensions") { manager.reload(); status = "Extensions reloaded" }
                Button("Open Folder") { NSWorkspace.shared.open(manager.userDirectory) }
            }
            if !extensionsEnabled {
                Text("Extensions are currently disabled. Enable them above to use extension commands.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HSplitView {
                List(selection: $selection) {
                    Section("Loaded Extensions") {
                        ForEach(manager.installed) { ext in
                            HStack {
                                Toggle("", isOn: Binding(get: { manager.isEnabled(ext.manifest.name) },
                                                         set: { manager.setEnabled($0, ext.manifest.name) }))
                                    .labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ext.manifest.name).fontWeight(.medium)
                                    Text(ext.isBundled ? "Bundled · \(ext.manifest.version)" : "Custom · \(ext.manifest.version)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let newer = updates[ext.manifest.name] {
                                    Spacer(); Text("→ \(newer)").font(.caption).foregroundStyle(.tint)
                                }
                            }
                            .tag(ext.manifest.name)
                        }
                    }
                    if !manager.failures.isEmpty {
                        Section("Failed to Load") {
                            ForEach(manager.failures) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.folder.lastPathComponent).fontWeight(.medium)
                                    Text(failure.message).font(.caption).foregroundStyle(.red)
                                }
                                .tag("failure:" + failure.folder.lastPathComponent)
                            }
                        }
                    }
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

                Group {
                    if let name = selection, let ext = manager.installed.first(where: { $0.manifest.name == name }) {
                        ExtensionDetail(manager: manager, ext: ext, newerVersion: updates[name], status: $status)
                    } else if let name = selection, name.hasPrefix("failure:") {
                        FailureDetail(manager: manager, folderName: String(name.dropFirst("failure:".count)), status: $status)
                    } else {
                        Text("Select an extension to view details").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                TextField("https://github.com/owner/repo", text: $repoURL).textFieldStyle(.roundedBorder)
                Button("Install from GitHub") { install() }.disabled(repoURL.isEmpty || busy || !allowUpdates)
                Button("Check for Updates") { checkUpdates() }.disabled(busy || !allowUpdates)
            }
            Text(allowUpdates ? status : "Checking GitHub for extensions is turned off in Privacy settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func install() {
        busy = true; status = "Installing…"
        Task {
            do {
                let manifest = try await manager.install(fromGitHub: repoURL)
                status = "Installed \(manifest.name) \(manifest.version)"; selection = manifest.name; repoURL = ""
            } catch { status = error.localizedDescription }
            busy = false
        }
    }

    private func checkUpdates() {
        busy = true; status = "Checking GitHub…"
        Task {
            do {
                updates = try await manager.checkForUpdates()
                status = updates.isEmpty ? "All extensions are up to date" : "\(updates.count) update(s) available"
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
}

private struct FailureDetail: View {
    @ObservedObject var manager: ExtensionsManager
    let folderName: String
    @Binding var status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(folderName).font(.title3.bold())
            Text(manager.failures.first { $0.folder.lastPathComponent == folderName }?.message ?? "")
                .foregroundStyle(.red).textSelection(.enabled)
            if manager.failures.contains(where: { $0.folder.lastPathComponent == folderName && !$0.folder.path.hasPrefix(manager.bundledDirectory?.path ?? "\u{0}") }) {
                Button("Remove Extension", role: .destructive) {
                    do { try manager.remove(folderName) } catch { status = error.localizedDescription }
                }
            }
            Spacer()
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExtensionDetail: View {
    @ObservedObject var manager: ExtensionsManager
    let ext: ExtensionsManager.Installed
    let newerVersion: String?
    @Binding var status: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ext.manifest.name).font(.title2.bold())
                    Text(ext.manifest.version).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Enabled", isOn: Binding(get: { manager.isEnabled(ext.manifest.name) },
                                                    set: { manager.setEnabled($0, ext.manifest.name) }))
                }
                if let d = ext.manifest.description { Text(d) }
                Text([ext.manifest.author.map { "by \($0)" }, ext.manifest.category, ext.manifest.license]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)

                section("Extension Permissions") {
                    Label(ext.manifest.scope.explanation, systemImage: ext.manifest.scope == .none ? "lock" : "doc.text")
                    if ext.manifest.needsAI {
                        Label("Asks the AI engine chosen in Settings → AI", systemImage: "sparkles")
                    }
                    if ext.manifest.endpointList.isEmpty {
                        Label("Makes no network calls of its own", systemImage: "network.slash")
                    } else {
                        ForEach(ext.manifest.endpointList, id: \.self) { Label($0, systemImage: "network").font(.callout.monospaced()) }
                    }
                    if !ext.manifest.keyIDs.isEmpty {
                        Text("Required API Keys:").font(.callout)
                        ForEach(ext.manifest.keyIDs, id: \.self) { id in
                            let stored = ExtensionStore.secret(id) != nil
                            let granted = ExtensionStore.grants(id).contains(ext.manifest.name)
                            Label("\(APIKeyID.displayName(id)) — \(stored ? (granted ? "available" : "not granted") : "not stored")",
                                  systemImage: stored && granted ? "key.fill" : "key")
                        }
                    }
                    if !ext.manifest.dependencyNames.isEmpty {
                        Text("Depends on: " + ext.manifest.dependencyNames.joined(separator: ", ")).font(.callout)
                    }
                }

                if !ext.preferences.isEmpty {
                    section("Extension Settings") {
                        ForEach(ext.preferences, id: \.key) { PreferenceControl(manager: manager, extensionName: ext.manifest.name, spec: $0) }
                    }
                }

                section("Commands") {
                    ForEach(ext.commands, id: \.name) { command in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(command.signature).font(.body.monospaced().bold())
                            if !command.helpText.isEmpty { Text(command.helpText).font(.callout) }
                            if !command.aliases.isEmpty {
                                Text("Aliases: " + command.aliases.map { "::" + $0 }.joined(separator: ", ")).font(.caption)
                            }
                            ForEach(command.parameters, id: \.name) { p in
                                Text("• \(p.name) (\(p.type.rawValue)\(p.required ? "" : ", optional = \(p.defaultValue.text)")) \(p.helpText)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(command.tutorials, id: \.command) { t in
                                Text("::\(t.command) — \(t.description)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }

                HStack {
                    if let newerVersion {
                        Button("Update to \(newerVersion)") {
                            Task {
                                do { try await manager.update(ext.manifest.name); status = "Updated \(ext.manifest.name)" }
                                catch { status = error.localizedDescription }
                            }
                        }
                    }
                    if let source = Defaults[.extensionsSources][ext.manifest.name], let url = URL(string: source) {
                        Button("Open GitHub Repo") { NSWorkspace.shared.open(url) }
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ext.folder]) }
                    if !ext.isBundled {
                        Button("Remove Extension", role: .destructive) {
                            guard Alerts.confirm("Remove Extension?", info: "This will permanently delete the extension folder and all its files.",
                                                 confirmTitle: "Remove", destructive: true) else { return }
                            do { try manager.remove(ext.manifest.name) } catch { status = error.localizedDescription }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// A control generated from a `Preference` definition.
private struct PreferenceControl: View {
    @ObservedObject var manager: ExtensionsManager
    let extensionName: String
    let spec: PreferenceSpec

    private var value: JSONValue { ExtensionStore.preference(extensionName, spec.key) ?? spec.defaultValue }
    private func set(_ v: JSONValue) { ExtensionStore.setPreference(extensionName, spec.key, v); manager.touch() }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch spec.kind {
            case .bool:
                Toggle(spec.label, isOn: Binding(get: { if case .bool(let b) = value { return b }; return value.text == "true" },
                                                 set: { set(.bool($0)) }))
            case .string:
                LabeledContent(spec.label) {
                    TextField(spec.label, text: Binding(get: { value.text }, set: { set(.string($0)) }))
                        .textFieldStyle(.roundedBorder).labelsHidden()
                }
            case .paragraph:
                Text(spec.label)
                TextEditor(text: Binding(get: { value.text }, set: { set(.string($0)) }))
                    .font(.callout).frame(height: 70).border(Color.secondary.opacity(0.3))
            case .selectOne:
                Picker(spec.label, selection: Binding(get: { value.text }, set: { set(.string($0)) })) {
                    ForEach(spec.options.contains(value.text) || value.text.isEmpty ? spec.options : spec.options + [value.text], id: \.self) {
                        Text($0).tag($0)
                    }
                }
            case .selectMultiple:
                Text(spec.label)
                ForEach(spec.options, id: \.self) { option in
                    Toggle(option, isOn: Binding(get: { selected.contains(option) }, set: { on in
                        set(.list(on ? selected + [option] : selected.filter { $0 != option }))
                    }))
                }
            }
            if let help = spec.helpText { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var selected: [String] {
        if case .list(let l) = value { return l }
        return value.text.isEmpty ? [] : [value.text]
    }
}

// MARK: - API keys

private struct APIKeysTab: View {
    @ObservedObject var manager: ExtensionsManager
    @State private var newName = ""
    @State private var newSecret = ""
    @State private var replacing: [String: String] = [:]

    private var keyIDs: [String] {
        Array(Set(ExtensionStore.keyIDs + manager.installed.flatMap(\.manifest.keyIDs))).sorted()
    }

    var body: some View {
        let _ = manager.revision
        VStack(alignment: .leading, spacing: 10) {
            Text("Add an API key to enable extensions that call external APIs. Keys are stored in your Keychain and only sent to the endpoints an extension declares.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Name (e.g. openai)", text: $newName).frame(width: 160)
                SecureField("Key", text: $newSecret)
                Button("Add") {
                    save(newName, newSecret); newName = ""; newSecret = ""
                }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newSecret.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            if keyIDs.isEmpty { Text("No API keys stored").foregroundStyle(.secondary) }
            List(keyIDs, id: \.self) { id in
                let stored = ExtensionStore.secret(id) != nil
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: stored ? "key.fill" : "key").foregroundStyle(stored ? Color.accentColor : .secondary)
                        Text(APIKeyID.displayName(id)).fontWeight(.medium)
                        Text(stored ? "stored" : "not stored").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        SecureField(stored ? "Replace key" : "Key", text: Binding(get: { replacing[id] ?? "" }, set: { replacing[id] = $0 }))
                            .textFieldStyle(.roundedBorder).frame(width: 180)
                        Button(stored ? "Replace" : "Save") { save(id, replacing[id] ?? ""); replacing[id] = nil }
                            .disabled((replacing[id] ?? "").isEmpty)
                        if stored || ExtensionStore.keyIDs.contains(id) {
                            Button("Delete", role: .destructive) { ExtensionStore.deleteKey(id); manager.touch() }
                        }
                    }
                    let candidates = manager.installed.filter { !$0.manifest.endpointList.isEmpty }
                    if candidates.isEmpty {
                        Text("No loaded extensions require this API key").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Select which extensions can access this API key:").font(.caption)
                        ForEach(candidates) { ext in
                            Toggle(ext.manifest.name + (ext.manifest.keyIDs.contains(id) ? " (requires this key)" : ""),
                                   isOn: Binding(get: { ExtensionStore.grants(id).contains(ext.manifest.name) },
                                                 set: { ExtensionStore.setGrant($0, key: id, extension: ext.manifest.name); manager.touch() }))
                                .toggleStyle(.checkbox).font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func save(_ name: String, _ secret: String) {
        let id = APIKeyID.normalize(name)
        let declaring = manager.installed.filter { $0.manifest.keyIDs.contains(id) }.map(\.manifest.name)
        ExtensionStore.setKey(id, secret: secret, declaredBy: declaring)
        manager.touch()
    }
}

// MARK: - Logs

private struct LogsTab: View {
    @ObservedObject var logger: ExtensionLogger
    @Default(.extensionLogging) private var logging

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(logging ? "Extension logs capture console output from JavaScript for debugging."
                             : "Console output is not recorded while extension logging is off. Load errors are always shown.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { logger.clear() }
            }
            List(logger.entries.reversed()) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.date.formatted(date: .omitted, time: .standard)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(entry.extensionName).font(.caption.bold())
                    Text(entry.message).font(.caption.monospaced())
                        .foregroundStyle(entry.level == .error ? .red : entry.level == .warning ? .orange : .primary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

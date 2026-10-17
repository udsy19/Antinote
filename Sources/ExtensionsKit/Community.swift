import Foundation
import SuperNotesCore

/// A GitHub location of an extension: repository plus optional branch and sub-folder.
public struct GitHubSource: Equatable, Sendable {
    public var owner: String
    public var repo: String
    /// "HEAD" = the default branch.
    public var branch: String
    public var path: String

    /// Accepts `owner/repo`, `https://github.com/owner/repo(.git)` and `…/tree/<branch>/<sub/folder>`.
    public init(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = trimmed
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        var parts = s.split(separator: "/").map(String.init)
        if parts.first?.lowercased() == "github.com" {
            parts.removeFirst()
        } else if trimmed.contains("://") || parts.first?.contains(".") == true {
            throw ExtensionError.install("That doesn't look like a GitHub repository URL.")
        }
        guard parts.count >= 2, !trimmed.contains(" "), !parts.contains("..") else {
            throw ExtensionError.install("That doesn't look like a GitHub repository URL.")
        }
        owner = parts[0]
        repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            branch = parts[3]
            path = parts.dropFirst(4).joined(separator: "/")
        } else {
            branch = "HEAD"
            path = ""
        }
    }

    public var repositoryURL: String { "https://github.com/\(owner)/\(repo)" }

    public func rawURL(_ file: String) -> URL {
        let folder = path.isEmpty ? "" : path + "/"
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(folder)\(file)")!
    }
}

extension ExtensionsManager {
    private func requireUpdatesAllowed() throws {
        guard Defaults[.allowExtensionUpdates] else {
            throw ExtensionError.install("Checking GitHub for extensions is turned off in Settings → Privacy.")
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ExtensionError.install("\(url.lastPathComponent) was not found in the repository.")
        }
        return data
    }

    /// Downloads `extension.json` and its scripts from GitHub into the user extensions folder and reloads.
    @discardableResult
    public func install(fromGitHub location: String) async throws -> ExtensionManifest {
        try requireUpdatesAllowed()
        let source = try GitHubSource(location)
        let manifestData = try await fetch(source.rawURL("extension.json"))
        let manifest = try ExtensionManifest.decode(manifestData)
        var files: [(String, Data)] = [("extension.json", manifestData)]
        for file in manifest.scriptFiles { files.append((file, try await fetch(source.rawURL(file)))) }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("supernotes-ext-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            for (file, data) in files {
                let url = staging.appendingPathComponent(file)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
            let destination = userDirectory.appendingPathComponent(manifest.name, isDirectory: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            throw ExtensionError.install("Failed to install extension: \(error.localizedDescription)")
        }
        Defaults[.extensionsSources][manifest.name] = source.repositoryURL + (source.path.isEmpty ? "" : "/tree/\(source.branch)/\(source.path)")
        reload()
        return manifest
    }

    /// Extensions installed from GitHub whose remote manifest has a newer version: name → remote version.
    public func checkForUpdates() async throws -> [String: String] {
        try requireUpdatesAllowed()
        var updates: [String: String] = [:]
        for (name, location) in Defaults[.extensionsSources] {
            guard let current = installed.first(where: { $0.manifest.name == name }), !current.isBundled,
                  let source = try? GitHubSource(location),
                  let data = try? await fetch(source.rawURL("extension.json")),
                  let remote = try? ExtensionManifest.decode(data),
                  let remoteVersion = Version(remote.version), let localVersion = Version(current.manifest.version),
                  localVersion < remoteVersion else { continue }
            updates[name] = remote.version
        }
        return updates
    }

    public func update(_ name: String) async throws {
        guard let location = Defaults[.extensionsSources][name] else {
            throw ExtensionError.install("'\(name)' was not installed from GitHub.")
        }
        try await install(fromGitHub: location)
    }

    /// Deletes a user-installed extension's folder (bundled extensions can only be disabled).
    public func remove(_ name: String) throws {
        if installed.contains(where: { $0.manifest.name == name && $0.isBundled }) {
            throw ExtensionError.install("Bundled extensions can't be removed; disable them instead.")
        }
        let folder = installed.first { $0.manifest.name == name }?.folder ?? userDirectory.appendingPathComponent(name)
        guard folder.standardizedFileURL.path.hasPrefix(userDirectory.standardizedFileURL.path + "/") else {
            throw ExtensionError.install("'\(name)' is not in the extensions folder.")
        }
        try FileManager.default.removeItem(at: folder)
        Defaults[.extensionsSources][name] = nil
        reload()
    }
}

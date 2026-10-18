import Foundation
import SuperNotesCore

/// The pure part of choosing an engine: what the user picked against what the Mac has.
public enum EngineSelection {
    public struct Availability: Sendable, Equatable {
        /// Apple's on-device model answers on this Mac (macOS 26, Apple Intelligence on).
        public var appleModel: Bool
        /// A supported command-line tool is installed.
        public var commandLineTool: Bool
        public init(appleModel: Bool, commandLineTool: Bool) { self.appleModel = appleModel; self.commandLineTool = commandLineTool }
    }

    /// The engine to use. Nothing picked: Apple's model where present, else the downloaded one. Apple's model
    /// picked on a Mac without it: the downloaded one. The command-line tool is used whenever it is picked; its
    /// readiness says so when no tool is installed.
    public static func resolve(preferred: AIEngineKind?, available: Availability) -> AIEngineKind {
        switch preferred {
        case nil: available.appleModel ? .apple : .onDevice
        case .apple?: available.appleModel ? .apple : .onDevice
        case .onDevice?: .onDevice
        case .commandLine?: .commandLine
        }
    }

    /// Whether the background download should run: only when it is wanted, missing, and the downloaded model is
    /// the engine that would answer (a Mac on Apple's model doesn't fetch 1.3 GB it won't use).
    public static func shouldDownload(engine: AIEngineKind, autoDownload: Bool, installed: Bool) -> Bool {
        autoDownload && !installed && engine == .onDevice
    }
}

/// What the downloader checks before it uses the network or the disk. The app reads the system
/// (`SystemConditions`); tests inject values.
public struct DownloadConditions: Sendable, Equatable {
    /// A network path is up and is neither expensive (hotspot, cellular) nor constrained (Low Data Mode).
    public var networkOK: Bool
    public var lowPowerMode: Bool
    public var freeDiskBytes: Int64

    public init(networkOK: Bool, lowPowerMode: Bool, freeDiskBytes: Int64) {
        self.networkOK = networkOK; self.lowPowerMode = lowPowerMode; self.freeDiskBytes = freeDiskBytes
    }

    /// Downloads wait until this much is free, so a model never fills the disk.
    public static let minimumFreeDisk: Int64 = 10_000_000_000

    /// Why a download can't start now, or nil when it can.
    public var blocker: Blocker? {
        if freeDiskBytes < Self.minimumFreeDisk { return .disk }
        if lowPowerMode { return .lowPower }
        if !networkOK { return .network }
        return nil
    }

    public enum Blocker: Sendable, Equatable {
        case disk, lowPower, network

        public var text: String {
            switch self {
            case .disk: "Waiting for \(ModelSpec.sizeText(DownloadConditions.minimumFreeDisk)) of free disk space"
            case .lowPower: "Paused in Low Power Mode"
            case .network: "Waiting for Wi-Fi or another unmetered connection"
            }
        }
    }
}

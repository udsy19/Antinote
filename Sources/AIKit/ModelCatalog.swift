import Foundation
import SuperNotesCore

/// One downloadable model: where it comes from and how to recognise the right bytes.
public struct ModelSpec: Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var fileName: String
    public var url: URL
    /// Lower-case hex SHA-256 of the file.
    public var sha256: String
    public var bytes: Int64
    public var licence: String

    public init(id: String, displayName: String, fileName: String, url: URL, sha256: String, bytes: Int64, licence: String) {
        self.id = id; self.displayName = displayName; self.fileName = fileName; self.url = url
        self.sha256 = sha256; self.bytes = bytes; self.licence = licence
    }

    public var host: String { url.host ?? "" }
    /// "1.28 GB".
    public var sizeText: String { ModelSpec.sizeText(bytes) }

    public static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

/// The models Super Notes knows how to fetch.
public enum ModelCatalog {
    /// Qwen3.5 2B instruct, Q4_K_M GGUF (Apache-2.0), the same pick the sister project measured: good answers,
    /// 1.28 GB, about 1.5 GB resident. Pinned to a repository commit so a re-upload can't change the bytes
    /// behind the hash; the hash is the file's Hugging Face LFS id, verified by downloading and hashing it.
    public static let qwen35_2B = ModelSpec(
        id: "qwen3.5-2b-q4_k_m",
        displayName: "Qwen3.5 2B (Q4_K_M)",
        fileName: "Qwen3.5-2B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-Q4_K_M.gguf")!,
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
        bytes: 1_280_835_840,
        licence: "Apache-2.0")

    /// The on-device model `::ask` uses.
    public static let `default` = qwen35_2B
}

import Foundation

struct LocalWhisperCatalogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let approximateSizeBytes: Int64
    let qualityDescription: String
    let sourceRevision: String
    let sha256: String?

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(sourceRevision)/\(fileName)")!
    }

    var isInstallable: Bool {
        guard let sha256 else { return false }
        return sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
    }

    var descriptor: LocalWhisperModelDescriptor? {
        guard let sha256, isInstallable else { return nil }
        return LocalWhisperModelDescriptor(
            id: id,
            displayName: displayName,
            fileName: fileName,
            downloadURL: downloadURL,
            sha256: sha256,
            approximateSizeBytes: approximateSizeBytes
        )
    }
}

enum LocalWhisperModelCatalog {
    /// The upstream revision is pinned so model URLs never silently move to different bytes.
    static let upstreamRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"

    /// Catalog metadata is intentionally available before downloads are enabled.
    /// A model becomes installable only after its 64-character SHA-256 is independently verified.
    static let recommended: [LocalWhisperCatalogEntry] = [
        LocalWhisperCatalogEntry(
            id: "tiny",
            displayName: "Whisper Tiny",
            fileName: "ggml-tiny.bin",
            approximateSizeBytes: 75_000_000,
            qualityDescription: "Fastest and lightest; suitable for quick drafts.",
            sourceRevision: upstreamRevision,
            sha256: nil
        ),
        LocalWhisperCatalogEntry(
            id: "base",
            displayName: "Whisper Base",
            fileName: "ggml-base.bin",
            approximateSizeBytes: 142_000_000,
            qualityDescription: "Balanced speed and accuracy; planned default.",
            sourceRevision: upstreamRevision,
            sha256: nil
        ),
        LocalWhisperCatalogEntry(
            id: "small",
            displayName: "Whisper Small",
            fileName: "ggml-small.bin",
            approximateSizeBytes: 466_000_000,
            qualityDescription: "Higher accuracy with greater memory and latency.",
            sourceRevision: upstreamRevision,
            sha256: nil
        )
    ]

    static func entry(id: String) -> LocalWhisperCatalogEntry? {
        recommended.first { $0.id == id }
    }
}

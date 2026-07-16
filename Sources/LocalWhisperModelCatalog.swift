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
    /// Pinned upstream revision. Hashes below are the Git LFS SHA-256 OIDs for
    /// the files at this exact revision, so the download URL and integrity check
    /// refer to the same immutable bytes.
    static let upstreamRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"

    static let recommended: [LocalWhisperCatalogEntry] = [
        LocalWhisperCatalogEntry(
            id: "tiny",
            displayName: "Whisper Tiny",
            fileName: "ggml-tiny.bin",
            approximateSizeBytes: 75_000_000,
            qualityDescription: "Fastest and lightest; suitable for quick drafts.",
            sourceRevision: upstreamRevision,
            sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
        ),
        LocalWhisperCatalogEntry(
            id: "base",
            displayName: "Whisper Base",
            fileName: "ggml-base.bin",
            approximateSizeBytes: 142_000_000,
            qualityDescription: "Balanced speed and accuracy; recommended default.",
            sourceRevision: upstreamRevision,
            sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
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

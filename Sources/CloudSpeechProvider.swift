import Foundation

/// Cloud-backed speech provider that adapts the existing OpenAI-compatible
/// transcription client to the provider-neutral `SpeechProvider` boundary.
final class CloudSpeechProvider: SpeechProvider {
    let capabilities: SpeechProviderCapabilities = .openAICompatibleCloud

    private let service: TranscriptionService

    init(service: TranscriptionService) {
        self.service = service
    }

    convenience init(
        apiKey: String,
        baseURL: String = "https://api.groq.com/openai/v1",
        transcriptionModel: String = "whisper-large-v3",
        language: String? = nil
    ) throws {
        try self.init(
            service: TranscriptionService(
                apiKey: apiKey,
                baseURL: baseURL,
                transcriptionModel: transcriptionModel,
                language: language
            )
        )
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await service.transcribe(fileURL: fileURL)
    }
}

/// Constructs provider-neutral speech implementations from application settings.
/// Local and hybrid providers are deliberately rejected until their runtimes are
/// installed, preventing the UI from silently falling back to the cloud.
enum SpeechProviderFactory {
    enum FactoryError: LocalizedError, Equatable {
        case unsupportedMode(SpeechExecutionMode)

        var errorDescription: String? {
            switch self {
            case .unsupportedMode(.local):
                return "Local transcription is not installed yet."
            case .unsupportedMode(.hybrid):
                return "Hybrid transcription is not available yet."
            case .unsupportedMode(.cloud):
                return "Cloud transcription is unavailable."
            }
        }
    }

    static func makeCloudProvider(
        apiKey: String,
        baseURL: String,
        transcriptionModel: String,
        language: String?
    ) throws -> any SpeechProvider {
        try CloudSpeechProvider(
            apiKey: apiKey,
            baseURL: baseURL,
            transcriptionModel: transcriptionModel,
            language: language
        )
    }

    static func makeProvider(
        mode: SpeechExecutionMode,
        cloudProvider: @autoclosure () throws -> any SpeechProvider
    ) throws -> any SpeechProvider {
        switch mode {
        case .cloud:
            return try cloudProvider()
        case .local, .hybrid:
            throw FactoryError.unsupportedMode(mode)
        }
    }
}

/// Small provider-neutral execution boundary used by application pipelines and
/// tests. Keeping cancellation at this level gives every future provider the
/// same behavior before and after the provider call.
struct SpeechTranscriptionRunner {
    let provider: any SpeechProvider

    func transcribe(fileURL: URL) async throws -> String {
        try Task.checkCancellation()
        let transcript = try await provider.transcribe(fileURL: fileURL)
        try Task.checkCancellation()
        return transcript
    }
}

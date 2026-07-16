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

extension SpeechProviderFactory {
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
}

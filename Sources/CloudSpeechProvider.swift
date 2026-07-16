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
enum SpeechProviderFactory {
    enum FactoryError: LocalizedError, Equatable {
        case unsupportedMode(SpeechExecutionMode)
        case localRuntimeUnavailable
        case localModelUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedMode(.hybrid):
                return "Hybrid transcription is not available yet."
            case .unsupportedMode(.local):
                return "Local transcription is unavailable."
            case .unsupportedMode(.cloud):
                return "Cloud transcription is unavailable."
            case .localRuntimeUnavailable:
                return "The local Whisper runtime is not installed or executable."
            case .localModelUnavailable:
                return "The selected local Whisper model is not installed."
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

    static func makeLocalProvider(
        runtimeStatus: LocalWhisperRuntimeStatus,
        modelURL: URL?,
        language: String?,
        timeout: TimeInterval = 120,
        processRunner: any LocalWhisperProcessRunning = FoundationLocalWhisperProcessRunner()
    ) throws -> any SpeechProvider {
        guard runtimeStatus.isReady, let executableURL = runtimeStatus.executableURL else {
            throw FactoryError.localRuntimeUnavailable
        }
        guard let modelURL else {
            throw FactoryError.localModelUnavailable
        }

        do {
            return try LocalWhisperSpeechProvider(
                executableURL: executableURL,
                modelURL: modelURL,
                language: language,
                timeout: timeout,
                processRunner: processRunner
            )
        } catch LocalWhisperSpeechProviderError.runtimeUnavailable {
            throw FactoryError.localRuntimeUnavailable
        } catch LocalWhisperSpeechProviderError.modelUnavailable {
            throw FactoryError.localModelUnavailable
        }
    }

    /// Backward-compatible factory used by call sites that only have a cloud provider.
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

    /// Provider-complete factory. Local must be explicitly supplied; Hybrid remains unavailable.
    static func makeProvider(
        mode: SpeechExecutionMode,
        cloudProvider: @autoclosure () throws -> any SpeechProvider,
        localProvider: @autoclosure () throws -> any SpeechProvider
    ) throws -> any SpeechProvider {
        switch mode {
        case .cloud:
            return try cloudProvider()
        case .local:
            return try localProvider()
        case .hybrid:
            throw FactoryError.unsupportedMode(.hybrid)
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

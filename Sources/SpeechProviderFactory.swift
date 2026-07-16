import Foundation

/// Constructs provider-neutral speech implementations without coupling local
/// tests to the cloud transport implementation.
enum SpeechProviderFactory {
    enum FactoryError: LocalizedError, Equatable {
        case unsupportedMode(SpeechExecutionMode)
        case localRuntimeUnavailable
        case localModelUnavailable
        case localModelInvalidChecksum

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
            case .localModelInvalidChecksum:
                return "The selected local Whisper model failed its integrity check. Remove and download it again."
            }
        }
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

/// Provider-neutral execution boundary used by the dictation pipeline and tests.
struct SpeechTranscriptionRunner {
    let provider: any SpeechProvider

    func transcribe(fileURL: URL) async throws -> String {
        try Task.checkCancellation()
        let transcript = try await provider.transcribe(fileURL: fileURL)
        try Task.checkCancellation()
        return transcript
    }
}

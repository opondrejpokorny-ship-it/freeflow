import Foundation

extension AppState {
    /// Provider-neutral replacement for `makeTranscriptionService()`.
    ///
    /// Existing call sites can migrate one by one without duplicating provider
    /// configuration or exposing API credentials outside `AppState`.
    func makeSpeechProvider() throws -> any SpeechProvider {
        CloudSpeechProvider(service: try makeTranscriptionService())
    }

    /// Builds the provider-neutral runner used by the dictation pipeline.
    func makeSpeechTranscriptionRunner() throws -> SpeechTranscriptionRunner {
        SpeechTranscriptionRunner(provider: try makeSpeechProvider())
    }
}

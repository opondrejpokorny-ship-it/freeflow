import Foundation

extension AppState {
    static let speechExecutionModeStorageKey = "speech_execution_mode"
    static let localWhisperModelIDStorageKey = "local_whisper_model_id"
    static let localWhisperExecutablePathStorageKey = "local_whisper_executable_path"

    var speechExecutionMode: SpeechExecutionMode {
        let rawValue = UserDefaults.standard.string(forKey: Self.speechExecutionModeStorageKey)
        return SpeechExecutionMode(rawValue: rawValue ?? "") ?? .cloud
    }

    var selectedLocalWhisperModelID: String {
        let stored = UserDefaults.standard.string(forKey: Self.localWhisperModelIDStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "base" : stored
    }

    var customLocalWhisperExecutableURL: URL? {
        let stored = UserDefaults.standard.string(forKey: Self.localWhisperExecutablePathStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !stored.isEmpty else { return nil }
        let expanded = NSString(string: stored).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Builds the provider selected in Settings. Local mode never silently
    /// falls back to Cloud: missing or corrupted dependencies surface a clear error.
    func makeSpeechProvider() throws -> any SpeechProvider {
        switch speechExecutionMode {
        case .cloud:
            return CloudSpeechProvider(service: try makeTranscriptionService())
        case .local:
            return try makeVerifiedLocalSpeechProvider()
        case .hybrid:
            throw SpeechProviderFactory.FactoryError.unsupportedMode(.hybrid)
        }
    }

    func makeSpeechTranscriptionRunner() throws -> SpeechTranscriptionRunner {
        SpeechTranscriptionRunner(provider: try makeSpeechProvider())
    }

    private func makeVerifiedLocalSpeechProvider() throws -> any SpeechProvider {
        guard let catalogEntry = LocalWhisperModelCatalog.entry(id: selectedLocalWhisperModelID),
              let descriptor = catalogEntry.descriptor else {
            throw SpeechProviderFactory.FactoryError.localModelUnavailable
        }

        let modelsDirectory = try LocalWhisperModelManager.defaultModelsDirectory()
        let modelURL = modelsDirectory.appendingPathComponent(descriptor.fileName, isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw SpeechProviderFactory.FactoryError.localModelUnavailable
        }

        let actualChecksum = try LocalWhisperModelManager.sha256(of: modelURL)
        guard actualChecksum.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
            throw SpeechProviderFactory.FactoryError.localModelInvalidChecksum
        }

        let runtimeStatus = LocalWhisperRuntimeDetector(
            customExecutableURL: customLocalWhisperExecutableURL
        ).detect()

        return try SpeechProviderFactory.makeLocalProvider(
            runtimeStatus: runtimeStatus,
            modelURL: modelURL,
            language: transcriptionLanguage
        )
    }
}

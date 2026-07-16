import Foundation

/// Provider-neutral interface for converting a recorded audio file into text.
///
/// Implementations may execute remotely, locally, or combine both approaches.
/// Callers should depend on this protocol rather than a concrete API client.
protocol SpeechProvider {
    var capabilities: SpeechProviderCapabilities { get }
    func transcribe(fileURL: URL) async throws -> String
}

/// Describes where speech recognition work is performed.
enum SpeechExecutionMode: String, CaseIterable, Codable, Sendable {
    case cloud
    case local
    case hybrid
}

/// Capabilities exposed by a speech provider without leaking implementation details.
struct SpeechProviderCapabilities: Equatable, Sendable {
    let executionMode: SpeechExecutionMode
    let supportsAutomaticLanguageDetection: Bool
    let supportsLanguageHint: Bool
    let requiresNetwork: Bool

    static let openAICompatibleCloud = SpeechProviderCapabilities(
        executionMode: .cloud,
        supportsAutomaticLanguageDetection: true,
        supportsLanguageHint: true,
        requiresNetwork: true
    )
}

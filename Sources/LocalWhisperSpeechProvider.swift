import Foundation

struct LocalWhisperProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

protocol LocalWhisperProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> LocalWhisperProcessResult
}

enum LocalWhisperProcessError: LocalizedError, Equatable {
    case timedOut(TimeInterval)
    case failedToLaunch(String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(timeout):
            return "Local transcription timed out after \(Int(timeout)) seconds."
        case let .failedToLaunch(message):
            return "Unable to launch local Whisper: \(message)"
        }
    }
}

final class FoundationLocalWhisperProcessRunner: LocalWhisperProcessRunning, @unchecked Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> LocalWhisperProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withThrowingTaskGroup(of: LocalWhisperProcessResult.self) { group in
                group.addTask {
                    return try await withCheckedThrowingContinuation { continuation in
                        process.terminationHandler = { process in
                            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
                            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                            continuation.resume(returning: LocalWhisperProcessResult(
                                exitCode: process.terminationStatus,
                                standardOutput: String(decoding: outputData, as: UTF8.self),
                                standardError: String(decoding: errorData, as: UTF8.self)
                            ))
                        }

                        do {
                            try process.run()
                        } catch {
                            continuation.resume(throwing: LocalWhisperProcessError.failedToLaunch(error.localizedDescription))
                        }
                    }
                }

                group.addTask {
                    let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    if process.isRunning {
                        process.terminate()
                    }
                    throw LocalWhisperProcessError.timedOut(timeout)
                }

                guard let first = try await group.next() else {
                    throw LocalWhisperProcessError.failedToLaunch("Process produced no result.")
                }
                group.cancelAll()
                return first
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

enum LocalWhisperSpeechProviderError: LocalizedError, Equatable {
    case runtimeUnavailable
    case modelUnavailable
    case invalidAudioFile
    case processFailed(exitCode: Int32, message: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "The local Whisper runtime is not installed or executable."
        case .modelUnavailable:
            return "The selected local Whisper model is not installed."
        case .invalidAudioFile:
            return "The recorded audio file is missing or unreadable."
        case let .processFailed(exitCode, message):
            return "Local Whisper exited with code \(exitCode): \(message)"
        case .emptyTranscript:
            return "Local Whisper returned an empty transcript."
        }
    }
}

final class LocalWhisperSpeechProvider: SpeechProvider {
    let capabilities = SpeechProviderCapabilities(
        executionMode: .local,
        supportsAutomaticLanguageDetection: true,
        supportsLanguageHint: true,
        requiresNetwork: false
    )

    private let executableURL: URL
    private let modelURL: URL
    private let language: String?
    private let timeout: TimeInterval
    private let fileManager: FileManager
    private let processRunner: any LocalWhisperProcessRunning

    init(
        executableURL: URL,
        modelURL: URL,
        language: String? = nil,
        timeout: TimeInterval = 120,
        fileManager: FileManager = .default,
        processRunner: any LocalWhisperProcessRunning = FoundationLocalWhisperProcessRunner()
    ) throws {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw LocalWhisperSpeechProviderError.runtimeUnavailable
        }
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw LocalWhisperSpeechProviderError.modelUnavailable
        }

        self.executableURL = executableURL
        self.modelURL = modelURL
        self.language = LanguageService.normalizedInputCode(language ?? "")
        self.timeout = timeout
        self.fileManager = fileManager
        self.processRunner = processRunner
    }

    func transcribe(fileURL: URL) async throws -> String {
        try Task.checkCancellation()

        guard fileManager.isReadableFile(atPath: fileURL.path) else {
            throw LocalWhisperSpeechProviderError.invalidAudioFile
        }

        var arguments = [
            "--model", modelURL.path,
            "--file", fileURL.path,
            "--no-timestamps"
        ]

        if let language, !language.isEmpty {
            arguments.append(contentsOf: ["--language", language])
        } else {
            arguments.append(contentsOf: ["--language", "auto"])
        }

        let result = try await processRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        )

        try Task.checkCancellation()

        guard result.exitCode == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalWhisperSpeechProviderError.processFailed(
                exitCode: result.exitCode,
                message: message.isEmpty ? "Unknown error" : message
            )
        }

        let transcript = Self.cleanedTranscript(from: result.standardOutput)
        guard !transcript.isEmpty else {
            throw LocalWhisperSpeechProviderError.emptyTranscript
        }
        return transcript
    }

    static func cleanedTranscript(from output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

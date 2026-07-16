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

/// Runs whisper.cpp with file-backed stdout/stderr. File handles avoid the
/// bounded-pipe deadlock that can occur when a child process writes enough logs
/// before its parent starts draining the pipes.
final class FoundationLocalWhisperProcessRunner: LocalWhisperProcessRunning, @unchecked Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> LocalWhisperProcessResult {
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("freeflow-whisper-process-\(UUID().uuidString)", isDirectory: true)
        let outputURL = captureDirectory.appendingPathComponent("stdout.txt")
        let errorURL = captureDirectory.appendingPathComponent("stderr.txt")

        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? fileManager.removeItem(at: captureDirectory)
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withThrowingTaskGroup(of: LocalWhisperProcessResult.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        process.terminationHandler = { process in
                            try? outputHandle.close()
                            try? errorHandle.close()
                            let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
                            let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
                            continuation.resume(returning: LocalWhisperProcessResult(
                                exitCode: process.terminationStatus,
                                standardOutput: String(decoding: outputData, as: UTF8.self),
                                standardError: String(decoding: errorData, as: UTF8.self)
                            ))
                        }

                        do {
                            try process.run()
                        } catch {
                            try? outputHandle.close()
                            try? errorHandle.close()
                            continuation.resume(
                                throwing: LocalWhisperProcessError.failedToLaunch(error.localizedDescription)
                            )
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
        guard fileManager.isReadableFile(atPath: modelURL.path) else {
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
            "--no-timestamps",
            "--no-prints"
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
            .filter { !$0.isEmpty && !looksLikeTimestampLine($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeTimestampLine(_ line: String) -> Bool {
        line.hasPrefix("[") && line.contains("-->") && line.hasSuffix("]")
    }
}

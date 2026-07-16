import Foundation

@main
struct LocalWhisperSpeechProviderTests {
    static func main() async {
        testTranscriptCleanup()
        await testProviderBuildsArgumentsAndReturnsTranscript()
        await testProviderPropagatesProcessFailure()
        testFactoryRejectsMissingRuntimeAndModel()
        print("LocalWhisperSpeechProviderTests passed")
    }

    private static func testTranscriptCleanup() {
        let output = """
        [00:00:00.000 --> 00:00:01.000]
        Ahoj světe.

        Toto je test.
        """
        expectEqual(
            LocalWhisperSpeechProvider.cleanedTranscript(from: output),
            "Ahoj světe. Toto je test."
        )
    }

    private static func testProviderBuildsArgumentsAndReturnsTranscript() async {
        let fixture = try! Fixture()
        defer { fixture.cleanup() }

        let runner = FakeProcessRunner(result: LocalWhisperProcessResult(
            exitCode: 0,
            standardOutput: "Ahoj světe.\n",
            standardError: ""
        ))
        let provider = try! LocalWhisperSpeechProvider(
            executableURL: fixture.executableURL,
            modelURL: fixture.modelURL,
            language: "cs-CZ",
            processRunner: runner
        )

        let transcript = try? await provider.transcribe(fileURL: fixture.audioURL)
        expectEqual(transcript, "Ahoj světe.")
        expect(runner.arguments.contains("--model"), "Model argument is missing")
        expect(runner.arguments.contains(fixture.modelURL.path), "Model path is missing")
        expect(runner.arguments.contains("--file"), "Audio argument is missing")
        expect(runner.arguments.contains(fixture.audioURL.path), "Audio path is missing")
        expect(runner.arguments.suffix(2) == ["--language", "cs"], "Language was not normalized")
    }

    private static func testProviderPropagatesProcessFailure() async {
        let fixture = try! Fixture()
        defer { fixture.cleanup() }

        let runner = FakeProcessRunner(result: LocalWhisperProcessResult(
            exitCode: 2,
            standardOutput: "",
            standardError: "invalid model"
        ))
        let provider = try! LocalWhisperSpeechProvider(
            executableURL: fixture.executableURL,
            modelURL: fixture.modelURL,
            processRunner: runner
        )

        do {
            _ = try await provider.transcribe(fileURL: fixture.audioURL)
            fatalError("Expected process failure")
        } catch let error as LocalWhisperSpeechProviderError {
            expect(
                error == .processFailed(exitCode: 2, message: "invalid model"),
                "Unexpected process failure: \(error)"
            )
        } catch {
            fatalError("Unexpected error type: \(error)")
        }
    }

    private static func testFactoryRejectsMissingRuntimeAndModel() {
        let unavailable = LocalWhisperRuntimeStatus(
            architecture: .appleSilicon,
            executableURL: nil,
            executableIsRunnable: false,
            metalIsExpected: true
        )

        do {
            _ = try SpeechProviderFactory.makeLocalProvider(
                runtimeStatus: unavailable,
                modelURL: nil,
                language: nil
            )
            fatalError("Expected missing runtime error")
        } catch let error as SpeechProviderFactory.FactoryError {
            expect(error == .localRuntimeUnavailable, "Unexpected runtime error: \(error)")
        } catch {
            fatalError("Unexpected error type: \(error)")
        }
    }

    private static func expectEqual(_ actual: String?, _ expected: String) {
        expect(actual == expected, "Expected \(expected.debugDescription), got \((actual ?? "nil").debugDescription)")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}

private final class FakeProcessRunner: LocalWhisperProcessRunning, @unchecked Sendable {
    private let result: LocalWhisperProcessResult
    private(set) var arguments: [String] = []

    init(result: LocalWhisperProcessResult) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> LocalWhisperProcessResult {
        self.arguments = arguments
        return result
    }
}

private struct Fixture {
    let directoryURL: URL
    let executableURL: URL
    let modelURL: URL
    let audioURL: URL

    init() throws {
        let fileManager = FileManager.default
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalWhisperTests-\(UUID().uuidString)", isDirectory: true)
        executableURL = directoryURL.appendingPathComponent("whisper-cli")
        modelURL = directoryURL.appendingPathComponent("model.bin")
        audioURL = directoryURL.appendingPathComponent("audio.wav")

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try Data("model".utf8).write(to: modelURL)
        try Data("audio".utf8).write(to: audioURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

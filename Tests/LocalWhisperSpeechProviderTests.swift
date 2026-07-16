import Foundation

@main
struct LocalWhisperSpeechProviderTests {
    static func main() async {
        testTranscriptCleanup()
        await testProviderBuildsArgumentsAndReturnsTranscript()
        await testProviderPropagatesProcessFailure()
        testFactoryRejectsMissingRuntimeAndModel()
        testCatalogExposesVerifiedModelsOnly()
        testRuntimeDetectorSkipsNonExecutableCandidate()
        await testModelManagerRejectsUnsafeFileNames()
        await testModelManagerInstallsVerifiedDownload()
        print("LocalWhisperSpeechProviderTests passed")
    }

    private static func testTranscriptCleanup() {
        let output = """
        [00:00:00.000 --> 00:00:01.000]
        Ahoj světe.

        [literal bracketed speech]
        Toto je test.
        """
        expectEqual(
            LocalWhisperSpeechProvider.cleanedTranscript(from: output),
            "Ahoj světe. [literal bracketed speech] Toto je test."
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
        expect(runner.arguments.contains("--no-prints"), "CLI logging suppression is missing")
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

    private static func testCatalogExposesVerifiedModelsOnly() {
        expect(
            LocalWhisperModelCatalog.entry(id: "tiny")?.descriptor?.sha256
                == "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            "Tiny should expose the pinned checksum"
        )
        expect(
            LocalWhisperModelCatalog.entry(id: "base")?.descriptor?.sha256
                == "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            "Base should expose the pinned checksum"
        )
        expect(LocalWhisperModelCatalog.entry(id: "small")?.descriptor == nil, "Small must remain locked")
    }

    private static func testRuntimeDetectorSkipsNonExecutableCandidate() {
        let fixture = try! Fixture()
        defer { fixture.cleanup() }

        let nonExecutable = fixture.directoryURL.appendingPathComponent("not-runnable")
        let bundled = fixture.directoryURL.appendingPathComponent("bundled-whisper-cli")
        let manifestURL = fixture.directoryURL.appendingPathComponent("whisper-runtime.json")
        try! Data().write(to: nonExecutable)
        try! Data("#!/bin/sh\n".utf8).write(to: bundled)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
        try! Data(runtimeManifestJSON.utf8).write(to: manifestURL)

        let status = LocalWhisperRuntimeDetector(
            bundledExecutableURL: bundled,
            bundledManifestURL: manifestURL,
            customExecutableURL: nonExecutable,
            commonExecutableURLs: []
        ).detect()
        expect(status.executableURL == bundled, "Detector should continue after a non-runnable custom path")
        expect(status.isReady, "Runnable bundled executable should be ready")
        expect(status.source == .bundled, "Bundled executable source was not preserved")
        expect(status.manifest?.version == "1.9.1", "Bundled runtime manifest was not loaded")
        expect(
            status.manifest?.commit == "f049fff95a089aa9969deb009cdd4892b3e74916",
            "Bundled runtime commit was not loaded"
        )
    }

    private static var runtimeManifestJSON: String {
        """
        {
          "schemaVersion": 1,
          "name": "whisper.cpp",
          "version": "1.9.1",
          "commit": "f049fff95a089aa9969deb009cdd4892b3e74916",
          "sourceRepository": "https://github.com/ggml-org/whisper.cpp.git",
          "architectures": ["arm64", "x86_64"],
          "minimumMacOSVersion": "13.0",
          "sharedLibraries": false,
          "metalEnabled": true,
          "metalLibraryEmbedded": true,
          "nativeOptimizations": false
        }
        """
    }

    private static func testModelManagerRejectsUnsafeFileNames() async {
        let fixture = try! Fixture()
        defer { fixture.cleanup() }
        let manager = try! LocalWhisperModelManager(modelsDirectory: fixture.directoryURL)
        let descriptor = LocalWhisperModelDescriptor(
            id: "unsafe",
            displayName: "Unsafe",
            fileName: "..",
            downloadURL: URL(string: "https://example.invalid/model.bin")!,
            sha256: String(repeating: "0", count: 64),
            approximateSizeBytes: 1
        )

        do {
            _ = try await manager.modelURL(for: descriptor)
            fatalError("Expected invalid model identifier")
        } catch LocalWhisperModelManagerError.invalidModelIdentifier {
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }

    private static func testModelManagerInstallsVerifiedDownload() async {
        let fixture = try! Fixture()
        defer { fixture.cleanup() }

        let modelsDirectory = fixture.directoryURL.appendingPathComponent("models", isDirectory: true)
        let downloadedURL = fixture.directoryURL.appendingPathComponent("verified-download.bin")
        try! Data("verified-model".utf8).write(to: downloadedURL)
        let checksum = try! LocalWhisperModelManager.sha256(of: downloadedURL)
        let manager = try! LocalWhisperModelManager(
            modelsDirectory: modelsDirectory,
            downloader: { _, progress in
                progress(0.5)
                return downloadedURL
            }
        )
        let descriptor = LocalWhisperModelDescriptor(
            id: "verified",
            displayName: "Verified",
            fileName: "verified.bin",
            downloadURL: URL(string: "https://example.invalid/verified.bin")!,
            sha256: checksum,
            approximateSizeBytes: 14
        )

        let installState = await manager.install(descriptor)
        guard case let .ready(installedURL) = installState else {
            fatalError("Expected verified model installation, got \(installState)")
        }
        expect(FileManager.default.isReadableFile(atPath: installedURL.path), "Installed model is not readable")
        let state = await manager.state(for: descriptor)
        guard case .ready = state else {
            fatalError("Expected ready state after installation, got \(state)")
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

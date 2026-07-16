import Foundation

/// Snapshot of the local whisper.cpp execution environment.
struct LocalWhisperRuntimeStatus: Equatable, Sendable {
    enum Architecture: String, Sendable {
        case appleSilicon
        case intel
        case unsupported
    }

    let architecture: Architecture
    let executableURL: URL?
    let executableIsRunnable: Bool
    let metalIsExpected: Bool

    var isReady: Bool {
        executableURL != nil && executableIsRunnable
    }
}

/// Detects whether FreeFlow can launch a local whisper.cpp binary.
struct LocalWhisperRuntimeDetector {
    private let fileManager: FileManager
    private let bundledExecutableURL: URL?
    private let customExecutableURL: URL?

    init(
        fileManager: FileManager = .default,
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
        customExecutableURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bundledExecutableURL = bundledExecutableURL
        self.customExecutableURL = customExecutableURL
    }

    func detect() -> LocalWhisperRuntimeStatus {
        let executableURL = [customExecutableURL, bundledExecutableURL]
            .compactMap { $0 }
            .first(where: { fileManager.fileExists(atPath: $0.path) })

        let runnable = executableURL.map {
            fileManager.isExecutableFile(atPath: $0.path)
        } ?? false

        return LocalWhisperRuntimeStatus(
            architecture: Self.currentArchitecture,
            executableURL: executableURL,
            executableIsRunnable: runnable,
            metalIsExpected: Self.currentArchitecture == .appleSilicon
        )
    }

    static var currentArchitecture: LocalWhisperRuntimeStatus.Architecture {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        return .intel
        #else
        return .unsupported
        #endif
    }
}

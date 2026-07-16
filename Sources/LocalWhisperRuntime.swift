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
        architecture != .unsupported && executableURL != nil && executableIsRunnable
    }
}

/// Detects whether FreeFlow can launch a local whisper.cpp binary.
struct LocalWhisperRuntimeDetector {
    private let fileManager: FileManager
    private let bundledExecutableURL: URL?
    private let customExecutableURL: URL?
    private let commonExecutableURLs: [URL]

    init(
        fileManager: FileManager = .default,
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
        customExecutableURL: URL? = nil,
        commonExecutableURLs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ]
    ) {
        self.fileManager = fileManager
        self.bundledExecutableURL = bundledExecutableURL
        self.customExecutableURL = customExecutableURL
        self.commonExecutableURLs = commonExecutableURLs
    }

    func detect() -> LocalWhisperRuntimeStatus {
        let executableURL = ([customExecutableURL, bundledExecutableURL].compactMap { $0 } + commonExecutableURLs)
            .first(where: {
                fileManager.fileExists(atPath: $0.path)
                    && fileManager.isExecutableFile(atPath: $0.path)
            })

        return LocalWhisperRuntimeStatus(
            architecture: Self.currentArchitecture,
            executableURL: executableURL,
            executableIsRunnable: executableURL != nil,
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

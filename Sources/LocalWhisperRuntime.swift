import Foundation

struct LocalWhisperRuntimeManifest: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let name: String
    let version: String
    let commit: String
    let sourceRepository: String
    let architectures: [String]
    let minimumMacOSVersion: String
    let sharedLibraries: Bool
    let metalEnabled: Bool
    let metalLibraryEmbedded: Bool
    let nativeOptimizations: Bool

    static func load(from url: URL?) -> LocalWhisperRuntimeManifest? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LocalWhisperRuntimeManifest.self, from: data),
              manifest.schemaVersion == 1,
              manifest.name == "whisper.cpp" else {
            return nil
        }
        return manifest
    }
}

/// Snapshot of the local whisper.cpp execution environment.
struct LocalWhisperRuntimeStatus: Equatable, Sendable {
    enum Architecture: String, Sendable {
        case appleSilicon
        case intel
        case unsupported
    }

    enum Source: String, Sendable {
        case custom
        case bundled
        case homebrew
        case system
    }

    let architecture: Architecture
    let executableURL: URL?
    let executableIsRunnable: Bool
    let metalIsExpected: Bool
    let source: Source?
    let manifest: LocalWhisperRuntimeManifest?

    init(
        architecture: Architecture,
        executableURL: URL?,
        executableIsRunnable: Bool,
        metalIsExpected: Bool,
        source: Source? = nil,
        manifest: LocalWhisperRuntimeManifest? = nil
    ) {
        self.architecture = architecture
        self.executableURL = executableURL
        self.executableIsRunnable = executableIsRunnable
        self.metalIsExpected = metalIsExpected
        self.source = source
        self.manifest = manifest
    }

    var isReady: Bool {
        architecture != .unsupported && executableURL != nil && executableIsRunnable
    }
}

/// Detects whether FreeFlow can launch a local whisper.cpp binary.
struct LocalWhisperRuntimeDetector {
    private struct Candidate {
        let url: URL
        let source: LocalWhisperRuntimeStatus.Source
    }

    private let fileManager: FileManager
    private let bundledExecutableURL: URL?
    private let bundledManifestURL: URL?
    private let customExecutableURL: URL?
    private let commonExecutableURLs: [URL]

    init(
        fileManager: FileManager = .default,
        bundledExecutableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "whisper-cli")
            ?? Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
        bundledManifestURL: URL? = Bundle.main.url(forResource: "whisper-runtime", withExtension: "json"),
        customExecutableURL: URL? = nil,
        commonExecutableURLs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ]
    ) {
        self.fileManager = fileManager
        self.bundledExecutableURL = bundledExecutableURL
        self.bundledManifestURL = bundledManifestURL
        self.customExecutableURL = customExecutableURL
        self.commonExecutableURLs = commonExecutableURLs
    }

    func detect() -> LocalWhisperRuntimeStatus {
        var candidates: [Candidate] = []
        if let customExecutableURL {
            candidates.append(Candidate(url: customExecutableURL, source: .custom))
        }
        if let bundledExecutableURL {
            candidates.append(Candidate(url: bundledExecutableURL, source: .bundled))
        }
        candidates.append(contentsOf: commonExecutableURLs.map { url in
            let source: LocalWhisperRuntimeStatus.Source = url.path.hasPrefix("/opt/homebrew/")
                ? .homebrew
                : .system
            return Candidate(url: url, source: source)
        })

        let selectedCandidate = candidates.first(where: {
            fileManager.fileExists(atPath: $0.url.path)
                && fileManager.isExecutableFile(atPath: $0.url.path)
        })
        let source = selectedCandidate?.source
        let manifest = source == .bundled
            ? LocalWhisperRuntimeManifest.load(from: bundledManifestURL)
            : nil

        return LocalWhisperRuntimeStatus(
            architecture: Self.currentArchitecture,
            executableURL: selectedCandidate?.url,
            executableIsRunnable: selectedCandidate != nil,
            metalIsExpected: Self.currentArchitecture == .appleSilicon,
            source: source,
            manifest: manifest
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

import CryptoKit
import Foundation

struct LocalWhisperModelDescriptor: Equatable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
    let sha256: String
    let approximateSizeBytes: Int64
}

enum LocalWhisperModelState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double?)
    case ready(URL)
    case invalidChecksum
    case failed(String)
}

enum LocalWhisperModelManagerError: LocalizedError {
    case invalidChecksum(expected: String, actual: String)
    case invalidModelIdentifier

    var errorDescription: String? {
        switch self {
        case let .invalidChecksum(expected, actual):
            return "Downloaded model checksum mismatch. Expected \(expected), got \(actual)."
        case .invalidModelIdentifier:
            return "The local Whisper model identifier is invalid."
        }
    }
}

/// Owns local model paths, installation, verification, and removal.
actor LocalWhisperModelManager {
    private let fileManager: FileManager
    private let modelsDirectory: URL
    private let downloader: @Sendable (URL) async throws -> URL

    init(
        fileManager: FileManager = .default,
        modelsDirectory: URL? = nil,
        downloader: @escaping @Sendable (URL) async throws -> URL = LocalWhisperModelManager.defaultDownload
    ) throws {
        self.fileManager = fileManager
        self.modelsDirectory = try modelsDirectory ?? Self.defaultModelsDirectory(fileManager: fileManager)
        self.downloader = downloader
        try fileManager.createDirectory(at: self.modelsDirectory, withIntermediateDirectories: true)
    }

    static func defaultModelsDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return applicationSupport
            .appendingPathComponent("FreeFlow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    func modelURL(for descriptor: LocalWhisperModelDescriptor) throws -> URL {
        guard !descriptor.id.isEmpty,
              !descriptor.fileName.isEmpty,
              descriptor.fileName == URL(fileURLWithPath: descriptor.fileName).lastPathComponent else {
            throw LocalWhisperModelManagerError.invalidModelIdentifier
        }
        return modelsDirectory.appendingPathComponent(descriptor.fileName, isDirectory: false)
    }

    func state(for descriptor: LocalWhisperModelDescriptor) async -> LocalWhisperModelState {
        do {
            let destination = try modelURL(for: descriptor)
            guard fileManager.fileExists(atPath: destination.path) else {
                return .notInstalled
            }

            let checksum = try Self.sha256(of: destination)
            return checksum.caseInsensitiveCompare(descriptor.sha256) == .orderedSame
                ? .ready(destination)
                : .invalidChecksum
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func install(_ descriptor: LocalWhisperModelDescriptor) async -> LocalWhisperModelState {
        do {
            let destination = try modelURL(for: descriptor)
            let temporaryURL = try await downloader(descriptor.downloadURL)
            let checksum = try Self.sha256(of: temporaryURL)

            guard checksum.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
                try? fileManager.removeItem(at: temporaryURL)
                throw LocalWhisperModelManagerError.invalidChecksum(
                    expected: descriptor.sha256,
                    actual: checksum
                )
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            return .ready(destination)
        } catch LocalWhisperModelManagerError.invalidChecksum {
            return .invalidChecksum
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func remove(_ descriptor: LocalWhisperModelDescriptor) async throws {
        let destination = try modelURL(for: descriptor)
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try fileManager.removeItem(at: destination)
    }

    static func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDownload(_ url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return temporaryURL
    }
}

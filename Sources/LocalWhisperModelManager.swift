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
    typealias ProgressHandler = @Sendable (Double?) -> Void
    typealias Downloader = @Sendable (URL, @escaping ProgressHandler) async throws -> URL

    private let fileManager: FileManager
    private let modelsDirectory: URL
    private let downloader: Downloader

    init(
        fileManager: FileManager = .default,
        modelsDirectory: URL? = nil,
        downloader: @escaping Downloader = LocalWhisperModelManager.defaultDownload
    ) throws {
        let resolvedDirectory: URL
        if let modelsDirectory {
            resolvedDirectory = modelsDirectory.standardizedFileURL
        } else {
            resolvedDirectory = try Self.defaultModelsDirectory(fileManager: fileManager).standardizedFileURL
        }

        self.fileManager = fileManager
        self.modelsDirectory = resolvedDirectory
        self.downloader = downloader
        try fileManager.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
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
        let fileName = descriptor.fileName
        guard !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              fileName == URL(fileURLWithPath: fileName).lastPathComponent else {
            throw LocalWhisperModelManagerError.invalidModelIdentifier
        }

        let destination = modelsDirectory
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
        guard destination.deletingLastPathComponent() == modelsDirectory else {
            throw LocalWhisperModelManagerError.invalidModelIdentifier
        }
        return destination
    }

    func state(for descriptor: LocalWhisperModelDescriptor) async -> LocalWhisperModelState {
        do {
            let destination = try modelURL(for: descriptor)
            guard fileManager.isReadableFile(atPath: destination.path) else {
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

    func install(
        _ descriptor: LocalWhisperModelDescriptor,
        progress: @escaping ProgressHandler = { _ in }
    ) async -> LocalWhisperModelState {
        progress(0)
        var temporaryURL: URL?
        var stagedURL: URL?
        defer {
            if let temporaryURL { try? fileManager.removeItem(at: temporaryURL) }
            if let stagedURL { try? fileManager.removeItem(at: stagedURL) }
        }

        do {
            let destination = try modelURL(for: descriptor)
            let downloadedURL = try await downloader(descriptor.downloadURL) { value in
                progress(value.map { min(max($0, 0), 1) })
            }
            temporaryURL = downloadedURL
            let checksum = try Self.sha256(of: downloadedURL)

            guard checksum.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
                throw LocalWhisperModelManagerError.invalidChecksum(
                    expected: descriptor.sha256,
                    actual: checksum
                )
            }

            let staged = modelsDirectory
                .appendingPathComponent(".\(descriptor.fileName).\(UUID().uuidString).partial")
            stagedURL = staged
            try fileManager.moveItem(at: downloadedURL, to: staged)
            temporaryURL = nil

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
            stagedURL = nil
            progress(1)
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
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func defaultDownload(
        _ url: URL,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        try await LocalWhisperDownloadClient.download(from: url, progress: progress)
    }
}

private final class LocalWhisperDownloadClient: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: LocalWhisperModelManager.ProgressHandler?
    private var session: URLSession?

    static func download(
        from url: URL,
        progress: @escaping LocalWhisperModelManager.ProgressHandler
    ) async throws -> URL {
        let client = LocalWhisperDownloadClient()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                client.lock.lock()
                client.continuation = continuation
                client.progress = progress
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 60 * 60
                let session = URLSession(configuration: configuration, delegate: client, delegateQueue: nil)
                client.session = session
                client.lock.unlock()
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            client.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(throwing: CancellationError())
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let value: Double? = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        lock.lock()
        let progress = self.progress
        lock.unlock()
        progress?(value)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }

        do {
            let retainedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("freeflow-whisper-\(UUID().uuidString).download")
            try FileManager.default.moveItem(at: location, to: retainedURL)
            finish(.success(retainedURL))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        self.progress = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

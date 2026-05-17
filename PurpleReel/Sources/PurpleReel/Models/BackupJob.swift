import Foundation

enum BackupFileState: Equatable {
    case queued
    case hashing(bytesRead: Int64)
    case copying
    case verifying(destination: URL)
    case done
    case failed(String)
}

@MainActor
final class BackupFileItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let relativePath: String
    let sizeBytes: Int64

    @Published var state: BackupFileState = .queued
    @Published var sourceHash: String?
    /// Map of destination root URL → resulting verified hash.
    @Published var destinationHashes: [URL: String] = [:]

    init(sourceURL: URL, relativePath: String, sizeBytes: Int64) {
        self.sourceURL = sourceURL
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
    }
}

@MainActor
final class BackupJob: ObservableObject, Identifiable {
    let id = UUID()
    let source: URL
    let destinations: [URL]
    let algorithm: HashAlgorithm

    @Published var items: [BackupFileItem] = []
    @Published var isRunning = false
    @Published var startedAt: Date?
    @Published var finishedAt: Date?
    @Published var summary: String = ""
    @Published var mhlPaths: [URL] = []

    init(source: URL, destinations: [URL], algorithm: HashAlgorithm) {
        self.source = source
        self.destinations = destinations
        self.algorithm = algorithm
    }
}

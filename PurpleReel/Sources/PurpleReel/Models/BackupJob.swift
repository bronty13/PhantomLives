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

/// MHL output format. Legacy = ASC Media Hash List v1.1 (the
/// long-standing DIT format, hex digests inside one `<hash>` per
/// file). ascMHL = ASC-MHL v2.0 (Netflix Originals requirement) —
/// supports C4 IDs alongside hex hashes and emits the v2.0 schema.
enum MHLFormat: String, CaseIterable, Identifiable, Codable {
    case legacy   = "MHL v1.1"
    case ascMHL   = "ASC-MHL v2.0"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .legacy: return "mhl"
        case .ascMHL: return "ascmhl"
        }
    }
}

@MainActor
final class BackupJob: ObservableObject, Identifiable {
    let id = UUID()
    let source: URL
    let destinations: [URL]
    let algorithm: HashAlgorithm
    let mhlFormat: MHLFormat

    @Published var items: [BackupFileItem] = []
    @Published var isRunning = false
    @Published var startedAt: Date?
    @Published var finishedAt: Date?
    @Published var summary: String = ""
    @Published var mhlPaths: [URL] = []

    init(source: URL, destinations: [URL],
         algorithm: HashAlgorithm,
         mhlFormat: MHLFormat = .legacy) {
        self.source = source
        self.destinations = destinations
        self.algorithm = algorithm
        self.mhlFormat = mhlFormat
    }
}

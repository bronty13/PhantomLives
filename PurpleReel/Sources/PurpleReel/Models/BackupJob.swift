import Foundation

enum BackupFileState: Equatable {
    case queued
    case hashing(bytesRead: Int64)
    case copying
    case verifying(destination: URL)
    case done
    case failed(String)
    /// C37 — set when the user cancelled the run before this file
    /// got processed. Distinct from `.failed` so the summary alert
    /// can report "X cancelled, Y verified" separately.
    case cancelled
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
    /// C37 — cancel flag checked at the top of each per-file loop
    /// iteration inside `VerifiedBackupService.run(...)`. Set by
    /// `cancel()`; the run terminates between files (after the
    /// current file's hash + copy + verify completes) rather than
    /// mid-bytestream. That's the right granularity — a partial
    /// copy on the destination would be invalid anyway, so we let
    /// the in-flight file finish so it's either fully verified or
    /// not started.
    @Published private(set) var isCancelled = false

    init(source: URL, destinations: [URL],
         algorithm: HashAlgorithm,
         mhlFormat: MHLFormat = .legacy) {
        self.source = source
        self.destinations = destinations
        self.algorithm = algorithm
        self.mhlFormat = mhlFormat
    }

    /// C37 — user-triggered cancel. `VerifiedBackupService.run(...)`
    /// checks `isCancelled` between files; the WorkflowChainRun
    /// propagates this through to its active backup step so a chain-
    /// level cancel actually stops mid-backup (was step-boundary-
    /// only pre-C37).
    @MainActor
    func cancel() {
        isCancelled = true
    }
}

import Foundation

/// A progress snapshot emitted during extraction or creation. The GUI binds
/// these to a progress bar; the CLI renders a TTY line.
public struct ArchiveProgress: Sendable {
    public let entriesDone: Int
    public let entriesTotal: Int?     // nil when unknown (streaming, pre-scan skipped)
    public let bytesDone: Int64
    public let currentName: String

    public var fraction: Double? {
        guard let total = entriesTotal, total > 0 else { return nil }
        return min(1.0, Double(entriesDone) / Double(total))
    }
}

/// Caller hooks for long-running engine operations. Both are optional and must
/// be safe to call from a background thread.
public struct ProgressSink: Sendable {
    public var onProgress: (@Sendable (ArchiveProgress) -> Void)?
    public var isCancelled: (@Sendable () -> Bool)?

    public init(onProgress: (@Sendable (ArchiveProgress) -> Void)? = nil,
                isCancelled: (@Sendable () -> Bool)? = nil) {
        self.onProgress = onProgress
        self.isCancelled = isCancelled
    }

    public static let none = ProgressSink()

    func cancelled() -> Bool { isCancelled?() ?? false }
    func report(_ p: ArchiveProgress) { onProgress?(p) }
}

/// Thrown when the caller cancels mid-operation.
public struct CancelledError: Error {}

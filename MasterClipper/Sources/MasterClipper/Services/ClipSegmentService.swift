import Foundation
import MasterClipperCore

/// Captures `ClipSegment` rows for a clip's source folder. Walks the folder
/// in chronological order via `VideoFolderService`, computes MD5/SHA-1/SHA-256
/// for each `.mov` (single streaming pass through `HashService`), and writes
/// the rows back to the database in one transaction.
///
/// Hashing is potentially long-running for big files, so the public capture
/// API is `async` and exposes a per-file progress callback so the workflow
/// sheet can render `Hashing 3 of 12…` while it runs.
@MainActor
enum ClipSegmentService {

    /// Per-file capture-time error. Propagated up so the caller can decide
    /// whether to keep going (the workflow always finishes the others — one
    /// unreadable file shouldn't lose hashes for the rest).
    struct CaptureFailure: Equatable {
        let filename: String
        let message: String
    }

    /// Result of a capture pass. `segments` holds every row that succeeded
    /// (already persisted in DB); `failures` lists files that failed to hash.
    struct CaptureResult {
        let segments: [ClipSegment]
        let failures: [CaptureFailure]
    }

    /// Hash every `.mov` directly inside `folder`, build a `ClipSegment` row
    /// per file, and replace the clip's segment set in one transaction.
    ///
    /// `progress(currentIndex, total, filename)` fires on the main actor
    /// before each file is hashed so the UI can render a "Hashing N/M …" line.
    /// The total is the file count after enumeration, so it's known up-front.
    static func captureAndPersist(
        folder: URL,
        clipId: String,
        progress: @MainActor @escaping (_ current: Int, _ total: Int, _ filename: String) -> Void
    ) async throws -> CaptureResult {
        let items = try VideoFolderService.enumerate(folder: folder)
        let total = items.count

        var rows: [ClipSegment] = []
        var failures: [CaptureFailure] = []

        for (idx, item) in items.enumerated() {
            await MainActor.run {
                progress(idx + 1, total, item.currentName)
            }
            do {
                let h = try await HashService.hash(filePath: item.url.path)
                rows.append(makeSegment(
                    item: item,
                    clipId: clipId,
                    hashes: h
                ))
            } catch {
                failures.append(CaptureFailure(
                    filename: item.currentName,
                    message: error.localizedDescription
                ))
                // Persist a metadata-only row so the segment is still
                // recorded — hashes stay empty, the editor can re-attempt.
                rows.append(makeSegment(
                    item: item,
                    clipId: clipId,
                    hashes: nil
                ))
            }
        }

        try DatabaseService.shared.replaceSegments(forClip: clipId, with: rows)
        // Re-pull so the caller has the persisted rows (with autoincrement IDs).
        let persisted = try DatabaseService.shared.fetchSegments(forClip: clipId)
        return CaptureResult(segments: persisted, failures: failures)
    }

    /// Builds a `ClipSegment` from a folder item + (optional) hash digest.
    /// Common spine for both the success path and the metadata-only fallback
    /// when a single file fails to hash.
    private static func makeSegment(
        item: VideoFolderService.Item,
        clipId: String,
        hashes: HashService.Hashes?
    ) -> ClipSegment {
        let now = DatabaseService.isoNow()
        return ClipSegment(
            id: nil,
            clipId: clipId,
            position: item.expectedPosition,
            filename: item.currentName,
            creationDate: item.creationDateString,
            sizeBytes: hashes?.sizeBytes,
            md5: hashes?.md5 ?? "",
            sha1: hashes?.sha1 ?? "",
            sha256: hashes?.sha256 ?? "",
            hashedAt: hashes == nil ? "" : now,
            createdAt: now,
            updatedAt: now
        )
    }
}

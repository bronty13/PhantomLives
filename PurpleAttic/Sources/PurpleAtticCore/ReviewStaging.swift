import Foundation

/// Copies the items that an **incremental** run newly added to the archive into a separate
/// "NEW PHOTOS TO REVIEW" folder, so just-arrived photos can be handed off (to keep) or
/// deleted after review — without disturbing the backup set. "New" = a file path that wasn't
/// in the archive before this run (a genuinely new photo); re-exported edits of existing
/// photos keep their path and aren't re-staged. Never runs on the first/baseline population
/// (when there's no prior snapshot to diff against) — that would duplicate the whole library.
public enum ReviewStaging {

    /// Relative file paths (recursive, regular files, hidden skipped) under `dir`, for the
    /// before/after diff. Empty when `dir` doesn't exist yet (→ baseline run → no staging).
    public static func snapshot(_ dir: String) -> Set<String> {
        let url = URL(fileURLWithPath: dir)
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var out = Set<String>()
        let prefix = url.standardizedFileURL.path + "/"
        for case let f as URL in en {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let full = f.standardizedFileURL.path
            out.insert(full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full)
        }
        return out
    }

    /// Paths present in `after` but not `before` — the files this run added.
    public static func newPaths(before: Set<String>, after: Set<String>) -> [String] {
        Array(after.subtracting(before)).sorted()
    }

    public struct StageResult: Sendable, Equatable {
        public let copied: Int
        public let failed: Int
        public let bytes: Int64
    }

    /// Copy each `relPaths` entry from `sourceDir/<rel>` to `<batchDir>/<subfolder>/<rel>`,
    /// preserving the dated archive structure and creating intermediate folders. Best-effort:
    /// a failed copy is counted, never thrown (review staging must never fail the archive).
    @discardableResult
    public static func copyNew(relPaths: [String], sourceDir: String,
                               batchDir: String, subfolder: String) -> StageResult {
        let fm = FileManager.default
        var copied = 0, failed = 0
        var bytes: Int64 = 0
        for rel in relPaths {
            let src = (sourceDir as NSString).appendingPathComponent(rel)
            let dstDir = (batchDir as NSString).appendingPathComponent(subfolder)
            let dst = (dstDir as NSString).appendingPathComponent(rel)
            do {
                try fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent,
                                       withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
                try fm.copyItem(atPath: src, toPath: dst)
                copied += 1
                if let sz = (try? fm.attributesOfItem(atPath: dst))?[.size] as? NSNumber {
                    bytes += sz.int64Value
                }
            } catch {
                failed += 1
            }
        }
        return StageResult(copied: copied, failed: failed, bytes: bytes)
    }
}

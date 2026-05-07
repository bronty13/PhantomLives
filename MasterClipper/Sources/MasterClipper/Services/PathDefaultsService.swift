import Foundation
import AppKit

/// Computes default Production / FCP folder paths for clips and runs the
/// one-time backfill that fills in those columns for every production clip
/// that doesn't already have them set.
///
/// Pattern placeholders:
///   `{date}`  → clip.contentDate or clip.goLiveDate (YYYY-MM-DD)
///   `{title}` → clip.title (filename-safe: `/` and `\` → `-`, trimmed)
@MainActor
enum PathDefaultsService {

    // MARK: - Compute a path for a single clip

    static func productionPath(for clip: Clip, settings: AppSettings) -> String? {
        compose(base: settings.defaultProductionBase,
                pattern: settings.defaultProductionPattern,
                clip: clip)
    }

    static func fcpPath(for clip: Clip, settings: AppSettings) -> String? {
        compose(base: settings.defaultFCPBase,
                pattern: settings.defaultFCPPattern,
                clip: clip)
    }

    private static func compose(base: String, pattern: String, clip: Clip) -> String? {
        let trimmedBase = base.trimmingCharacters(in: .whitespaces)
        guard !trimmedBase.isEmpty else { return nil }
        guard let date = bestDate(for: clip), !date.isEmpty else { return nil }
        let title = sanitize(clip.title)
        let filled = pattern
            .replacingOccurrences(of: "{date}",  with: date)
            .replacingOccurrences(of: "{title}", with: title)
        let basePath = (trimmedBase as NSString).expandingTildeInPath
        return (basePath as NSString).appendingPathComponent(filled)
    }

    private static func bestDate(for clip: Clip) -> String? {
        if let d = clip.contentDate, !d.isEmpty { return d }
        if let d = clip.goLiveDate,  !d.isEmpty { return d }
        return nil
    }

    private static func sanitize(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/",  with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":",  with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Backfill

    struct BackfillResult {
        var productionFilled: Int = 0
        var fcpFilled: Int = 0
        var skipped: Int = 0
        var failed: Int = 0
    }

    /// Walk every active clip in `production` status and fill the
    /// `production_folder` / `fcp_project_folder` columns when they're empty,
    /// using the current settings defaults. Skips clips with no usable date.
    /// Idempotent — re-running with no new candidates is a no-op.
    @discardableResult
    static func backfill(appState: AppState) -> BackfillResult {
        var r = BackfillResult()
        for clip in appState.clips where !clip.archived && clip.statusEnum == .production {
            var mutated = clip
            var changed = false

            if (mutated.productionFolder ?? "").isEmpty {
                if let path = productionPath(for: clip, settings: appState.settings) {
                    mutated.productionFolder = path
                    r.productionFilled += 1
                    changed = true
                } else {
                    r.skipped += 1
                }
            }
            if (mutated.fcpProjectFolder ?? "").isEmpty {
                if let path = fcpPath(for: clip, settings: appState.settings) {
                    mutated.fcpProjectFolder = path
                    r.fcpFilled += 1
                    changed = true
                }
            }

            if changed {
                do {
                    try DatabaseService.shared.updateClip(mutated)
                } catch {
                    r.failed += 1
                }
            }
        }
        appState.reloadClips()
        return r
    }

    // MARK: - Re-stamp existing production folders to current pattern

    struct RestampResult {
        var matched: Int = 0          // clips whose stored path already matched
        var stamped: Int = 0          // clips whose folder was migrated successfully
        var filesCopied: Int = 0      // total per-clip files copied across all stamps
        var failed: [(clipId: String, reason: String)] = []
        var skippedNoFolder: Int = 0  // clips with empty productionFolder (nothing to migrate)
        var skippedNoExpected: Int = 0 // clips where current settings can't compute a path
    }

    /// Walk every active clip with a non-empty `production_folder` and, when
    /// the stored value doesn't match what the current settings pattern
    /// resolves to, migrate it:
    ///
    /// 1. `mkdir -p` the new (`<base>/<contentDate> <title>` by default) folder.
    /// 2. Copy every per-clip file from the old folder to the new one. A file
    ///    counts as per-clip when its name is exactly `<sanitizedTitle>.<ext>`
    ///    *or* starts with `<sanitizedTitle>_` (e.g. `Title.mp4`, `Title.png`,
    ///    `Title_reduced.mp4`, `Title_frame_07.png`). Anything else is left
    ///    behind so the OTHER clips that historically shared the old date-only
    ///    folder still find their files there.
    /// 3. Update `clip.production_folder` to the new path.
    ///
    /// Old folder is **never** deleted — it may still be referenced by other
    /// clips that haven't been migrated yet, or contain files that don't
    /// match the per-clip prefix. Re-stamping is idempotent; running with
    /// nothing-to-migrate is a no-op.
    @discardableResult
    static func restampOutOfPatternProductionFolders(appState: AppState) -> RestampResult {
        let fm = FileManager.default
        var r = RestampResult()

        for clip in appState.clips where !clip.archived {
            let current = (clip.productionFolder ?? "").trimmingCharacters(in: .whitespaces)
            guard !current.isEmpty else {
                r.skippedNoFolder += 1
                continue
            }
            guard let expected = productionPath(for: clip, settings: appState.settings) else {
                r.skippedNoExpected += 1
                continue
            }

            let currentExpanded = (current as NSString).expandingTildeInPath
                .precomposedStringWithCanonicalMapping
            let expectedExpanded = (expected as NSString).expandingTildeInPath
                .precomposedStringWithCanonicalMapping

            if currentExpanded == expectedExpanded {
                r.matched += 1
                continue
            }

            // mkdir -p new folder (idempotent — pre-existing is fine).
            do {
                try fm.createDirectory(atPath: expectedExpanded,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
            } catch {
                r.failed.append((clipId: clip.id,
                                 reason: "mkdir failed: \(error.localizedDescription)"))
                continue
            }

            // Copy per-clip files when the old folder is reachable. Skipped
            // silently when the old volume isn't mounted — the DB pointer
            // will be updated regardless so future audits look at the right
            // location once the user creates the canonical files there.
            let safeTitle = sanitize(clip.title)
            let copiedCount = copyPerClipFiles(
                from: currentExpanded,
                to: expectedExpanded,
                titleSanitized: safeTitle,
                fm: fm
            )
            r.filesCopied += copiedCount

            // Persist the new path on the clip.
            var mutated = clip
            mutated.productionFolder = expectedExpanded
            do {
                try DatabaseService.shared.updateClip(mutated)
                r.stamped += 1
            } catch {
                r.failed.append((clipId: clip.id,
                                 reason: "DB update failed: \(error.localizedDescription)"))
            }
        }

        appState.reloadClips()
        return r
    }

    /// Copy every file in `oldDir` whose name is `<title>.<ext>` or starts
    /// with `<title>_` into `newDir`. Files that already exist in `newDir`
    /// are skipped (we never overwrite). Returns the number of files
    /// actually copied.
    private static func copyPerClipFiles(
        from oldDir: String,
        to newDir: String,
        titleSanitized title: String,
        fm: FileManager
    ) -> Int {
        guard !title.isEmpty else { return 0 }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: oldDir, isDirectory: &isDir), isDir.boolValue else {
            return 0
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: oldDir) else {
            return 0
        }
        var copied = 0
        for name in entries {
            // Match either `<title>.<anything>` or `<title>_<anything>`. Hard
            // boundary on `.` / `_` so "Foo" doesn't catch "Foo Bar.mp4".
            let nfc = name.precomposedStringWithCanonicalMapping
            let titleNFC = title.precomposedStringWithCanonicalMapping
            let exact = nfc == titleNFC
            let dotted  = nfc.hasPrefix(titleNFC + ".")
            let undered = nfc.hasPrefix(titleNFC + "_")
            guard exact || dotted || undered else { continue }

            let src = (oldDir as NSString).appendingPathComponent(name)
            let dst = (newDir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: dst) { continue }
            do {
                try fm.copyItem(atPath: src, toPath: dst)
                copied += 1
            } catch {
                // Best-effort — keep walking so partial failures don't lose
                // the other matched files.
                continue
            }
        }
        return copied
    }

    // MARK: - Reveal helper

    /// Opens the given path in Finder. Falls back to revealing the deepest
    /// existing parent if the leaf doesn't exist yet (so e.g. an unconfigured
    /// production folder still surfaces the parent directory).
    static func revealInFinder(_ path: String?) {
        guard let p = path?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return }
        let expanded = (p as NSString).expandingTildeInPath
        let fm = FileManager.default
        if fm.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
            return
        }
        // Walk up to the deepest existing ancestor.
        var current = (expanded as NSString)
        while current.length > 1 {
            let parent = current.deletingLastPathComponent
            if fm.fileExists(atPath: parent) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: parent)])
                return
            }
            current = parent as NSString
        }
        // Final fallback — open Finder at the user's home dir.
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: NSHomeDirectory())
        ])
    }
}

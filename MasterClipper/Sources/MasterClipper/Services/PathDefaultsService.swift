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

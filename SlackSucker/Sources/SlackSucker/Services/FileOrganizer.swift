import Foundation

/// Post-process a completed slackdump archive folder by sorting
/// `__uploads/<FILE_ID>/<name>` attachments into media-category
/// subdirectories at the run-folder root.
///
/// Resulting layout:
///
///     <RunFolder>/
///     ├── slackdump.sqlite        (untouched)
///     ├── archive.log             (slackdump stdout)
///     ├── organize-log.txt        (this service's summary)
///     ├── Videos/<file>
///     ├── Photos/<file>
///     ├── Audio/<file>
///     └── Other/<file>
///
/// `__avatars/` (user profile thumbnails) is intentionally left in
/// place — those aren't user-shared content, just identicons, and
/// dropping them in `Photos/` would pollute the gallery view a user
/// of this feature is probably aiming for.
///
/// The service never deletes files — only moves them. On collision it
/// renames the incoming file with a `(<FILE_ID>)` suffix instead of
/// overwriting.
enum FileOrganizer {

    enum Category: String, CaseIterable {
        case videos = "Videos"
        case photos = "Photos"
        case audio  = "Audio"
        case other  = "Other"

        /// Conservative-by-design: only widely-recognised extensions
        /// land in the three media buckets; anything unknown (PDFs,
        /// docs, archives, snippets, transcripts) goes to `Other`.
        static let videoExts: Set<String> = [
            "mp4","mov","m4v","avi","mkv","webm","wmv","flv","mpg","mpeg","3gp","ts"
        ]
        static let photoExts: Set<String> = [
            "jpg","jpeg","png","gif","heic","heif","webp","bmp","tiff","tif","svg","avif"
        ]
        static let audioExts: Set<String> = [
            "mp3","m4a","wav","ogg","flac","aac","wma","aiff","aif","opus","amr"
        ]

        static func classify(extension ext: String) -> Category {
            let lower = ext.lowercased()
            if videoExts.contains(lower) { return .videos }
            if photoExts.contains(lower) { return .photos }
            if audioExts.contains(lower) { return .audio }
            return .other
        }
    }

    struct Result: Equatable {
        var moved: [String: Int] = [:]   // category name → count
        var collisions: Int = 0
        var errors: [String] = []

        var totalMoved: Int { moved.values.reduce(0, +) }
    }

    /// Move every file in `__uploads/<ID>/<name>` to
    /// `<RunFolder>/<Category>/<name>`. Removes the now-empty
    /// `__uploads` tree. No-op when `__uploads` doesn't exist.
    ///
    /// Idempotent: re-running on an already-organized folder is safe
    /// (the `__uploads` directory will have been deleted on the first
    /// pass, so the second pass returns an empty Result).
    @discardableResult
    static func organize(runFolder: URL) -> Result {
        var result = Result()
        let fm = FileManager.default
        let uploadsDir = runFolder.appendingPathComponent("__uploads", isDirectory: true)
        guard fm.fileExists(atPath: uploadsDir.path) else { return result }

        let fileIDDirs = (try? fm.contentsOfDirectory(
            at: uploadsDir,
            includingPropertiesForKeys: [.isDirectoryKey])) ?? []

        for idDir in fileIDDirs {
            let isDir = (try? idDir.resourceValues(forKeys: [.isDirectoryKey])
                                  .isDirectory) ?? false
            guard isDir else { continue }
            let fileID = idDir.lastPathComponent

            let inner = (try? fm.contentsOfDirectory(
                at: idDir,
                includingPropertiesForKeys: nil)) ?? []
            for fileURL in inner {
                let ext = fileURL.pathExtension
                let category = Category.classify(extension: ext)
                let categoryDir = runFolder.appendingPathComponent(
                    category.rawValue, isDirectory: true)
                do {
                    try fm.createDirectory(at: categoryDir,
                                           withIntermediateDirectories: true)
                } catch {
                    result.errors.append("create \(category.rawValue)/: \(error.localizedDescription)")
                    continue
                }

                let originalName = fileURL.lastPathComponent
                var dest = categoryDir.appendingPathComponent(originalName)
                if fm.fileExists(atPath: dest.path) {
                    // Disambiguate with the Slack file-ID rather than a
                    // running counter — IDs are globally unique inside a
                    // workspace, so re-running won't double-suffix.
                    let base = (originalName as NSString).deletingPathExtension
                    let extPart = (originalName as NSString).pathExtension
                    let disambiguated = extPart.isEmpty
                        ? "\(base) (\(fileID))"
                        : "\(base) (\(fileID)).\(extPart)"
                    dest = categoryDir.appendingPathComponent(disambiguated)
                    result.collisions += 1
                }

                do {
                    try fm.moveItem(at: fileURL, to: dest)
                    result.moved[category.rawValue, default: 0] += 1
                } catch {
                    result.errors.append("\(originalName): \(error.localizedDescription)")
                }
            }
            // Clean up the file-ID dir if everything moved out cleanly.
            // Leave it alone if files remain so the user can rerun and
            // see what got stranded.
            let remaining = (try? fm.contentsOfDirectory(at: idDir,
                                                        includingPropertiesForKeys: nil))?.count ?? 0
            if remaining == 0 {
                try? fm.removeItem(at: idDir)
            }
        }

        // Drop __uploads only if it's empty after the pass — same
        // principle: leave stranded files visible.
        let stragglers = (try? fm.contentsOfDirectory(at: uploadsDir,
                                                     includingPropertiesForKeys: nil))?.count ?? 0
        if stragglers == 0 {
            try? fm.removeItem(at: uploadsDir)
        }

        writeSummary(runFolder: runFolder, result: result)
        return result
    }

    /// Write a human-readable summary of the reorg into
    /// `<RunFolder>/organize-log.txt`. Non-fatal on write failure.
    private static func writeSummary(runFolder: URL, result: Result) {
        var lines: [String] = []
        lines.append("SlackSucker file-organization summary")
        lines.append("Run folder: \(runFolder.lastPathComponent)")
        lines.append("")
        for cat in Category.allCases {
            lines.append("\(cat.rawValue): \(result.moved[cat.rawValue] ?? 0)")
        }
        lines.append("")
        lines.append("Total files moved: \(result.totalMoved)")
        if result.collisions > 0 {
            lines.append("Filename collisions auto-renamed with file-ID suffix: \(result.collisions)")
        }
        if !result.errors.isEmpty {
            lines.append("")
            lines.append("Errors:")
            for e in result.errors { lines.append("  - \(e)") }
        }
        let logURL = runFolder.appendingPathComponent("organize-log.txt")
        try? lines.joined(separator: "\n").appending("\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
}

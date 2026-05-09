import Foundation

/// Reads a folder of `.mov` files, sorts them by macOS filesystem creation
/// time, and offers a one-shot "fix order" rename so the on-disk filenames
/// match the chronological order (1.mov, 2.mov, … N.mov).
///
/// Used by the new-clip workflow: the picked folder becomes the clip's FCP
/// project folder, and the user wants the videos renamed in shoot-order
/// before they start cutting.
@MainActor
enum VideoFolderService {

    /// One enumerated row in the folder.
    struct Item: Identifiable, Equatable {
        let id: URL                    // file URL doubles as identity
        let url: URL
        let currentName: String        // e.g. "3.mov" or "IMG_1234.mov"
        let creationDate: Date
        let creationDateString: String // max-precision display string
        let expectedPosition: Int      // 1-based position when sorted by ctime
        let expectedName: String       // e.g. "3.mov"
        let isOutOfOrder: Bool         // currentName != expectedName
    }

    /// Single rename step performed by `fixOrder`. Returned so the UI can
    /// surface "renamed N files" feedback or, on error, point to the row that
    /// failed.
    struct RenameStep: Equatable {
        let from: String
        let to: String
    }

    enum FolderError: LocalizedError {
        case notADirectory
        case unreadable(String)
        case renameCollision(String)
        case renameFailed(from: String, to: String, underlying: String)

        var errorDescription: String? {
            switch self {
            case .notADirectory:
                return "Selected path is not a folder."
            case .unreadable(let why):
                return "Could not read folder contents: \(why)"
            case .renameCollision(let name):
                return "A file named \(name) already exists in the folder."
            case .renameFailed(let from, let to, let why):
                return "Rename failed: \(from) → \(to) (\(why))"
            }
        }
    }

    // MARK: - Enumeration

    /// Returns every `.mov` file directly inside `folder`, sorted ascending by
    /// macOS filesystem creation date (`URLResourceKey.creationDateKey`).
    /// Hidden files and subfolders are ignored.
    static func enumerate(folder: URL) throws -> [Item] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderError.notADirectory
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .creationDateKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey,
                ],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw FolderError.unreadable(error.localizedDescription)
        }

        // Filter to .mov files (case-insensitive). The user's renaming target
        // is `<n>.mov`, so non-mov video extensions don't participate — keeps
        // the algorithm simple and predictable.
        let movs = urls.filter { $0.pathExtension.lowercased() == "mov" }

        // For each file we capture three pieces of data and derive an
        // "effective recording time":
        //
        //   - btime (URLResourceKey.creationDateKey) — APFS file birthtime.
        //   - mtime (contentModificationDateKey) — last write to the contents.
        //   - effective = min(btime, mtime) when both exist.
        //
        // Why min: the natural recording event sets btime ≈ mtime. After
        // that, copies / cloud sync / unzipping etc. tend to update btime to
        // "now" while preserving mtime (rsync, `cp -p`, Dropbox, AirDrop all
        // keep mtime). So min(btime, mtime) is a closer approximation of
        // "when the recording happened" than btime alone — and it agrees
        // with btime on never-touched files. File size is the secondary
        // tiebreaker (back-to-back recordings of different lengths sort
        // deterministically); filename is the final fallback.
        struct Row {
            let url: URL
            let btime: Date?
            let mtime: Date?
            let size: Int
            var effective: Date {
                switch (btime, mtime) {
                case let (b?, m?): return min(b, m)
                case let (b?, nil): return b
                case let (nil, m?): return m
                case (nil, nil):    return .distantPast
                }
            }
        }
        let rows: [Row] = movs.map { url in
            let v = try? url.resourceValues(forKeys: [
                .creationDateKey, .contentModificationDateKey, .fileSizeKey
            ])
            return Row(
                url: url,
                btime: v?.creationDate,
                mtime: v?.contentModificationDate,
                size: v?.fileSize ?? 0
            )
        }

        let sorted = rows.sorted { lhs, rhs in
            if lhs.effective != rhs.effective { return lhs.effective < rhs.effective }
            if lhs.size != rhs.size           { return lhs.size < rhs.size }
            return lhs.url.lastPathComponent
                .localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }

        return sorted.enumerated().map { (idx, row) in
            let pos = idx + 1
            let expected = "\(pos).mov"
            let currentName = row.url.lastPathComponent
            // Display the effective time (the value we actually sort on) so
            // the rename UI matches the rename order. Fall back to btime then
            // mtime then "—" if the file has neither.
            let displayDate = row.btime.map { min($0, row.mtime ?? $0) }
                ?? row.mtime
            let dateStr = displayDate.map(formatPrecise) ?? "—"
            return Item(
                id: row.url,
                url: row.url,
                currentName: currentName,
                creationDate: displayDate ?? .distantPast,
                creationDateString: dateStr,
                expectedPosition: pos,
                expectedName: expected,
                isOutOfOrder: currentName != expected
            )
        }
    }

    // MARK: - Rename to chronological order

    /// Rename every `.mov` in `folder` so its name matches its 1-based position
    /// when sorted by creation date (1.mov, 2.mov, …). Two-phase to avoid
    /// collisions when the new name belongs to another file in the same set:
    ///   1. Move every file to `__mc_tmp_<uuid>_<n>.mov`
    ///   2. Move it from there to `<n>.mov`
    /// Returns the list of (from → to) renames actually performed (i.e.
    /// rows that were already correctly named are skipped).
    @discardableResult
    static func fixOrder(folder: URL) throws -> [RenameStep] {
        let items = try enumerate(folder: folder)

        // Plan the desired final names from current order.
        struct Plan {
            let url: URL
            let originalName: String
            let tempURL: URL
            let finalURL: URL
        }
        let token = UUID().uuidString.prefix(8)
        let plans: [Plan] = items.map { item in
            let tmp = folder.appendingPathComponent(
                "__mc_tmp_\(token)_\(item.expectedPosition).mov"
            )
            let final = folder.appendingPathComponent(item.expectedName)
            return Plan(
                url: item.url,
                originalName: item.currentName,
                tempURL: tmp,
                finalURL: final
            )
        }

        // Defensive: if any planned `final` URL exists *and* doesn't belong to
        // a file in this rename set, bail before touching anything. Matches the
        // user's mental model — the folder should only contain numbered movs.
        let movedSet = Set(plans.map { $0.url.standardizedFileURL.path })
        let fm = FileManager.default
        for plan in plans {
            let finalPath = plan.finalURL.standardizedFileURL.path
            if fm.fileExists(atPath: finalPath), !movedSet.contains(finalPath) {
                throw FolderError.renameCollision(plan.finalURL.lastPathComponent)
            }
        }

        var performed: [RenameStep] = []

        // Phase 1: stage everything to temp names. Done unconditionally so
        // the second pass is collision-free even when files are merely
        // permuted (e.g. swap 1.mov ↔ 2.mov).
        for plan in plans {
            do {
                try fm.moveItem(at: plan.url, to: plan.tempURL)
            } catch {
                throw FolderError.renameFailed(
                    from: plan.originalName,
                    to: plan.tempURL.lastPathComponent,
                    underlying: error.localizedDescription
                )
            }
        }

        // Phase 2: temp → final. Skip recording a step when the final name
        // matched the original (it was already correctly numbered).
        for plan in plans {
            do {
                try fm.moveItem(at: plan.tempURL, to: plan.finalURL)
            } catch {
                throw FolderError.renameFailed(
                    from: plan.tempURL.lastPathComponent,
                    to: plan.finalURL.lastPathComponent,
                    underlying: error.localizedDescription
                )
            }
            if plan.originalName != plan.finalURL.lastPathComponent {
                performed.append(RenameStep(
                    from: plan.originalName,
                    to: plan.finalURL.lastPathComponent
                ))
            }
        }

        return performed
    }

    // MARK: - Formatting

    /// Formats a Date with microsecond precision and timezone offset, in the
    /// shape `2026-05-06 14:23:17.123456 +0000`. Mirrors the user's
    /// `mdls -name kMDItemFSCreationDate` workflow but with full sub-second
    /// resolution so files captured back-to-back are distinguishable.
    static func formatPrecise(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        let whole = floor(interval)
        let microseconds = Int(((interval - whole) * 1_000_000).rounded())
        let base = Date(timeIntervalSince1970: whole)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)

        let zoneFmt = DateFormatter()
        zoneFmt.locale = Locale(identifier: "en_US_POSIX")
        zoneFmt.dateFormat = "Z"
        zoneFmt.timeZone = TimeZone(secondsFromGMT: 0)

        return "\(fmt.string(from: base)).\(String(format: "%06d", microseconds)) \(zoneFmt.string(from: base))"
    }
}

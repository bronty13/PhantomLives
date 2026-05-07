import Foundation

/// Per-clip file audit. Verifies that the FCP/Production folders exist and
/// that the expected media files (`<Title>.mp4`, `<Title>_reduced.mp4`,
/// `<Title>.png`, `<Title>.fcpbundle`) are in place. Read-only — no file
/// operations or DB writes happen here. Phase 2 file handling (move,
/// re-encode, frame capture, hash, transcribe) builds on top of this.
///
/// Threshold semantics: when the main MP4 exceeds
/// `settings.largeFileThresholdMB`, the reduced variant is required;
/// otherwise it's optional (status `na` if absent, `ok` if present).
///
/// FCP folder absence is `warn`, not `missing`, because the external drive
/// may simply not be mounted at audit time — this is normal.
@MainActor
enum FileAuditService {

    enum CheckStatus: String {
        case ok        // present and as expected
        case warn      // present but suboptimal, OR absent in a non-fatal way (drive unmounted)
        case missing   // expected to exist but doesn't — user attention needed
        case na        // not applicable (e.g. reduced not required, or parent path missing)

        var label: String {
            switch self {
            case .ok:      return "OK"
            case .warn:    return "Warning"
            case .missing: return "Missing"
            case .na:      return "—"
            }
        }
    }

    /// A nearby file we believe is the intended one, just under a different
    /// name. Surfaced when the expected `<Title>.<ext>` doesn't exist but a
    /// best-effort scan of the parent directory turns up something that fits
    /// the file-type predicate. `alternatives` lists other candidates so the
    /// user can see they exist before accepting the suggestion.
    struct SuggestedRename {
        let parentDir: String
        let currentFilename: String
        let targetFilename: String
        let alternatives: [String]

        var fromPath: String { (parentDir as NSString).appendingPathComponent(currentFilename) }
        var toPath: String   { (parentDir as NSString).appendingPathComponent(targetFilename) }
    }

    struct Check: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let status: CheckStatus
        let path: String?
        let sizeBytes: Int64?
        let suggestedRename: SuggestedRename?

        init(label: String, detail: String, status: CheckStatus,
             path: String?, sizeBytes: Int64?, suggestedRename: SuggestedRename? = nil) {
            self.label = label
            self.detail = detail
            self.status = status
            self.path = path
            self.sizeBytes = sizeBytes
            self.suggestedRename = suggestedRename
        }

        var sizeFormatted: String? {
            guard let s = sizeBytes else { return nil }
            return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
        }
    }

    struct Result {
        var fcp: Check
        var production: Check
        var mp4: Check
        var reduced: Check
        var thumbnailFrames: Check
        var fcpBundle: Check
        /// Metadata check: clip has a refined description filled in.
        var description: Check
        /// Metadata check: clip has a whisper transcript stored.
        var transcript: Check
        /// Integrity check: MD5 / SHA-1 / SHA-256 fingerprints of the
        /// canonical MP4 pair are stored on the clip.
        var hashes: Check

        /// 1-based frame numbers actually present on disk. Drives the
        /// frame-picker stepper in the audit UI.
        var foundFrameNumbers: [Int]
        /// `numFramesToCapture` from settings — the expected upper bound.
        var expectedFrameCount: Int

        // Suggested values for `clipFilename` / `previewFilename` based on
        // what was actually found on disk. `thumbnailFilename` is now set
        // explicitly by the user via the frame picker, not derived here.
        var detectedClipFilename: String?
        var detectedPreviewFilename: String?

        /// Best candidate MP4 file found in the FCP folder when the
        /// production main MP4 is missing — fed to the "Push from FCP"
        /// pill so the user can move the rendered export into Production
        /// without leaving the audit.
        var fcpMp4Candidate: String?

        var allChecks: [Check] {
            [fcp, production, mp4, reduced, thumbnailFrames, fcpBundle, description, transcript, hashes]
        }
        var missingCount: Int  { allChecks.filter { $0.status == .missing }.count }
        var warnCount: Int     { allChecks.filter { $0.status == .warn }.count }
        var okCount: Int       { allChecks.filter { $0.status == .ok }.count }
        var hasIssues: Bool    { missingCount > 0 || warnCount > 0 }

        var renameSuggestions: [SuggestedRename] {
            allChecks.compactMap { $0.suggestedRename }
        }

        /// Are any of the suggested filenames different from what's currently
        /// stored on the clip? Drives the "Apply" button enable state.
        func hasNewDetections(against clip: Clip) -> Bool {
            (detectedClipFilename != nil   && detectedClipFilename   != clip.clipFilename) ||
            (detectedPreviewFilename != nil && detectedPreviewFilename != clip.previewFilename)
        }
    }

    static func audit(clip: Clip, settings: AppSettings) -> Result {
        let fm = FileManager.default
        let thresholdBytes = Int64(max(0, settings.largeFileThresholdMB)) * 1024 * 1024

        let fcpPath  = expand(clip.fcpProjectFolder)
        let prodPath = expand(clip.productionFolder)
        let title    = sanitizeTitle(clip.title)

        // 1 — FCP folder
        let fcpCheck: Check = {
            guard let p = fcpPath, !p.isEmpty else {
                return Check(label: "FCP project folder",
                             detail: "No FCP path set",
                             status: .warn, path: nil, sizeBytes: nil)
            }
            if isDirectory(p, fm: fm) {
                return Check(label: "FCP project folder",
                             detail: p,
                             status: .ok, path: p, sizeBytes: nil)
            }
            // Drive likely unmounted — warn, don't fail.
            return Check(label: "FCP project folder",
                         detail: "Not accessible — drive may be unmounted: \(p)",
                         status: .warn, path: p, sizeBytes: nil)
        }()

        // 2 — Production folder (must exist; missing is concerning)
        let prodCheck: Check = {
            guard let p = prodPath, !p.isEmpty else {
                return Check(label: "Production folder",
                             detail: "No production path set",
                             status: .missing, path: nil, sizeBytes: nil)
            }
            if isDirectory(p, fm: fm) {
                return Check(label: "Production folder",
                             detail: p,
                             status: .ok, path: p, sizeBytes: nil)
            }
            return Check(label: "Production folder",
                         detail: "Folder does not exist — possible typo: \(p)",
                         status: .missing, path: p, sizeBytes: nil)
        }()

        let canCheckProdFiles = prodCheck.status == .ok && !title.isEmpty

        // Pre-compute the reduced-file path/existence here so the main MP4
        // check can demote the "over threshold" warning to an OK when the
        // reduced companion is already in place. Reduced check itself runs
        // afterwards as before.
        let reducedFilename = title + "_reduced.mp4"
        let reducedFullPath = canCheckProdFiles
            ? prodPath.map { ($0 as NSString).appendingPathComponent(reducedFilename) }
            : nil
        let reducedExists = reducedFullPath.map { fm.fileExists(atPath: $0) } ?? false

        // 3 — Main MP4
        let mp4Filename = title + ".mp4"
        let mp4FullPath = canCheckProdFiles
            ? prodPath.map { ($0 as NSString).appendingPathComponent(mp4Filename) }
            : nil

        var mp4Check: Check
        var detectedClipFilename: String? = nil

        if !canCheckProdFiles {
            mp4Check = Check(label: "Main MP4 (Title.mp4)",
                             detail: title.isEmpty
                                ? "Clip has no title — set the title and re-audit"
                                : "Production folder unavailable",
                             status: .na, path: nil, sizeBytes: nil)
        } else if let fp = mp4FullPath, fm.fileExists(atPath: fp) {
            let size = fileSize(fp, fm: fm)
            detectedClipFilename = mp4Filename
            if let s = size, thresholdBytes > 0 && s > thresholdBytes {
                let formatted     = ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
                let thresholdStr  = ByteCountFormatter.string(fromByteCount: thresholdBytes, countStyle: .file)
                if reducedExists {
                    // Over threshold is fine when the reduced companion is
                    // already on disk — that's the whole point of having
                    // a `_reduced.mp4`.
                    mp4Check = Check(label: "Main MP4 (\(mp4Filename))",
                                     detail: "Over threshold (\(formatted) > \(thresholdStr)) — reduced version is in place",
                                     status: .ok, path: fp, sizeBytes: size)
                } else {
                    mp4Check = Check(label: "Main MP4 (\(mp4Filename))",
                                     detail: "Over threshold (\(formatted) > \(thresholdStr)) — needs a reduced version",
                                     status: .warn, path: fp, sizeBytes: size)
                }
            } else {
                mp4Check = Check(label: "Main MP4 (\(mp4Filename))",
                                 detail: "Present",
                                 status: .ok, path: fp, sizeBytes: size)
            }
        } else {
            // Try to find a similarly-named .mp4 (excluding *_reduced.mp4).
            let suggestion = prodPath.flatMap { dir in
                findRenameSuggestion(
                    parentDir: dir,
                    expected: mp4Filename,
                    predicate: { name in
                        let lower = name.lowercased()
                        return lower.hasSuffix(".mp4") && !lower.hasSuffix("_reduced.mp4")
                    },
                    fm: fm
                )
            }
            let detail = suggestion.map { "Missing — found similar: \($0.currentFilename)" }
                ?? "Missing in production folder"
            mp4Check = Check(label: "Main MP4 (\(mp4Filename))",
                             detail: detail,
                             status: .missing, path: mp4FullPath, sizeBytes: nil,
                             suggestedRename: suggestion)
        }

        // 4 — Reduced MP4 (required only when main is over threshold)
        // `reducedFilename` / `reducedFullPath` are declared above so the
        // main-MP4 check can demote-to-OK when the reduced is in place.
        let mainOverThreshold = (mp4Check.sizeBytes ?? 0) > thresholdBytes && thresholdBytes > 0

        var reducedCheck: Check
        var detectedPreviewFilename: String? = nil

        if !canCheckProdFiles {
            reducedCheck = Check(label: "Reduced MP4 (Title_reduced.mp4)",
                                 detail: "Production folder unavailable",
                                 status: .na, path: nil, sizeBytes: nil)
        } else if !mainOverThreshold {
            // Not required — but surface it if it happens to be there.
            if let fp = reducedFullPath, fm.fileExists(atPath: fp) {
                let size = fileSize(fp, fm: fm)
                detectedPreviewFilename = reducedFilename
                reducedCheck = Check(label: "Reduced MP4 (\(reducedFilename))",
                                     detail: "Present (not required — main MP4 is under threshold)",
                                     status: .ok, path: fp, sizeBytes: size)
            } else {
                reducedCheck = Check(label: "Reduced MP4 (\(reducedFilename))",
                                     detail: "Not required — main MP4 is under threshold",
                                     status: .na, path: nil, sizeBytes: nil)
            }
        } else if let fp = reducedFullPath, fm.fileExists(atPath: fp) {
            let size = fileSize(fp, fm: fm)
            detectedPreviewFilename = reducedFilename
            reducedCheck = Check(label: "Reduced MP4 (\(reducedFilename))",
                                 detail: "Present",
                                 status: .ok, path: fp, sizeBytes: size)
        } else {
            let suggestion = prodPath.flatMap { dir in
                findRenameSuggestion(
                    parentDir: dir,
                    expected: reducedFilename,
                    predicate: { $0.lowercased().hasSuffix("_reduced.mp4") },
                    fm: fm
                )
            }
            let detail = suggestion.map { "Required, missing — found similar: \($0.currentFilename)" }
                ?? "Required (main is over threshold) but missing"
            reducedCheck = Check(label: "Reduced MP4 (\(reducedFilename))",
                                 detail: detail,
                                 status: .missing, path: reducedFullPath, sizeBytes: nil,
                                 suggestedRename: suggestion)
        }

        // 5 — Thumbnail frames. We scan the production folder for
        // `<Title>_frame_NN.png` files and report how many we found vs how
        // many we expected (settings.numFramesToCapture). The user picks
        // which frame number is the canonical thumbnail via the audit UI;
        // that filename ends up on `clip.thumbnailFilename`.
        let expectedFrameCount = max(1, settings.numFramesToCapture)
        var foundFrameNumbers: [Int] = []
        if canCheckProdFiles, let dir = prodPath {
            foundFrameNumbers = findFrameNumbers(parentDir: dir, title: title, fm: fm)
        }

        let thumbnailFramesCheck: Check = {
            if !canCheckProdFiles {
                return Check(label: "Thumbnail frames (Title_frame_NN.png)",
                             detail: title.isEmpty
                                ? "Clip has no title — set the title and re-audit"
                                : "Production folder unavailable",
                             status: .na, path: nil, sizeBytes: nil)
            }
            let countFound = foundFrameNumbers.count
            // Path on the row points to whichever frame the clip currently
            // has selected (so Reveal opens *that* file). Fallback is the
            // first found frame, so Reveal still does something useful.
            let revealPath: String? = {
                if let chosen = clip.thumbnailFilename, !chosen.isEmpty,
                   let dir = prodPath {
                    let p = (dir as NSString).appendingPathComponent(chosen)
                    if fm.fileExists(atPath: p) { return p }
                }
                if let firstN = foundFrameNumbers.first, let dir = prodPath {
                    let name = String(format: "%@_frame_%02d.png", title, firstN)
                    let p = (dir as NSString).appendingPathComponent(name)
                    if fm.fileExists(atPath: p) { return p }
                }
                return nil
            }()

            if countFound == 0 {
                return Check(label: "Thumbnail frames",
                             detail: "No `<Title>_frame_NN.png` files in the production folder — capture them via the audit workflow.",
                             status: .missing, path: nil, sizeBytes: nil)
            }
            if countFound < expectedFrameCount {
                return Check(label: "Thumbnail frames",
                             detail: "\(countFound) of \(expectedFrameCount) captured. Re-run capture to fill the gaps.",
                             status: .warn, path: revealPath, sizeBytes: nil)
            }
            return Check(label: "Thumbnail frames",
                         detail: "\(countFound) of \(expectedFrameCount) captured. Pick which frame is the canonical thumbnail below.",
                         status: .ok, path: revealPath, sizeBytes: nil)
        }()

        // 6 — FCP bundle
        let fcpBundleFilename = title + ".fcpbundle"
        let fcpBundleFullPath = (fcpPath != nil && !title.isEmpty)
            ? ((fcpPath! as NSString).appendingPathComponent(fcpBundleFilename))
            : nil

        let fcpBundleCheck: Check = {
            if title.isEmpty {
                return Check(label: "FCP bundle (Title.fcpbundle)",
                             detail: "Clip has no title — set the title and re-audit",
                             status: .na, path: nil, sizeBytes: nil)
            }
            guard let path = fcpBundleFullPath else {
                return Check(label: "FCP bundle (\(fcpBundleFilename))",
                             detail: "No FCP path set",
                             status: .warn, path: nil, sizeBytes: nil)
            }
            // If the FCP folder itself isn't reachable, can't say more.
            if fcpCheck.status == .warn {
                return Check(label: "FCP bundle (\(fcpBundleFilename))",
                             detail: "Skipped — FCP folder not accessible",
                             status: .warn, path: path, sizeBytes: nil)
            }
            if fm.fileExists(atPath: path) {
                return Check(label: "FCP bundle (\(fcpBundleFilename))",
                             detail: "Present",
                             status: .ok, path: path, sizeBytes: nil)
            }
            let suggestion = findRenameSuggestion(
                parentDir: fcpPath!,
                expected: fcpBundleFilename,
                predicate: { $0.lowercased().hasSuffix(".fcpbundle") },
                fm: fm
            )
            let detail = suggestion.map { "Missing — found similar: \($0.currentFilename)" }
                ?? "Missing in FCP folder"
            return Check(label: "FCP bundle (\(fcpBundleFilename))",
                         detail: detail,
                         status: .missing, path: path, sizeBytes: nil,
                         suggestedRename: suggestion)
        }()

        // 7 — Description (metadata)
        let refined = clip.descriptionRefined.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw     = clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionCheck: Check = {
            if !refined.isEmpty {
                let words = refined.split(whereSeparator: \.isWhitespace).count
                return Check(label: "Description (refined)",
                             detail: "\(words) words",
                             status: .ok, path: nil, sizeBytes: nil)
            }
            if !raw.isEmpty {
                let words = raw.split(whereSeparator: \.isWhitespace).count
                return Check(label: "Description (raw only)",
                             detail: "Raw description present (\(words) words) but not refined yet — run Refine via Ollama in the editor.",
                             status: .warn, path: nil, sizeBytes: nil)
            }
            return Check(label: "Description",
                         detail: "No description — paste raw text and refine via Ollama.",
                         status: .missing, path: nil, sizeBytes: nil)
        }()

        // 8 — Transcript (metadata)
        let transcriptText = clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptCheck: Check = {
            if transcriptText.isEmpty {
                return Check(label: "Video transcription",
                             detail: "No transcript — generate via the Capture / Transcript pill in this workflow, or from the editor.",
                             status: .missing, path: nil, sizeBytes: nil)
            }
            let words = transcriptText.split(whereSeparator: \.isWhitespace).count
            return Check(label: "Video transcription",
                         detail: "\(words) words on file",
                         status: .ok, path: nil, sizeBytes: nil)
        }()

        // 9 — Hashes (MD5 / SHA-1 / SHA-256). The clip stores hex digests
        // for both the main and reduced MP4. We treat the trio as
        // computed together — if `hashesComputedAt` is empty the clip
        // hasn't been hashed yet (missing). When we DO have hashes, but
        // the reduced MP4 file exists on disk and the reduced row is
        // empty, that's a partial state (warn — the user has likely
        // generated a reduced version after hashing). Otherwise OK.
        let hashesCheck: Check = {
            let mainPresent = mp4Check.status == .ok || mp4Check.status == .warn
            guard mainPresent else {
                return Check(label: "File hashes (MD5 / SHA-1 / SHA-256)",
                             detail: "Main MP4 not on disk — nothing to hash.",
                             status: .na, path: nil, sizeBytes: nil)
            }
            if clip.hashesComputedAt.isEmpty || clip.mp4Sha256.isEmpty {
                return Check(label: "File hashes (MD5 / SHA-1 / SHA-256)",
                             detail: "Not yet computed — run the hashes action below.",
                             status: .missing, path: nil, sizeBytes: nil)
            }
            // Reduced MP4 exists on disk but no reduced hash → partial.
            if reducedCheck.status == .ok && clip.reducedSha256.isEmpty {
                return Check(label: "File hashes (MD5 / SHA-1 / SHA-256)",
                             detail: "Main hashed (\(clip.hashesComputedAt)) but the reduced MP4 hasn't been hashed yet.",
                             status: .warn, path: nil, sizeBytes: nil)
            }
            let reducedNote = clip.reducedSha256.isEmpty ? "" : " + reduced"
            return Check(label: "File hashes (MD5 / SHA-1 / SHA-256)",
                         detail: "Computed \(clip.hashesComputedAt) (main\(reducedNote)).",
                         status: .ok, path: nil, sizeBytes: nil)
        }()

        // FCP push candidate — only computed when the main MP4 is
        // missing and the FCP folder is reachable (otherwise there's
        // nothing to push). Picks the best-match MP4 in FCP by
        // similarity to the expected `<Title>.mp4` filename. The single
        // standalone .mp4 case wins automatically.
        var fcpMp4Candidate: String? = nil
        if mp4Check.status == .missing,
           fcpCheck.status == .ok,
           let fcpDir = fcpPath,
           !title.isEmpty,
           let entries = try? fm.contentsOfDirectory(atPath: fcpDir) {
            let mp4s = entries.filter { $0.lowercased().hasSuffix(".mp4") }
            if !mp4s.isEmpty {
                let normalized = FuzzyMatch.normalize(title)
                let scored = mp4s.map { name -> (String, Double) in
                    let base = FuzzyMatch.normalize((name as NSString).deletingPathExtension)
                    return (name, FuzzyMatch.similarity(base, normalized))
                }
                fcpMp4Candidate = scored.max(by: { $0.1 < $1.1 })?.0
            }
        }

        return Result(
            fcp: fcpCheck,
            production: prodCheck,
            mp4: mp4Check,
            reduced: reducedCheck,
            thumbnailFrames: thumbnailFramesCheck,
            fcpBundle: fcpBundleCheck,
            description: descriptionCheck,
            transcript: transcriptCheck,
            hashes: hashesCheck,
            foundFrameNumbers: foundFrameNumbers,
            expectedFrameCount: expectedFrameCount,
            detectedClipFilename: detectedClipFilename,
            detectedPreviewFilename: detectedPreviewFilename,
            fcpMp4Candidate: fcpMp4Candidate
        )
    }

    /// Scan `parentDir` for `<title>_frame_NN.png` and return the NN values
    /// in ascending order. The match is loose enough to absorb common
    /// title sanitization (slashes / colons replaced with `-`); a strict
    /// case-insensitive prefix check is enough for the workflows we
    /// generate ourselves.
    private static func findFrameNumbers(parentDir: String, title: String, fm: FileManager) -> [Int] {
        guard let entries = try? fm.contentsOfDirectory(atPath: parentDir) else { return [] }
        let prefix = (title + "_frame_").lowercased()
        var found: Set<Int> = []
        for name in entries {
            let lower = name.lowercased()
            guard lower.hasPrefix(prefix), lower.hasSuffix(".png") else { continue }
            let middle = lower.dropFirst(prefix.count).dropLast(".png".count)
            if let n = Int(middle) {
                found.insert(n)
            }
        }
        return found.sorted()
    }

    // MARK: - Helpers

    private static func expand(_ path: String?) -> String? {
        guard let p = path, !p.isEmpty else { return nil }
        // Only strip characters that should never appear in a real
        // filesystem path — newlines, tabs, NUL. Trailing / leading
        // SPACES are legal in macOS filenames (e.g. "MILF " with a
        // trailing space is a real folder name we've seen in the wild),
        // so we deliberately preserve them here. The caller's existence
        // check then matches the on-disk name exactly.
        let invalid = CharacterSet(charactersIn: "\n\r\t\u{0}")
        let cleaned = p.trimmingCharacters(in: invalid)
        guard !cleaned.isEmpty else { return nil }
        var expanded = (cleaned as NSString).expandingTildeInPath
        // Strip a trailing path separator so the exact-string match
        // doesn't depend on whether the path was stored with or
        // without the trailing slash.
        while expanded.count > 1 && expanded.hasSuffix("/") {
            expanded = String(expanded.dropLast())
        }
        return expanded
    }

    private static func sanitizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/",  with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":",  with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDirectory(_ path: String, fm: FileManager) -> Bool {
        // Multi-pass check, in cheap-to-expensive order. We've seen all
        // four cases in real user data:
        //   1. Exact literal path matches on-disk.
        //   2. URL round-trip succeeds (handles trailing-slash + a few
        //      symlink quirks like /tmp ↔ /private/tmp).
        //   3. Unicode normalisation (NFC vs NFD on the volume name —
        //      external drives often arrive in NFD).
        //   4. Whitespace-trimmed variant — covers the case where the
        //      stored path has a stray trailing space the on-disk name
        //      doesn't have, OR vice-versa where the on-disk name has
        //      a trailing space that some upstream code stripped.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if (try? url.resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory) == true {
            return true
        }
        let nfc = path.precomposedStringWithCanonicalMapping
        var nfcDir: ObjCBool = false
        if nfc != path, fm.fileExists(atPath: nfc, isDirectory: &nfcDir), nfcDir.boolValue {
            return true
        }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        var trimDir: ObjCBool = false
        if trimmed != path,
           fm.fileExists(atPath: trimmed, isDirectory: &trimDir),
           trimDir.boolValue {
            return true
        }
        return false
    }

    private static func fileSize(_ path: String, fm: FileManager) -> Int64? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.int64Value
    }

    /// Scan `parentDir` for files matching `predicate`, score each against
    /// `expected` (by basename Levenshtein similarity), and return the closest
    /// match with the rest as alternatives. Returns nil when no candidates
    /// match — including when the only match is the expected file itself
    /// (defensive — the caller already checked that path didn't exist).
    private static func findRenameSuggestion(
        parentDir: String,
        expected: String,
        predicate: (String) -> Bool,
        fm: FileManager
    ) -> SuggestedRename? {
        guard let entries = try? fm.contentsOfDirectory(atPath: parentDir) else { return nil }
        let candidates = entries.filter(predicate).filter { entry in
            // Defense in depth: skip the expected name (case-insensitive).
            entry.compare(expected, options: .caseInsensitive) != .orderedSame
        }
        guard !candidates.isEmpty else { return nil }

        let expectedBase = FuzzyMatch.normalize((expected as NSString).deletingPathExtension)
        let scored = candidates
            .map { name -> (name: String, sim: Double) in
                let base = FuzzyMatch.normalize((name as NSString).deletingPathExtension)
                return (name, FuzzyMatch.similarity(base, expectedBase))
            }
            .sorted { $0.sim > $1.sim }

        guard let top = scored.first else { return nil }
        let alternatives = scored.dropFirst().map { $0.name }

        return SuggestedRename(
            parentDir: parentDir,
            currentFilename: top.name,
            targetFilename: expected,
            alternatives: Array(alternatives)
        )
    }

    /// Perform the actual rename — `mv from to`. The caller is responsible
    /// for re-running the audit afterwards so the UI reflects the new state.
    /// Throws if the destination already exists, the source is gone, or the
    /// volume isn't writable. No-op when the names already match.
    static func applyRename(_ rename: SuggestedRename) throws {
        guard rename.currentFilename != rename.targetFilename else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: rename.toPath) {
            struct DestExists: LocalizedError {
                let path: String
                var errorDescription: String? {
                    "A file already exists at \(path) — refusing to overwrite. Resolve manually."
                }
            }
            throw DestExists(path: rename.toPath)
        }
        try fm.moveItem(atPath: rename.fromPath, toPath: rename.toPath)
    }

    /// Move a rendered MP4 export from the FCP folder into the
    /// Production folder, renaming it to the canonical `<Title>.mp4`
    /// in the process. Creates the production folder when missing.
    /// Refuses to overwrite an existing destination — the user has to
    /// resolve that manually so we don't accidentally clobber a
    /// known-good copy.
    static func pushFromFCP(
        fcpFolder: String,
        productionFolder: String,
        title: String,
        sourceFilename: String
    ) throws -> String {
        let fm = FileManager.default
        struct PushError: LocalizedError {
            let msg: String
            var errorDescription: String? { msg }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw PushError(msg: "Clip has no title — set the title before pushing.")
        }

        let fcpExpanded  = (fcpFolder as NSString).expandingTildeInPath
        let prodExpanded = (productionFolder as NSString).expandingTildeInPath
        let sourcePath   = (fcpExpanded as NSString).appendingPathComponent(sourceFilename)
        let canonicalDestName = sanitizeTitle(trimmedTitle) + ".mp4"
        let destPath = (prodExpanded as NSString).appendingPathComponent(canonicalDestName)

        guard fm.fileExists(atPath: sourcePath) else {
            throw PushError(msg: "Source not found in FCP folder: \(sourcePath)")
        }

        // Create production folder if it isn't there yet.
        var isDir: ObjCBool = false
        if !(fm.fileExists(atPath: prodExpanded, isDirectory: &isDir) && isDir.boolValue) {
            try fm.createDirectory(atPath: prodExpanded,
                                   withIntermediateDirectories: true,
                                   attributes: nil)
        }

        if fm.fileExists(atPath: destPath) {
            throw PushError(msg: "Destination already exists: \(destPath) — refusing to overwrite. Resolve manually.")
        }

        try fm.moveItem(atPath: sourcePath, toPath: destPath)
        return destPath
    }

    // MARK: - Provision production folder

    enum ProvisionError: LocalizedError {
        case missingProductionBase
        case missingContentDate
        case missingTitle
        case sourceMissing(String)
        case destExists(String)
        case copyFailed(from: String, to: String, underlying: String)
        case mkdirFailed(String, underlying: String)

        var errorDescription: String? {
            switch self {
            case .missingProductionBase:
                return "Production root isn't set. Configure it in Settings → File Locations."
            case .missingContentDate:
                return "Clip has no content date — set one before stamping a production folder."
            case .missingTitle:
                return "Clip has no title — set one before stamping a production folder."
            case .sourceMissing(let p):
                return "FCP source not found: \(p)"
            case .destExists(let p):
                return "Destination already exists: \(p) — refusing to overwrite. Resolve manually."
            case .copyFailed(let from, let to, let why):
                return "Copy failed: \(from) → \(to) (\(why))"
            case .mkdirFailed(let p, let why):
                return "Couldn't create folder \(p): \(why)"
            }
        }
    }

    /// Outcome of `provisionProductionFolder`. The caller writes
    /// `productionPath` into `clip.productionFolder` and (when set)
    /// `canonicalFilename` into `clip.clipFilename`.
    struct ProvisionResult {
        /// Absolute, expanded path to the production folder. Always present
        /// on success — created on demand if it didn't exist.
        let productionPath: String
        /// `true` when this call actually created the folder; `false` when
        /// the folder was already on disk.
        let createdFolder: Bool
        /// Original filename that was copied from FCP, when applicable.
        let copiedFromFCP: String?
        /// Final filename inside the production folder (`<Title>.<ext>`),
        /// when a copy was performed. Caller stores on `clip.clipFilename`.
        let canonicalFilename: String?
    }

    /// One-click "fix the missing production folder" used by the audit
    /// pills. Path resolution delegates to `PathDefaultsService.productionPath`
    /// so the pill, the editor's "Set default" wand button, and the one-time
    /// backfill all produce the same shape — for the shipped default pattern
    /// `{date} {title}` that's `<base>/<contentDate> <Title>`.
    ///
    /// When `fcpSourceFilename` is non-nil and the file exists in
    /// `clip.fcpProjectFolder`, the file is **copied** (not moved — the FCP
    /// project keeps its render) into the new folder as `<Title>.<sourceExt>`.
    /// Final layout: `<base>/<contentDate> <Title>/<Title>.<ext>`. The folder
    /// name carries date + title for human scannability, the file inside is
    /// just the title — so `Title.Extension`-style references on other
    /// surfaces (audit, editor, exports) all match.
    @discardableResult
    static func provisionProductionFolder(
        clip: Clip,
        settings: AppSettings,
        fcpSourceFilename: String?
    ) throws -> ProvisionResult {
        let fm = FileManager.default

        let baseTrim = settings.defaultProductionBase.trimmingCharacters(in: .whitespaces)
        guard !baseTrim.isEmpty else { throw ProvisionError.missingProductionBase }

        let contentDate = (clip.contentDate ?? "").trimmingCharacters(in: .whitespaces)
        guard !contentDate.isEmpty else { throw ProvisionError.missingContentDate }

        let titleTrim = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleTrim.isEmpty else { throw ProvisionError.missingTitle }

        // Single source of truth for path resolution — keeps the pill in
        // lockstep with the wand button and the backfill regardless of any
        // future pattern customisation.
        guard let prodPath = PathDefaultsService.productionPath(for: clip, settings: settings) else {
            // PathDefaultsService returns nil only when base is empty or
            // there's no usable date — both of which we've already
            // validated, but defend against drift.
            throw ProvisionError.missingProductionBase
        }

        // mkdir -p
        var isDir: ObjCBool = false
        let preExisted = fm.fileExists(atPath: prodPath, isDirectory: &isDir) && isDir.boolValue
        if !preExisted {
            do {
                try fm.createDirectory(atPath: prodPath,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
            } catch {
                throw ProvisionError.mkdirFailed(prodPath, underlying: error.localizedDescription)
            }
        }

        // Optional copy from FCP. Skipped silently when caller didn't pass
        // a candidate — the empty-folder case still returns success.
        var copiedFromFCP: String? = nil
        var canonicalFilename: String? = nil
        if let sourceName = fcpSourceFilename?.trimmingCharacters(in: .whitespaces),
           !sourceName.isEmpty,
           let fcp = clip.fcpProjectFolder?.trimmingCharacters(in: .whitespaces),
           !fcp.isEmpty {
            let fcpExpanded = (fcp as NSString).expandingTildeInPath
            let sourcePath = (fcpExpanded as NSString).appendingPathComponent(sourceName)
            guard fm.fileExists(atPath: sourcePath) else {
                throw ProvisionError.sourceMissing(sourcePath)
            }

            // Preserve the source's extension so the user's "Title.Extension"
            // mapping holds — an .mov source becomes Title.mov, an .mp4
            // becomes Title.mp4. Sanitize the title with the existing helper
            // so `/`, `\`, `:` collapse to `-`.
            let ext = (sourceName as NSString).pathExtension
            let safeTitle = sanitizeTitle(titleTrim)
            let destName = ext.isEmpty ? safeTitle : "\(safeTitle).\(ext)"
            let destPath = (prodPath as NSString).appendingPathComponent(destName)

            if fm.fileExists(atPath: destPath) {
                throw ProvisionError.destExists(destPath)
            }
            do {
                try fm.copyItem(atPath: sourcePath, toPath: destPath)
            } catch {
                throw ProvisionError.copyFailed(
                    from: sourcePath,
                    to: destPath,
                    underlying: error.localizedDescription
                )
            }
            copiedFromFCP = sourceName
            canonicalFilename = destName
        }

        return ProvisionResult(
            productionPath: prodPath,
            createdFolder: !preExisted,
            copiedFromFCP: copiedFromFCP,
            canonicalFilename: canonicalFilename
        )
    }

    /// Promote a `<Title>_frame_NN.png` capture into the canonical
    /// `<Title>.png` thumbnail. Copies the picked frame into Production
    /// (overwriting any prior `<Title>.png` there) and deletes any stale
    /// `<Title>.png` mirror in the FCP folder so Production stays the
    /// single source of truth. Returns the absolute path of the new
    /// canonical thumbnail; the caller is expected to write that
    /// filename onto `clip.thumbnailFilename`.
    static func promoteFrameToThumbnail(
        productionFolder: String,
        fcpFolder: String?,
        title: String,
        frameFilename: String
    ) throws -> String {
        let fm = FileManager.default
        let prodExpanded = (productionFolder as NSString).expandingTildeInPath
        let sourcePath   = (prodExpanded as NSString).appendingPathComponent(frameFilename)
        let canonicalName = sanitizeTitle(title) + ".png"
        let destPath     = (prodExpanded as NSString).appendingPathComponent(canonicalName)

        struct PromoteError: LocalizedError {
            let msg: String
            var errorDescription: String? { msg }
        }
        guard fm.fileExists(atPath: sourcePath) else {
            throw PromoteError(msg: "Picked frame not found: \(sourcePath)")
        }

        // Production: overwrite any prior canonical thumbnail.
        if fm.fileExists(atPath: destPath) {
            try fm.removeItem(atPath: destPath)
        }
        try fm.copyItem(atPath: sourcePath, toPath: destPath)

        // FCP: clean up any stale `<Title>.png` mirror so Production is
        // the only source of truth. Silent if the FCP volume isn't
        // mounted or the file doesn't exist — those aren't failures.
        if let fcp = fcpFolder?.trimmingCharacters(in: .whitespaces), !fcp.isEmpty {
            let fcpExpanded = (fcp as NSString).expandingTildeInPath
            let fcpThumb = (fcpExpanded as NSString).appendingPathComponent(canonicalName)
            if fm.fileExists(atPath: fcpThumb) {
                try? fm.removeItem(atPath: fcpThumb)
            }
        }

        return destPath
    }

}

import Foundation

/// Spanned-clip detection (Kyno-parity row 29).
///
/// Cameras that record onto FAT32 cards break long takes across
/// multiple files when they hit the 4 GB / 2 GB single-file limit:
/// C300 emits `00000.MXF`, `00001.MXF`, …; Sony XAVC emits
/// `C0001.MP4`, `C0002.MP4`; GH5 emits `P1000001.MP4`,
/// `P1000002.MP4`. To an NLE these are one continuous take; to a
/// vanilla file browser they look like unrelated clips. Kyno's
/// browser auto-joins them so the user sees one item.
///
/// This service is a pure-Swift detector over an in-memory asset
/// list. It doesn't touch disk or AVAsset — the catalogue already
/// has every field it needs (codec, dims, fps, modtime). The
/// detector errs on the side of **not** grouping: false positives
/// here would silently glue together unrelated takes, which is
/// much worse than missing a span.
///
/// Heuristic, applied per directory:
///   1. Sort the assets by filename.
///   2. For each adjacent pair, check that they share:
///      - extension (case-insensitive)
///      - codec, widthPx, heightPx, frameRate, audioCodec
///      - filename prefix up to the trailing digit sequence
///      - sequential numeric suffix (N → N+1)
///      - modtime within `maxModtimeGap` (default 120s)
///   3. Chain consecutive matches into a single `SpanGroup`.
///
/// Single-file "groups" (no spanning) are dropped from the
/// returned list — the call site only cares about real spans.
enum SpanDetectionService {

    /// Max allowed modification-time gap between adjacent
    /// segments. 120 seconds covers the typical camera card-write
    /// boundary; widening it past a few minutes starts catching
    /// unrelated takes.
    static let maxModtimeGap: TimeInterval = 120

    struct SpanGroup: Identifiable {
        /// Stable identifier based on first segment's path so the
        /// sidebar selection survives re-detection.
        let id: String
        /// Display label = common filename prefix without the digit
        /// suffix, with extension. e.g. `MVI_.MOV` → reads as the
        /// camera "stem" the user recognises on their card.
        let label: String
        let segments: [Asset]
        let totalDuration: Double
        /// Directory the segments live in. Used for grouping in the
        /// sidebar — different folders never share a SpanGroup.
        let directory: String
    }

    /// Detect every span group in `assets`. Returns each group in
    /// the order it appears (sorted by segment 0's path).
    static func detect(in assets: [Asset]) -> [SpanGroup] {
        // Bucket by parent directory + extension; only same-folder
        // files of the same kind can ever span.
        var bucketed: [String: [Asset]] = [:]
        for a in assets {
            let dir = (a.path as NSString).deletingLastPathComponent
            let ext = ((a.path as NSString).pathExtension).lowercased()
            let key = "\(dir)|\(ext)"
            bucketed[key, default: []].append(a)
        }
        var groups: [SpanGroup] = []
        for (_, bucket) in bucketed {
            let sorted = bucket.sorted { $0.filename < $1.filename }
            var i = 0
            while i < sorted.count {
                var run: [Asset] = [sorted[i]]
                var j = i + 1
                while j < sorted.count,
                      isContinuation(prev: sorted[j - 1], next: sorted[j]) {
                    run.append(sorted[j])
                    j += 1
                }
                if run.count >= 2 {
                    let totalDur = run.reduce(0.0) {
                        $0 + ($1.durationSeconds ?? 0)
                    }
                    let label = spanLabel(for: run)
                    let dir = (run[0].path as NSString).deletingLastPathComponent
                    groups.append(SpanGroup(
                        id: run[0].path,
                        label: label,
                        segments: run,
                        totalDuration: totalDur,
                        directory: dir
                    ))
                }
                i = j
            }
        }
        return groups.sorted { $0.segments[0].path < $1.segments[0].path }
    }

    // MARK: - Heuristics

    /// True when `next` looks like a real continuation of `prev`.
    /// All conditions must hold — better to miss a span than to
    /// blindly glue unrelated clips.
    private static func isContinuation(prev: Asset, next: Asset) -> Bool {
        guard prev.codec == next.codec,
              prev.widthPx == next.widthPx,
              prev.heightPx == next.heightPx,
              prev.audioCodec == next.audioCodec
        else { return false }
        if let pr = prev.frameRate, let nr = next.frameRate,
           abs(pr - nr) > 0.05 { return false }
        // Modtime proximity. Two segments of the same recording
        // are written within seconds of each other; unrelated
        // recordings are minutes apart.
        if abs(prev.modifiedAt.timeIntervalSince(next.modifiedAt))
           > maxModtimeGap { return false }
        // Filename: same prefix + sequential trailing digits.
        guard let prevSplit = splitDigits(filenameStem(prev.filename)),
              let nextSplit = splitDigits(filenameStem(next.filename))
        else { return false }
        return prevSplit.prefix == nextSplit.prefix
            && prevSplit.numeric + 1 == nextSplit.numeric
    }

    /// Strip the file extension. We compare extensions separately
    /// — only same-extension files belong in the same span.
    private static func filenameStem(_ name: String) -> String {
        let ns = name as NSString
        return ns.deletingPathExtension
    }

    /// Split a filename stem into (non-digit prefix, trailing
    /// integer). Returns nil when there's no trailing digit run.
    /// Examples:
    ///   "MVI_0001" → ("MVI_", 1)
    ///   "C0001"    → ("C", 1)
    ///   "00001"    → ("", 1)
    ///   "clip"     → nil
    private static func splitDigits(_ stem: String) -> (prefix: String, numeric: Int)? {
        let chars = Array(stem)
        var i = chars.count
        while i > 0, chars[i - 1].isASCII, chars[i - 1].isNumber {
            i -= 1
        }
        guard i < chars.count,
              let n = Int(String(chars[i..<chars.count])) else { return nil }
        let prefix = String(chars[0..<i])
        return (prefix, n)
    }

    /// Build a human-readable span label like `MVI_.MOV (4 segments)`.
    private static func spanLabel(for run: [Asset]) -> String {
        let first = run[0]
        let ext = ((first.path as NSString).pathExtension).uppercased()
        let stem = filenameStem(first.filename)
        let prefix = splitDigits(stem)?.prefix ?? stem
        let displayPrefix = prefix.isEmpty ? "Spanned" : prefix
        return "\(displayPrefix).\(ext) (\(run.count) segments)"
    }
}

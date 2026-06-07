import Foundation

/// Transparent handling of **raw split archives** — the `.001`, `.002`, …
/// volume sets produced by 7-Zip's "split to volumes", the `split` tool, and
/// many download sites (`movie.mkv.7z.001`, `backup.zip.001`, …). The parts are
/// a plain byte split of one original archive, so concatenating them in order
/// reproduces it exactly; the engine then opens the reassembled file normally.
///
/// (Structured multi-volume formats — split *zip* `.z01` and multi-part *RAR*
/// `.partN.rar` / `.rNN` — are NOT plain concatenations and aren't handled here;
/// they'd need format-aware spanning.)
public enum MultiVolume {

    /// If `url` belongs to a raw numeric split set, return all parts in order
    /// (`.001` first). Returns nil for a normal single file. Works whether the
    /// user opens the first part or any later one.
    public static func volumeParts(for url: URL) -> [URL]? {
        let ext = url.pathExtension
        // The volume extension must be all digits, ≥2 wide (001, 0001, …).
        guard ext.count >= 2, ext.allSatisfy(\.isNumber) else { return nil }

        let width = ext.count
        let base = url.deletingPathExtension()          // strips ".001" → "archive.7z"
        let fm = FileManager.default

        func part(_ n: Int) -> URL {
            base.appendingPathExtension(String(format: "%0\(width)d", n))
        }
        // The set must start at .001 (…000 also tolerated by some tools).
        let start = fm.fileExists(atPath: part(1).path) ? 1
                  : (fm.fileExists(atPath: part(0).path) ? 0 : -1)
        guard start >= 0 else { return nil }

        var parts: [URL] = []
        var n = start
        while fm.fileExists(atPath: part(n).path) {
            parts.append(part(n))
            n += 1
            if n - start > 100_000 { break }            // runaway guard
        }
        return parts.count >= 2 ? parts : nil
    }

    /// Concatenate `parts` into a temp file (named after the original archive so
    /// extension-based detection still works) and return its URL. Streamed, so
    /// memory stays flat regardless of total size. Caller deletes the temp.
    public static func assemble(_ parts: [URL]) throws -> URL {
        let fm = FileManager.default
        // Recover the original name: "archive.7z.001" → "archive.7z".
        let originalName = parts[0].deletingPathExtension().lastPathComponent
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("pa-vol-\(UUID().uuidString)-\(originalName)")
        fm.createFile(atPath: tmp.path, contents: nil)
        guard let out = FileHandle(forWritingAtPath: tmp.path) else {
            throw ArchiveError.cannotOpen(path: tmp.path, detail: "couldn't create temp for reassembly")
        }
        defer { try? out.close() }
        for part in parts {
            guard let inp = FileHandle(forReadingAtPath: part.path) else {
                throw ArchiveError.cannotOpen(path: part.path, detail: "missing volume \(part.lastPathComponent)")
            }
            while case let chunk = inp.readData(ofLength: 4 << 20), !chunk.isEmpty {
                out.write(chunk)
            }
            try? inp.close()
        }
        return tmp
    }
}

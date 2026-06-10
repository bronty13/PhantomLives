import Foundation

/// Classifies a line of osxphotos export output so the engine can present it sensibly.
///
/// osxphotos floods the log with scary "❌️ Error exporting photo … exiftool error" lines for
/// photos whose **in-file metadata embed** failed — almost always old scans / odd formats with
/// damaged EXIF (Bad/Truncated MakerNotes, "Not a valid HEIC/JPEG", Bad ExifIFD entry, "Error
/// reading image data"). These are **benign**: osxphotos still wrote the image file and its
/// `.xmp` sidecar; only the redundant in-file embed was skipped. We reclassify them as an
/// informational "sidecar-only" notice (counted, not spammed), keep them distinct from genuine
/// export failures, and never confuse them with `missing:` (no file archived at all).
public enum OsxphotosLine {

    public enum Kind: Equatable {
        case metadataEmbedSkip(uuid: String, file: String)  // benign — file + sidecar archived
        case exportFailure(uuid: String, file: String, reason: String)  // a real export failure
        case companionNoise          // "exiftool error for file …" / "Retrying export …" — suppress
        case progressBar             // a rich progress-bar redraw — suppress
        case other                   // pass through to the log
    }

    /// Reasons that mean "metadata couldn't be embedded in the file" but the file itself is fine.
    static let benignEmbedSignatures = [
        "makernotes",                 // Bad / Truncated MakerNotes offset/directory/entry
        "not a valid heic",
        "not a valid jpeg",
        "not a valid png",
        "bad format",                 // Bad format (N) for … entry N
        "error reading image data",
        "bad exififd",
        "exififd entry",
    ]

    public static func classify(_ raw: String) -> Kind {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let lower = line.lowercased()

        // Companion spam around a failed embed — always suppress (the engine counts the photo
        // once from the "Error exporting photo" line instead).
        if lower.contains("exiftool error for file") || lower.contains("retrying export for photo") {
            return .companionNoise
        }
        // Rich progress redraw (osxphotos suppresses this when piped, but guard anyway).
        if line.contains("━") || line.contains("─━") {
            return .progressBar
        }

        // "❌️  Error exporting photo (UUID: FILENAME) as DEST: Error: REASON"
        if lower.contains("error exporting photo") {
            let (uuid, file) = parseUUIDAndFile(line)
            let reason = parseReason(line)
            let benign = benignEmbedSignatures.contains { reason.lowercased().contains($0) }
            return benign ? .metadataEmbedSkip(uuid: uuid, file: file)
                          : .exportFailure(uuid: uuid, file: file, reason: reason)
        }

        return .other
    }

    /// Extract the UUID and filename from "… photo (UUID: FILENAME) as …".
    static func parseUUIDAndFile(_ line: String) -> (uuid: String, file: String) {
        guard let open = line.range(of: "("),
              let colon = line.range(of: ": ", range: open.upperBound..<line.endIndex),
              let close = line.range(of: ")", range: colon.upperBound..<line.endIndex)
        else { return ("", "") }
        let uuid = String(line[open.upperBound..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
        let file = String(line[colon.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (uuid, file)
    }

    /// Everything after the last "Error: " in the line.
    static func parseReason(_ line: String) -> String {
        guard let r = line.range(of: "Error: ", options: .backwards) else { return line }
        // Trim the trailing temp-path osxphotos appends after " - /var/folders/…".
        var reason = String(line[r.upperBound...])
        if let dash = reason.range(of: " - /") { reason = String(reason[..<dash.lowerBound]) }
        return reason.trimmingCharacters(in: .whitespaces)
    }
}

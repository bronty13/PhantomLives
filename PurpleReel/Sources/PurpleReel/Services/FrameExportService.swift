import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Batch frame extractor. Kyno-parity row 15: every marker becomes a
/// PNG with the active LUT baked in. The single-frame export inside
/// `PlayerController.exportCurrentFrame` stays as-is; this service
/// handles the multi-frame fan-out so we don't grow the player
/// controller into a write-many-files-at-once role.
enum FrameExportService {

    struct Result {
        var written: Int = 0
        var skipped: Int = 0
        var failures: [String] = []
    }

    /// Export one PNG per marker. File names embed the marker
    /// timecode (HHMMSSFF-ish) and a slug of the marker note when
    /// present, so a reviewer can read the filename without opening
    /// each still.
    /// - Parameters:
    ///   - assetURL: source media URL.
    ///   - markers: catalogue marker list (in `Marker` schema).
    ///   - lut: optional LUTData to bake into every still.
    ///   - fps: clip frame rate, used for the timecode in the filename.
    ///   - destDirectory: where to write the PNGs. Created if missing.
    static func exportFramesAtMarkers(
        assetURL: URL,
        markers: [Marker],
        lut: LUTData?,
        fps: Double,
        destDirectory: URL
    ) async -> Result {
        var result = Result()
        try? FileManager.default.createDirectory(at: destDirectory,
                                                  withIntermediateDirectories: true)

        let avAsset = AVURLAsset(url: assetURL)
        let gen = AVAssetImageGenerator(asset: avAsset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter  = .zero
        let lutFilter = lut.flatMap { LUTService.filter(for: $0) }
        let ciContext = CIContext()

        // Single base name once — every output sits next to it with
        // a timecode + slug suffix.
        let base = assetURL.deletingPathExtension().lastPathComponent

        for marker in markers {
            let t = CMTime(seconds: marker.timecodeIn, preferredTimescale: 600)
            do {
                let cg = try gen.copyCGImage(at: t, actualTime: nil)
                let baked = applyLUT(to: cg, filter: lutFilter, ctx: ciContext) ?? cg
                let stamp = filenameTimecode(seconds: marker.timecodeIn, fps: fps)
                let slug = filenameSlug(note: marker.note)
                let suffix = slug.isEmpty ? "" : "_\(slug)"
                let url = destDirectory.appendingPathComponent("\(base)_\(stamp)\(suffix).png")
                if FileManager.default.fileExists(atPath: url.path) {
                    result.skipped += 1
                    continue
                }
                let rep = NSBitmapImageRep(cgImage: baked)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    result.failures.append("PNG encode failed at \(stamp)")
                    continue
                }
                try png.write(to: url)
                result.written += 1
            } catch {
                result.failures.append("\(marker.timecodeIn)s: \(error.localizedDescription)")
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func applyLUT(to source: CGImage,
                                  filter: CIFilter?,
                                  ctx: CIContext) -> CGImage? {
        guard let filter else { return source }
        let ci = CIImage(cgImage: source)
        filter.setValue(ci, forKey: kCIInputImageKey)
        guard let out = filter.outputImage else { return nil }
        return ctx.createCGImage(out, from: ci.extent)
    }

    /// `HHMMSSFF`-style timecode embedded in the filename. Stable to
    /// sort by, avoids colons (illegal in Finder display).
    private static func filenameTimecode(seconds: Double, fps: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let f = Int((seconds - Double(total)) * max(fps, 1))
        return String(format: "%02d%02d%02d_%02df", h, m, s, f)
    }

    /// Filesystem-safe slug from the marker note. Empty when nil.
    /// Drops anything that isn't alnum / dash / underscore; caps
    /// length so a long note doesn't blow the path.
    private static func filenameSlug(note: String?) -> String {
        guard let raw = note, !raw.isEmpty else { return "" }
        let lower = raw.lowercased()
        let mapped = lower.unicodeScalars.map { sc -> Character in
            if CharacterSet.alphanumerics.contains(sc) { return Character(sc) }
            return "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(collapsed.prefix(40))
    }
}

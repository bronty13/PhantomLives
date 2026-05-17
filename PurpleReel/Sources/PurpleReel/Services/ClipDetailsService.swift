import Foundation
import AVFoundation

/// Extended metadata loaded on demand for the Content tab — the bits
/// not stored in the catalog table because they're cheap to re-derive
/// and only needed when the user opens the inspector.
struct ClipDetails {
    var path: String
    var sizeBytes: Int64
    var modificationDate: Date?
    var creationDate: Date?

    var container: String?           // "MPEG-4" / "QuickTime Movie" / …
    var videoCodec: String?          // "avc1" / "hvc1" / "prores" / …
    var widthPx: Int?
    var heightPx: Int?
    var frameRate: Double?
    var videoBitrateBps: Double?     // estimated; 0 → unknown

    var audioCodec: String?
    var audioSampleRate: Double?
    var audioChannels: Int?
    var audioBitrateBps: Double?

    var durationSeconds: Double?
}

enum ClipDetailsService {

    /// Load full details from disk + AVFoundation. Safe to call from
    /// any actor — heavy work runs on a detached task.
    static func load(asset: Asset) async -> ClipDetails {
        await Task.detached(priority: .userInitiated) {
            loadSync(asset: asset)
        }.value
    }

    private static func loadSync(asset: Asset) -> ClipDetails {
        var d = ClipDetails(
            path: asset.path,
            sizeBytes: asset.sizeBytes,
            modificationDate: asset.modifiedAt,
            creationDate: nil,
            container: containerLabel(for: asset.path),
            videoCodec: asset.codec,
            widthPx: asset.widthPx,
            heightPx: asset.heightPx,
            frameRate: asset.frameRate,
            videoBitrateBps: nil,
            audioCodec: nil,
            audioSampleRate: nil,
            audioChannels: nil,
            audioBitrateBps: nil,
            durationSeconds: asset.durationSeconds
        )

        let url = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return d }

        let avAsset = AVURLAsset(url: url)

        // Creation date from QuickTime common metadata.
        for item in avAsset.commonMetadata where item.commonKey == .commonKeyCreationDate {
            if let date = item.dateValue {
                d.creationDate = date
            } else if let str = item.stringValue,
                      let parsed = ISO8601DateFormatter().date(from: str) {
                d.creationDate = parsed
            }
        }

        if let video = avAsset.tracks(withMediaType: .video).first {
            d.videoBitrateBps = Double(video.estimatedDataRate)
            if let fmt = video.formatDescriptions.first {
                let cm = fmt as! CMFormatDescription
                d.videoCodec = fourCC(CMFormatDescriptionGetMediaSubType(cm))
                if d.widthPx == nil || d.heightPx == nil {
                    let dim = CMVideoFormatDescriptionGetDimensions(cm)
                    d.widthPx = Int(dim.width)
                    d.heightPx = Int(dim.height)
                }
            }
        }

        if let audio = avAsset.tracks(withMediaType: .audio).first {
            d.audioBitrateBps = Double(audio.estimatedDataRate)
            if let fmt = audio.formatDescriptions.first {
                let cm = fmt as! CMFormatDescription
                d.audioCodec = fourCC(CMFormatDescriptionGetMediaSubType(cm))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(cm) {
                    d.audioSampleRate = asbd.pointee.mSampleRate
                    d.audioChannels = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
        }

        return d
    }

    private static func containerLabel(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v": return "MPEG-4"
        case "mov", "qt":  return "QuickTime Movie"
        case "mkv":         return "Matroska"
        case "avi":         return "AVI"
        case "mxf":         return "MXF"
        case "wav":         return "WAVE"
        case "aif", "aiff": return "AIFF"
        default:            return (path as NSString).pathExtension.uppercased()
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >>  8) & 0xff),
            UInt8(code & 0xff),
        ]
        let ascii = String(bytes: bytes, encoding: .ascii) ?? ""
        let trimmed = ascii.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "—" : trimmed
    }
}

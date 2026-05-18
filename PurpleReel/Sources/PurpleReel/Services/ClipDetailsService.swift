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
    /// any actor — heavy work runs on a detached task. The track /
    /// metadata reads use the modern async `.load(...)` API.
    static func load(asset: Asset) async -> ClipDetails {
        await Task.detached(priority: .userInitiated) {
            await loadAsync(asset: asset)
        }.value
    }

    private static func loadAsync(asset: Asset) async -> ClipDetails {
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

        // Creation date from QuickTime common metadata (async-load).
        let commonItems = (try? await avAsset.load(.commonMetadata)) ?? []
        for item in commonItems where item.commonKey == .commonKeyCreationDate {
            if let date = try? await item.load(.dateValue) {
                d.creationDate = date
            } else if let str = try? await item.load(.stringValue),
                      let parsed = ISO8601DateFormatter().date(from: str) {
                d.creationDate = parsed
            }
        }

        let videoTracks = (try? await avAsset.loadTracks(withMediaType: .video)) ?? []
        if let video = videoTracks.first {
            if let rate = try? await video.load(.estimatedDataRate) {
                d.videoBitrateBps = Double(rate)
            }
            let formats = (try? await video.load(.formatDescriptions)) ?? []
            if let cm = formats.first {
                d.videoCodec = fourCC(CMFormatDescriptionGetMediaSubType(cm))
                if d.widthPx == nil || d.heightPx == nil {
                    let dim = CMVideoFormatDescriptionGetDimensions(cm)
                    d.widthPx = Int(dim.width)
                    d.heightPx = Int(dim.height)
                }
            }
        }

        let audioTracks = (try? await avAsset.loadTracks(withMediaType: .audio)) ?? []
        if let audio = audioTracks.first {
            if let rate = try? await audio.load(.estimatedDataRate) {
                d.audioBitrateBps = Double(rate)
            }
            let formats = (try? await audio.load(.formatDescriptions)) ?? []
            if let cm = formats.first {
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

import Foundation
import ImageIO
import AVFoundation
import CoreLocation

/// File metadata for the comparison pane. Photo fields come from EXIF/TIFF/GPS via
/// ImageIO; video fields come from `AVAsset` track properties. Every field is
/// optional — different formats expose different subsets, and even within a format
/// (e.g. screenshots vs camera captures) the EXIF density varies.
public struct FileMetadata: Sendable, Hashable {
    // Common
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var captureDate: Date?

    // Photo
    public var cameraMake: String?
    public var cameraModel: String?
    public var lens: String?
    public var iso: Int?
    public var aperture: Double?
    public var shutterSpeed: String?
    public var focalLengthMM: Double?
    public var gpsLatitude: Double?
    public var gpsLongitude: Double?

    // Video
    public var durationSeconds: Double?
    public var codec: String?
    public var bitrateBps: Int?
    public var nominalFPS: Double?
    public var hasAudio: Bool?

    // IPTC keywords (read from `kCGImagePropertyIPTCKeywords`). Useful for any
    // photo whose original embedded keywords on import — Photos.app, Lightroom,
    // and most pro DAMs write these. Mirrored from the file itself, not from
    // PhotoKit's database, so non-Photos-library files surface them too.
    public var iptcKeywords: [String]?

    // Photos.app-specific fields, populated only when the file lives inside a
    // `.photoslibrary` AND the user granted PhotoKit access. Read via
    // `PhotoKitDeletionService.fetchMetadata(forPath:)`.
    public var photosAlbumNames: [String]?
    public var photosMediaSubtypes: [String]?
    public var photosIsFavorite: Bool?
    public var photosIsHidden: Bool?
    public var photosCreationDate: Date?
    public var photosHasAdjustments: Bool?
    public var photosBurstIdentifier: String?
    public var photosIsBurstRepresentative: Bool?

    // EXIF / IPTC / TIFF fields beyond the camera basics — surfaced when
    // populated. Most modern camera workflows write these even though the
    // earlier metadata pass didn't expose them.
    public var software: String?         // e.g. "iOS 17.4.1", "Photoshop 2024"
    public var colorProfile: String?     // e.g. "Display P3", "sRGB IEC61966-2.1"
    public var caption: String?          // IPTC caption-abstract / TIFF ImageDescription
    public var starRating: Int?          // 0-5; XMP-Photoshop:Rating or IPTC

    public init() {}

    /// Render as ordered key/value rows so the comparison panel can show two files'
    /// metadata side-by-side and highlight differing rows. Order is fixed and matches
    /// the sequence a photographer mentally scans: when, what, how.
    public struct Row: Sendable, Identifiable, Hashable {
        public let id: String
        public let label: String
        public let value: String
    }

    public func rows() -> [Row] {
        var out: [Row] = []
        func add(_ id: String, _ label: String, _ value: String?) {
            if let v = value, !v.isEmpty { out.append(Row(id: id, label: label, value: v)) }
        }
        add("dim", "Dimensions", pixelWidth.flatMap { w in pixelHeight.map { h in "\(w) × \(h)" } })
        add("captured", "Captured", captureDate.map { Self.dateFormatter.string(from: $0) })
        add("camera", "Camera", [cameraMake, cameraModel].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces).nilIfEmpty)
        add("lens", "Lens", lens)
        add("iso", "ISO", iso.map { String($0) })
        add("aperture", "Aperture", aperture.map { String(format: "ƒ/%.1f", $0) })
        add("shutter", "Shutter", shutterSpeed)
        add("focal", "Focal length", focalLengthMM.map { String(format: "%.0f mm", $0) })
        add("gps", "GPS", gpsLatitude.flatMap { lat in gpsLongitude.map { lon in
            String(format: "%.5f, %.5f", lat, lon)
        } })
        add("keywords", "Keywords", iptcKeywords.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") })
        add("rating", "Star rating", starRating.flatMap { $0 == 0 ? nil : String(repeating: "★", count: max(0, min(5, $0))) })
        add("caption", "Caption", caption)
        add("software", "Software", software)
        add("colorprofile", "Color profile", colorProfile)
        // Photos-app fields render in their own visual block at the bottom of
        // the table — see the `id` prefix `photos_` so the ComparisonView can
        // optionally style them as a separate section.
        add("photos_subtypes", "Photos subtypes", photosMediaSubtypes.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") })
        add("photos_albums", "Photos albums", photosAlbumNames.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") })
        add("photos_favorite", "Photos favorite", photosIsFavorite.map { $0 ? "★ yes" : "no" })
        add("photos_hidden", "Photos hidden", photosIsHidden.map { $0 ? "yes" : "no" })
        add("photos_adjustments", "Photos edited", photosHasAdjustments.map { $0 ? "yes (has adjustments)" : "no" })
        add("photos_burst_rep", "Burst keeper", photosIsBurstRepresentative.map { $0 ? "yes" : "no" })
        add("photos_burst_id", "Burst ID", photosBurstIdentifier)
        add("photos_created", "Photos created", photosCreationDate.map { Self.dateFormatter.string(from: $0) })
        add("duration", "Duration", durationSeconds.map { String(format: "%.1fs", $0) })
        add("codec", "Codec", codec)
        add("bitrate", "Bitrate", bitrateBps.map { Self.formatBitrate($0) })
        add("fps", "Frame rate", nominalFPS.map { String(format: "%.0f fps", $0) })
        add("audio", "Audio", hasAudio.map { $0 ? "yes" : "no" })
        return out
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", Double(bps) / 1_000_000) }
        if bps >= 1_000     { return String(format: "%.0f kbps", Double(bps) / 1_000) }
        return "\(bps) bps"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Reads metadata for one file. Cheap (no full image decode); pulls just the EXIF
/// dictionary or the video track's format description, both of which ImageIO and
/// AVFoundation can produce from the file header alone. Designed to be called
/// lazily when the user selects a cluster, not preemptively for every file.
public struct MetadataExtractor: Sendable {

    public init() {}

    public func extract(url: URL) async -> FileMetadata {
        let ext = url.pathExtension.lowercased()
        if FileKind.photoExtensions.contains(ext) {
            return extractPhoto(url: url)
        }
        if FileKind.videoExtensions.contains(ext) {
            return await extractVideo(url: url)
        }
        return FileMetadata()
    }

    // MARK: - photos

    private func extractPhoto(url: URL) -> FileMetadata {
        var m = FileMetadata()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return m }

        m.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
        m.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int

        let exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        let gps = (props[kCGImagePropertyGPSDictionary] as? [CFString: Any]) ?? [:]

        // Capture date — prefer EXIF DateTimeOriginal (true shutter time) over TIFF
        // DateTime (last modified within the camera).
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            m.captureDate = Self.exifDateFormatter.date(from: s)
        } else if let s = tiff[kCGImagePropertyTIFFDateTime] as? String {
            m.captureDate = Self.exifDateFormatter.date(from: s)
        }

        m.cameraMake = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        m.cameraModel = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        m.lens = (exif[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces)
        m.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        m.aperture = exif[kCGImagePropertyExifFNumber] as? Double
        m.focalLengthMM = exif[kCGImagePropertyExifFocalLength] as? Double

        // Shutter as a fraction string like "1/250 s" — exposure time arrives as a
        // decimal which is awful to read at small values.
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
            if exposure >= 1 {
                m.shutterSpeed = String(format: "%.1f s", exposure)
            } else {
                let denom = (1.0 / exposure).rounded()
                m.shutterSpeed = "1/\(Int(denom)) s"
            }
        }

        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            m.gpsLatitude = (latRef == "S") ? -lat : lat
            m.gpsLongitude = (lonRef == "W") ? -lon : lon
        }

        // IPTC keywords. Photos.app, Lightroom, and most pro DAMs write
        // user-applied keywords into the IPTC dictionary on export/save.
        // We surface them whether or not the file is inside a Photos library.
        let iptc = (props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
        if let kws = iptc[kCGImagePropertyIPTCKeywords] as? [String], !kws.isEmpty {
            m.iptcKeywords = kws.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let cap = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String,
           !cap.trimmingCharacters(in: .whitespaces).isEmpty {
            m.caption = cap.trimmingCharacters(in: .whitespaces)
        } else if let descr = tiff[kCGImagePropertyTIFFImageDescription] as? String,
                  !descr.trimmingCharacters(in: .whitespaces).isEmpty {
            // Fallback to TIFF ImageDescription, which some workflows use in
            // place of IPTC caption. Same semantic field for our purposes.
            m.caption = descr.trimmingCharacters(in: .whitespaces)
        }

        // Software: whichever app last wrote the file. Phones write "iOS X.Y";
        // desktops write "Photoshop 2024", "Lightroom 13.x", etc. Useful for
        // distinguishing camera-original files from edited copies.
        if let sw = tiff[kCGImagePropertyTIFFSoftware] as? String,
           !sw.trimmingCharacters(in: .whitespaces).isEmpty {
            m.software = sw.trimmingCharacters(in: .whitespaces)
        }

        // Color profile name — some files have a named ICC profile (Display
        // P3, sRGB, Adobe RGB, ProPhoto RGB). Distinguishes wide-gamut HEIC
        // from sRGB JPEG re-exports.
        if let profile = props[kCGImagePropertyProfileName] as? String,
           !profile.isEmpty {
            m.colorProfile = profile
        }

        // Star rating. Two common encodings: XMP (PhotoshopRating) and IPTC
        // (Star Rating). ImageIO surfaces them in different keys depending
        // on the file format; try both via the umbrella property dict
        // (`kCGImagePropertyRawDictionary` etc. are sometimes nested).
        if let r = props["Rating" as CFString] as? Int { m.starRating = r }
        else if let r = iptc[kCGImagePropertyIPTCStarRating] as? Int { m.starRating = r }

        return m
    }

    /// EXIF dates use this string format (no time zone — it's the local time the
    /// shutter fired). Pinned with POSIX locale so weird user locales don't change it.
    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    // MARK: - videos

    private func extractVideo(url: URL) async -> FileMetadata {
        var m = FileMetadata()
        let asset = AVURLAsset(url: url)

        // Duration first — quick read from the asset header. Use try-await; failures
        // for unreadable files surface as zero-filled metadata rather than throwing.
        if let duration = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(duration)
            if s.isFinite, s > 0 { m.durationSeconds = s }
        }

        // Creation date — `creationDate` is the modern API (iOS/macOS 16+).
        if let date = try? await asset.load(.creationDate)?.load(.dateValue) {
            m.captureDate = date
        }

        // Audio presence — informational on the comparison panel.
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio) {
            m.hasAudio = !audioTracks.isEmpty
        }

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return m
        }

        let naturalSize: CGSize
        do {
            naturalSize = try await videoTrack.load(.naturalSize)
            m.pixelWidth = Int(naturalSize.width)
            m.pixelHeight = Int(naturalSize.height)
        } catch {
            // Some malformed assets fail naturalSize but succeed on duration; skip.
        }

        if let fps = try? await videoTrack.load(.nominalFrameRate), fps > 0 {
            m.nominalFPS = Double(fps)
        }
        if let bitrate = try? await videoTrack.load(.estimatedDataRate), bitrate > 0 {
            m.bitrateBps = Int(bitrate)
        }

        // Codec — the format description carries a four-char `mediaSubType`.
        if let descs = try? await videoTrack.load(.formatDescriptions),
           let d = descs.first {
            let codec = CMFormatDescriptionGetMediaSubType(d)
            m.codec = Self.fourCharString(codec)
        }

        return m
    }

    /// Convert AVFoundation/QuickTime four-char codec codes (e.g. `0x68766331` =
    /// "hvc1" = HEVC) to a readable string. Falls back to hex if the bytes aren't
    /// printable ASCII.
    private static func fourCharString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8)  & 0xFF),
            UInt8(code         & 0xFF),
        ]
        let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        if printable, let s = String(bytes: bytes, encoding: .ascii) {
            return s.trimmingCharacters(in: .whitespaces)
        }
        return String(format: "0x%08X", code)
    }
}

import Foundation

/// Parsed metadata for a single media file, surfaced in Preview mode's EXIF panel. A plain
/// Codable value type with everything optional — populated by `EXIFService` (Phase 4) from
/// ImageIO (photos) or AVFoundation (video). Not persisted; recomputed on demand.
struct EXIFData: Codable, Equatable {
    // File-level
    var fileName: String?
    var fileSizeBytes: Int64?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var colorProfile: String?
    var fileType: String?

    // Capture
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: String?
    var aperture: String?
    var shutterSpeed: String?
    var iso: String?
    var captureDate: String?

    // Location
    var latitude: Double?
    var longitude: Double?

    // Media-specific
    var durationSeconds: Double?

    /// Convenience: a "4032 × 3024" dimension string when both axes are known.
    var dimensionsString: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w) × \(h)"
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    static let empty = EXIFData()
}

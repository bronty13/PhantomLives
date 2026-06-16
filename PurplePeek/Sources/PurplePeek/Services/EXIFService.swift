import Foundation
import ImageIO
import AVFoundation
import CoreGraphics

/// Reads metadata for a media file into an `EXIFData` value. Photos go through ImageIO
/// (`CGImageSource`), videos/audio through AVFoundation. All best-effort: any missing datum
/// is simply left nil.
enum EXIFService {

    static func load(for file: MediaFile) async -> EXIFData {
        switch file.mediaType {
        case .photo: return loadImage(file)
        case .video: return await loadAV(file, isVideo: true)
        case .audio: return await loadAV(file, isVideo: false)
        }
    }

    // MARK: - Photos (ImageIO)

    private static func loadImage(_ file: MediaFile) -> EXIFData {
        var data = base(file)
        guard let src = CGImageSourceCreateWithURL(file.fileURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return data }

        data.pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        data.pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        data.colorProfile = props[kCGImagePropertyProfileName] as? String

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            data.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            data.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            data.lensModel = exif[kCGImagePropertyExifLensModel] as? String
            if let fl = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue {
                data.focalLength = String(format: "%.0f mm", fl)
            }
            if let fn = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue {
                data.aperture = String(format: "f/%.1f", fn)
            }
            if let exp = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue, exp > 0 {
                data.shutterSpeed = exp < 1 ? "1/\(Int((1 / exp).rounded())) s" : String(format: "%.1f s", exp)
            }
            if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoArr.first {
                data.iso = "ISO \(iso.intValue)"
            }
            data.captureDate = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue {
                let ref = gps[kCGImagePropertyGPSLatitudeRef] as? String
                data.latitude = (ref == "S") ? -lat : lat
            }
            if let lon = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue {
                let ref = gps[kCGImagePropertyGPSLongitudeRef] as? String
                data.longitude = (ref == "W") ? -lon : lon
            }
        }
        return data
    }

    // MARK: - Video / audio (AVFoundation)

    private static func loadAV(_ file: MediaFile, isVideo: Bool) async -> EXIFData {
        var data = base(file)
        let asset = AVURLAsset(url: file.fileURL)

        if let duration = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(duration)
            if secs.isFinite, secs > 0 { data.durationSeconds = secs }
        }

        if isVideo, let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first, let size = try? await track.load(.naturalSize) {
            data.pixelWidth = Int(abs(size.width))
            data.pixelHeight = Int(abs(size.height))
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyModel:
                    data.cameraModel = try? await item.load(.stringValue)
                case .commonKeyMake:
                    data.cameraMake = try? await item.load(.stringValue)
                case .commonKeyCreationDate:
                    data.captureDate = try? await item.load(.stringValue)
                default:
                    break
                }
            }
        }
        return data
    }

    // MARK: - Shared

    private static func base(_ file: MediaFile) -> EXIFData {
        var d = EXIFData.empty
        d.fileName = file.fileName
        d.fileSizeBytes = file.fileSize
        d.fileType = file.mediaType.label
        return d
    }
}

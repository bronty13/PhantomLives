import Foundation
import AVFoundation
import AppKit

/// Pure helpers for the filesystem video-import path: pull a poster frame from a
/// movie file (for the strip thumbnail) and read its pixel dimensions. Kept
/// separate from the import service so the AVFoundation work is isolated. The
/// video's *bytes* are stored verbatim as an encrypted BLOB — we never
/// transcode; this only produces the still used for previews.
enum VideoProcessing {

    struct Poster {
        /// JPEG-encoded still pulled from early in the video.
        var jpeg: Data
        /// Pixel dimensions of the video track (orientation-corrected).
        var width: Int
        var height: Int
    }

    /// Decode a representative still + dimensions from a movie file. Returns nil
    /// if the file has no video track or can't be read.
    static func poster(from url: URL, maxEdge: CGFloat = ImageProcessing.maxImageEdge) async -> Poster? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        // Orientation-corrected natural size.
        let (naturalSize, transform): (CGSize, CGAffineTransform)
        if let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            naturalSize = loaded.0
            transform = loaded.1
        } else {
            naturalSize = .zero
            transform = .identity
        }
        let oriented = naturalSize.applying(transform)
        let w = Int(abs(oriented.width).rounded())
        let h = Int(abs(oriented.height).rounded())

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxEdge, height: maxEdge)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        // Aim ~1s in (a black leader frame is common at t=0); clamp to duration.
        let duration = (try? await asset.load(.duration)) ?? .zero
        let target = duration.seconds > 1.2 ? CMTime(seconds: 1.0, preferredTimescale: 600) : .zero

        guard let cgImage = try? await generator.image(at: target).image else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }

        return Poster(jpeg: jpeg,
                      width: w > 0 ? w : rep.pixelsWide,
                      height: h > 0 ? h : rep.pixelsHigh)
    }
}

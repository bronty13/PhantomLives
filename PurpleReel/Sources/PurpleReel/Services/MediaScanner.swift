import Foundation
import AVFoundation

actor MediaScanner {
    private let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "qt", "mxf", "avi", "mkv"
    ]
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tif", "tiff", "raw", "dng", "cr2", "nef", "arw"
    ]
    private let audioExtensions: Set<String> = [
        "wav", "aif", "aiff", "mp3", "m4a", "flac", "caf"
    ]

    private var allExtensions: Set<String> {
        videoExtensions.union(imageExtensions).union(audioExtensions)
    }

    /// Recursive walk of `root` building a fresh `Asset` per matching file.
    /// `progress` is called on the actor's queue; callers should hop to
    /// the main actor to mutate UI.
    func scan(root: URL, progress: @escaping (Int) -> Void) async throws -> [Asset] {
        var results: [Asset] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
        ]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true { continue }
            let ext = url.pathExtension.lowercased()
            guard allExtensions.contains(ext) else { continue }

            var asset = Asset(
                rowId: nil,
                path: url.path,
                filename: url.lastPathComponent,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? Date(),
                codec: nil,
                widthPx: nil,
                heightPx: nil,
                durationSeconds: nil,
                frameRate: nil,
                sha1: nil,
                addedAt: Date()
            )

            if videoExtensions.contains(ext) {
                await enrichVideoMetadata(into: &asset, url: url)
            }
            results.append(asset)
            if results.count % 50 == 0 { progress(results.count) }
        }
        progress(results.count)
        return results
    }

    private func enrichVideoMetadata(into asset: inout Asset, url: URL) async {
        let avAsset = AVURLAsset(url: url)
        do {
            let duration = try await avAsset.load(.duration)
            asset.durationSeconds = CMTimeGetSeconds(duration)
            let tracks = try await avAsset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                asset.widthPx = Int(abs(size.width))
                asset.heightPx = Int(abs(size.height))
                let nominalRate = try await track.load(.nominalFrameRate)
                asset.frameRate = Double(nominalRate)
                let formats = try await track.load(.formatDescriptions)
                if let fmt = formats.first {
                    let subtype = CMFormatDescriptionGetMediaSubType(fmt)
                    asset.codec = fourCCToString(subtype)
                }
            }
        } catch {
            NSLog("[PurpleReel] video metadata load failed for \(url.lastPathComponent): \(error)")
        }
    }

    private func fourCCToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

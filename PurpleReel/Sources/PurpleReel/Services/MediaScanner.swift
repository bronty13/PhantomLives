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

    /// Shallow scan — direct children of `root` only, no recursion.
    /// Used by `AppState.navigateAndShallowScan(_:)` for Kyno-style
    /// "select a folder → see media files at the top level
    /// immediately" behaviour. Symlink-aware so `/Volumes/Macintosh HD`
    /// resolves to `/` before listing.
    func scanShallow(root: URL) async throws -> [Asset] {
        let fm = FileManager.default
        let resolved = root.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        ]
        let entries = (try? fm.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        var results: [Asset] = []
        for url in entries {
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true { continue }
            let ext = url.pathExtension.lowercased()
            guard allExtensions.contains(ext) else { continue }
            var asset = Asset(
                rowId: nil,
                path: url.path,
                filename: url.lastPathComponent,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? Date(),
                codec: nil, widthPx: nil, heightPx: nil,
                durationSeconds: nil, frameRate: nil,
                sha1: nil, addedAt: Date(),
                audioCodec: nil, recordedAt: nil
            )
            if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
                await enrichVideoMetadata(into: &asset, url: url)
            }
            results.append(asset)
        }
        return results
    }

    /// Recursive walk of `root` building a fresh `Asset` per matching file.
    /// `progress` is called on the actor's queue; callers should hop to
    /// the main actor to mutate UI.
    ///
    /// Honors `ignoredFilesGlob` from Settings → Advanced: a
    /// `;`-separated list of fnmatch-style globs ("tmp;*backup;.cache").
    /// Each enumerated path's last component is matched against every
    /// glob; on a hit the file is skipped (and if it's a directory,
    /// its children too via `enumerator.skipDescendants()`).
    func scan(root: URL, progress: @escaping (Int) -> Void) async throws -> [Asset] {
        var results: [Asset] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
        ]
        let ignoreGlobs = Self.parseIgnoredGlobs(
            UserDefaults.standard.string(forKey: "ignoredFilesGlob") ?? ""
        )

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let last = url.lastPathComponent
            // Glob match — early out for directories so we don't walk
            // them at all.
            if !ignoreGlobs.isEmpty, ignoreGlobs.contains(where: { fnmatch(last, $0) }) {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
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
                addedAt: Date(),
                audioCodec: nil,
                recordedAt: nil
            )

            if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
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
            // Audio codec — read first audio track's format four-CC.
            // Works for assets that have an audio track regardless of
            // whether they have a video track.
            let audioTracks = try await avAsset.loadTracks(withMediaType: .audio)
            if let aTrack = audioTracks.first {
                let formats = try await aTrack.load(.formatDescriptions)
                if let fmt = formats.first {
                    let subtype = CMFormatDescriptionGetMediaSubType(fmt)
                    asset.audioCodec = fourCCToString(subtype)
                }
            }
            // Camera-set creation date. AVMetadata is the modern path
            // (load(.creationDate) on AVURLAsset returns the same
            // value the container's mdta atom carries on iPhone /
            // most prosumer cameras).
            if let creationDate = try await avAsset.load(.creationDate)?
                .load(.dateValue) {
                asset.recordedAt = creationDate
            }
        } catch {
            NSLog("[PurpleReel] video metadata load failed for \(url.lastPathComponent): \(error)")
        }
    }

    /// Parse the `ignoredFilesGlob` defaults string into individual
    /// patterns. Splits on `;`, strips whitespace, drops empty entries.
    static func parseIgnoredGlobs(_ raw: String) -> [String] {
        raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Tiny fnmatch — supports `*`, `?`, and literal characters.
    /// Anchors at both ends. Sufficient for the Settings → Advanced
    /// ignore patterns; full POSIX fnmatch would be overkill.
    private nonisolated func fnmatch(_ name: String, _ pattern: String) -> Bool {
        Self.fnmatchImpl(Array(name), Array(pattern))
    }

    private static func fnmatchImpl(_ name: [Character], _ pat: [Character]) -> Bool {
        var ni = 0, pi = 0
        var star = -1, sBack = 0
        while ni < name.count {
            if pi < pat.count, pat[pi] == name[ni] || pat[pi] == "?" {
                ni += 1; pi += 1
            } else if pi < pat.count, pat[pi] == "*" {
                star = pi; sBack = ni; pi += 1
            } else if star != -1 {
                pi = star + 1; sBack += 1; ni = sBack
            } else {
                return false
            }
        }
        while pi < pat.count, pat[pi] == "*" { pi += 1 }
        return pi == pat.count
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

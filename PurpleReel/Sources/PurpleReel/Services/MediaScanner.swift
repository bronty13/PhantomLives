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
        let volume = Self.resolveVolume(forPath: resolved.path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey,
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
                audioCodec: nil, recordedAt: nil,
                createdAt: values.creationDate
            )
            asset.volumeUUID  = volume.uuid
            asset.volumeLabel = volume.label
            if let cached = WorkspaceCacheService.loadIfFresh(for: url.path) {
                applyCachedTech(cached.tech, to: &asset)
            } else if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
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
        // Two-phase scan (parallelized 2026-05-18, builds 360+):
        //
        //   Phase A — walk the FileManager enumerator serially,
        //   build Asset stubs with filesystem-only fields, and tag
        //   each stub for AVAsset enrichment if needed.
        //   Cheap (single-threaded stat() per file); ~3-10ms per
        //   1000 files on local SSD.
        //
        //   Phase B — parallel AVAsset metadata probes via a
        //   bounded TaskGroup (max 6 concurrent — Apple Silicon's
        //   hardware HEVC decoder serializes past that point, and
        //   piling more tasks just burns CPU on context switches).
        //   Cuts cold-scan wall time roughly 4-5× on
        //   1000+ video workspaces vs the previous serial path.
        let fm = FileManager.default
        let volume = Self.resolveVolume(forPath: root.path)
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey,
        ]
        let ignoreGlobs = Self.parseIgnoredGlobs(
            UserDefaults.standard.string(forKey: "ignoredFilesGlob") ?? ""
        )

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        // ---- Phase A: build stubs serially ------------------------
        var stubs: [Asset] = []
        // Index into `stubs` for each file that still needs AVAsset
        // enrichment (i.e. video/audio with no fresh sidecar cache).
        var needsEnrich: [(index: Int, url: URL)] = []

        while let object = enumerator.nextObject() {
            guard let url = object as? URL else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            let last = url.lastPathComponent
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
                recordedAt: nil,
                createdAt: values.creationDate
            )
            asset.volumeUUID  = volume.uuid
            asset.volumeLabel = volume.label

            if let cached = WorkspaceCacheService.loadIfFresh(for: url.path) {
                applyCachedTech(cached.tech, to: &asset)
                stubs.append(asset)
            } else if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
                stubs.append(asset)
                needsEnrich.append((stubs.count - 1, url))
            } else {
                stubs.append(asset)
            }
        }

        // ---- Phase B: parallel AVAsset enrichment -----------------
        // Standard bounded-concurrency-TaskGroup pattern: prime up
        // to `maxConcurrent` tasks; when one completes, start the
        // next pending one. Keeps exactly `maxConcurrent` tasks in
        // flight until the queue is drained.
        let maxConcurrent = 6
        if !needsEnrich.isEmpty {
            await withTaskGroup(of: (Int, AVTech).self) { group in
                var cursor = 0
                let total = needsEnrich.count
                func enqueueNext() {
                    guard cursor < total else { return }
                    let (idx, url) = needsEnrich[cursor]
                    cursor += 1
                    group.addTask {
                        let tech = await Self.loadAVTech(url: url)
                        return (idx, tech)
                    }
                }
                for _ in 0..<min(maxConcurrent, total) { enqueueNext() }
                var completed = 0
                while let (idx, tech) = await group.next() {
                    Self.applyAVTech(tech, to: &stubs[idx])
                    completed += 1
                    if completed % 50 == 0 || completed == total {
                        progress(stubs.count)
                    }
                    enqueueNext()
                }
            }
        }
        progress(stubs.count)
        return stubs
    }

    /// Tech fields produced by `loadAVTech`. Decoupled from `Asset`
    /// so it crosses the TaskGroup boundary without needing the
    /// caller's actor isolation.
    fileprivate struct AVTech: Sendable {
        var codec: String?
        var widthPx: Int?
        var heightPx: Int?
        var durationSeconds: Double?
        var frameRate: Double?
        var audioCodec: String?
        var recordedAt: Date?
        var isVFR: Bool?
    }

    /// Static so the TaskGroup child task can call it without
    /// reaching back into the actor. All work is on AVAsset which
    /// has its own internal concurrency.
    private static func loadAVTech(url: URL) async -> AVTech {
        var tech = AVTech()
        let avAsset = AVURLAsset(url: url)
        do {
            let duration = try await avAsset.load(.duration)
            tech.durationSeconds = CMTimeGetSeconds(duration)
            let tracks = try await avAsset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                tech.widthPx = Int(abs(size.width))
                tech.heightPx = Int(abs(size.height))
                let nominalRate = try await track.load(.nominalFrameRate)
                tech.frameRate = Double(nominalRate)
                let formats = try await track.load(.formatDescriptions)
                if let fmt = formats.first {
                    let subtype = CMFormatDescriptionGetMediaSubType(fmt)
                    tech.codec = fourCCStatic(subtype)
                }
                let minDur = try await track.load(.minFrameDuration)
                let minDurSec = CMTimeGetSeconds(minDur)
                if nominalRate > 0, minDurSec.isFinite, minDurSec > 0 {
                    let inferred = 1.0 / minDurSec
                    let relGap = abs(Double(nominalRate) - inferred) / Double(nominalRate)
                    tech.isVFR = relGap > 0.10
                }
            }
            let audioTracks = try await avAsset.loadTracks(withMediaType: .audio)
            if let track = audioTracks.first {
                let formats = try await track.load(.formatDescriptions)
                if let fmt = formats.first {
                    let subtype = CMFormatDescriptionGetMediaSubType(fmt)
                    tech.audioCodec = fourCCStatic(subtype)
                }
            }
            // Creation date — `commonMetadata` is reasonably cheap.
            let common = try await avAsset.load(.commonMetadata)
            for item in common where item.commonKey == .commonKeyCreationDate {
                if let date = try? await item.load(.dateValue) {
                    tech.recordedAt = date
                    break
                }
            }
        } catch {
            // Probe failure on one clip is non-fatal — just leave
            // the tech fields nil. The catalog row still gets the
            // filesystem-derived basics.
            NSLog("[PurpleReel] AVAsset probe failed for \(url.lastPathComponent): \(error)")
        }
        return tech
    }

    fileprivate static func applyAVTech(_ tech: AVTech, to asset: inout Asset) {
        asset.codec            = tech.codec
        asset.widthPx          = tech.widthPx
        asset.heightPx         = tech.heightPx
        asset.durationSeconds  = tech.durationSeconds
        asset.frameRate        = tech.frameRate
        asset.audioCodec       = tech.audioCodec
        asset.recordedAt       = tech.recordedAt
        asset.isVFR            = tech.isVFR
    }

    /// Static fourCC helper — the instance version lives below for
    /// shallow-scan compatibility, but TaskGroup children need a
    /// non-isolated version they can call directly.
    private static func fourCCStatic(_ code: FourCharCode) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((code >> 24) & 0xFF) ?? "."),
            Character(UnicodeScalar((code >> 16) & 0xFF) ?? "."),
            Character(UnicodeScalar((code >> 8) & 0xFF) ?? "."),
            Character(UnicodeScalar(code & 0xFF) ?? "."),
        ]
        return String(chars)
    }

    /// Hydrate `asset` from a sidecar's technical block. The user
    /// portion is applied later by `WorkspaceCacheService.hydrateUserMetadata`
    /// — that hop has to live on the main actor because it touches
    /// `DatabaseService`.
    private func applyCachedTech(_ tech: WorkspaceCacheService.Tech,
                                  to asset: inout Asset) {
        asset.codec              = tech.codec
        asset.widthPx            = tech.widthPx
        asset.heightPx           = tech.heightPx
        asset.durationSeconds    = tech.durationSeconds
        asset.frameRate          = tech.frameRate
        asset.audioCodec         = tech.audioCodec
        asset.recordedAt         = tech.recordedAt
        asset.createdAt          = tech.createdAt ?? asset.createdAt
        asset.isVFR              = tech.isVFR
        asset.sha1               = tech.sha1
        asset.posterFrameSeconds = tech.posterFrameSeconds
    }

    /// Resolve the (volume UUID, volume label) for `path`. Called
    /// once per scan rather than per file — same volume across the
    /// whole tree. Returns nils when the OS won't answer (boot
    /// volume on older macOS, FUSE mounts, edge cases).
    static func resolveVolume(forPath path: String) -> (uuid: String?, label: String?) {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeIdentifierKey,
            .volumeLocalizedNameKey,
            .volumeURLKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        // volumeIdentifier is `Any` (CFData under the hood). Coerce
        // to NSObject then describe — stable enough for our use.
        var uuid: String? = nil
        if let id = values?.volumeIdentifier as? NSObject {
            uuid = id.description
        }
        return (uuid, values?.volumeLocalizedName)
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
                // VFR vs CFR heuristic. `minFrameDuration` is the
                // shortest interval AVFoundation ever sees between
                // two adjacent frames. For a CFR track it equals
                // `1 / nominalFrameRate`. For VFR (iPhone footage,
                // screen recordings, some action-cam high-speed
                // modes), the minimum interval is meaningfully
                // tighter than the nominal-average rate would
                // predict. We threshold the relative gap at 10%
                // to absorb 23.976-vs-24 family noise and round-
                // off in `nominalFrameRate`. Cheap — both values
                // come from the same track-load we already do for
                // the codec / size / nominal-rate.
                let minDur = try await track.load(.minFrameDuration)
                let minDurSec = CMTimeGetSeconds(minDur)
                if nominalRate > 0,
                   minDurSec.isFinite, minDurSec > 0 {
                    let inferred = 1.0 / minDurSec
                    let relGap = abs(Double(nominalRate) - inferred)
                                  / Double(nominalRate)
                    asset.isVFR = relGap > 0.10
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

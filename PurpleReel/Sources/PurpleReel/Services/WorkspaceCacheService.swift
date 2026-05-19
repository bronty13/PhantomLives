import Foundation

/// Shared workspace cache for NAS / SAN team browsing
/// (Kyno-parity row 7).
///
/// Lays a hidden `.purplereel/<filename>.json` next to each piece
/// of media when the user opts in via Settings → Workspace Cache.
/// The sidecar carries:
///   - Technical metadata (codec/dims/fps/duration/audioCodec/
///     recordedAt/createdAt/isVFR/sha1/posterFrameSeconds) so a
///     second user opening the same volume doesn't have to wait
///     for AVAsset probes on every clip.
///   - User metadata (rating, tags, clipMetadata log fields,
///     markers, subclips) so the team inherits everything that's
///     been logged so far.
///
/// Thumbnails and waveforms are deliberately *not* in the cache:
/// they regenerate cheaply and depend on local hardware /
/// color-management state. Centralized SQLite stays the source of
/// truth for the local session; sidecars are advisory.
///
/// Conflict handling: last-writer-wins. Real merge is out of scope
/// for v1 — two users editing the same clip concurrently will
/// overwrite each other. Document in the help text.
///
/// All writes are best-effort. Read-only volumes silently skip.
enum WorkspaceCacheService {

    /// Schema version. Bump when changing the JSON shape so the
    /// reader can refuse incompatible older sidecars instead of
    /// half-decoding them.
    static let currentVersion = 1

    /// Settings flag name. Lives in UserDefaults so any actor /
    /// service can poll without threading a binding through.
    static let enabledDefaultsKey = "workspaceCacheEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    // MARK: - Encoded payload

    struct Payload: Codable {
        var version: Int = currentVersion
        var filename: String
        var sizeBytes: Int64
        var modifiedAt: Date
        var tech: Tech
        var user: User
        var markers: [MarkerPayload]
        var subclips: [SubclipPayload]
    }
    struct Tech: Codable {
        var codec: String?
        var widthPx: Int?
        var heightPx: Int?
        var durationSeconds: Double?
        var frameRate: Double?
        var audioCodec: String?
        var recordedAt: Date?
        var createdAt: Date?
        var isVFR: Bool?
        var sha1: String?
        var posterFrameSeconds: Double?
    }
    struct User: Codable {
        var ratingStars: Int?
        var ratingColorLabel: String?
        var ratingDescription: String?
        var tags: [String] = []
        var title: String?
        var description: String?
        var reel: String?
        var scene: String?
        var shot: String?
        var take: String?
        var angle: String?
        var camera: String?
        var audioChannelNames: String?
    }
    struct MarkerPayload: Codable {
        var timecodeIn: Double
        var timecodeOut: Double?
        var note: String?
    }
    struct SubclipPayload: Codable {
        var name: String
        var timecodeIn: Double
        var timecodeOut: Double
    }

    // MARK: - Path helpers

    /// `<dir-of-asset>/.purplereel/<filename>.json`. Idempotent —
    /// directory is created on demand by the writer.
    static func sidecarURL(for assetPath: String) -> URL {
        let url = URL(fileURLWithPath: assetPath)
        return url.deletingLastPathComponent()
            .appendingPathComponent(".purplereel", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent + ".json")
    }

    // MARK: - Read

    /// Load the sidecar if present, valid, and modtime-matched. We
    /// require the JSON's `modifiedAt` to equal the file's current
    /// mtime within 1 second; otherwise we treat the sidecar as
    /// stale and the caller falls back to a fresh probe.
    static func loadIfFresh(for assetPath: String) -> Payload? {
        let sidecar = sidecarURL(for: assetPath)
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.version <= currentVersion else { return nil }
        let attrs = (try? FileManager.default
            .attributesOfItem(atPath: assetPath)) ?? [:]
        guard let mod = attrs[.modificationDate] as? Date else { return nil }
        if abs(mod.timeIntervalSince(payload.modifiedAt)) > 1.0 { return nil }
        return payload
    }

    // MARK: - Write

    /// Best-effort sidecar write. Atomic via `Data.write(.atomic)`.
    /// Silently no-ops when the toggle is off or the destination
    /// volume rejects the write (read-only, permission denied).
    static func writePayload(_ payload: Payload, for assetPath: String) {
        guard isEnabled else { return }
        let sidecar = sidecarURL(for: assetPath)
        let dir = sidecar.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: sidecar, options: .atomic)
        } catch {
            // Don't blow up the caller — volume might be read-only.
            NSLog("[PurpleReel] workspace cache write skipped at \(sidecar.path): \(error)")
        }
    }

    /// Convenience: read the current DB state for one asset, build
    /// a `Payload`, and write it. Called after any mutation
    /// (rating, tag add/remove, marker add/remove, clip-metadata
    /// save, poster-frame change). Best-effort.
    @MainActor
    static func saveAsset(_ asset: Asset, db: DatabaseService) {
        guard isEnabled, let id = asset.rowId else { return }
        let tech = Tech(
            codec: asset.codec,
            widthPx: asset.widthPx,
            heightPx: asset.heightPx,
            durationSeconds: asset.durationSeconds,
            frameRate: asset.frameRate,
            audioCodec: asset.audioCodec,
            recordedAt: asset.recordedAt,
            createdAt: asset.createdAt,
            isVFR: asset.isVFR,
            sha1: asset.sha1,
            posterFrameSeconds: asset.posterFrameSeconds
        )
        let rating = (try? db.rating(assetId: id))
        let tagList = (try? db.tags(assetId: id))?.map { $0.name } ?? []
        let meta = (try? db.clipMetadata(assetId: id))
                  ?? ClipMetadata(assetId: id,
                                  title: nil, description: nil,
                                  reel: nil, scene: nil, shot: nil,
                                  take: nil, angle: nil, camera: nil)
        let markerList = (try? db.markers(assetId: id))?.map {
            MarkerPayload(timecodeIn: $0.timecodeIn,
                          timecodeOut: $0.timecodeOut,
                          note: $0.note)
        } ?? []
        let subclipList = (try? db.subclips(parentAssetId: id))?.map {
            SubclipPayload(name: $0.name,
                           timecodeIn: $0.timecodeIn,
                           timecodeOut: $0.timecodeOut)
        } ?? []
        let user = User(
            ratingStars: rating?.stars,
            ratingColorLabel: rating?.colorLabel,
            ratingDescription: rating?.description,
            tags: tagList,
            title: meta.title,
            description: meta.description,
            reel: meta.reel,
            scene: meta.scene,
            shot: meta.shot,
            take: meta.take,
            angle: meta.angle,
            camera: meta.camera,
            audioChannelNames: meta.audioChannelNames
        )
        let payload = Payload(
            filename: asset.filename,
            sizeBytes: asset.sizeBytes,
            modifiedAt: asset.modifiedAt,
            tech: tech,
            user: user,
            markers: markerList,
            subclips: subclipList
        )
        writePayload(payload, for: asset.path)
    }

    // MARK: - Prune orphans (C32 G1)

    /// Result of a single `pruneOrphans(under:)` sweep.
    struct PruneResult: Equatable {
        var scanned: Int       // total `.purplereel/*.json` files inspected
        var deleted: [URL]     // sidecars whose source no longer exists
        var failed: [(URL, String)]

        static func == (lhs: PruneResult, rhs: PruneResult) -> Bool {
            lhs.scanned == rhs.scanned
                && lhs.deleted == rhs.deleted
                && lhs.failed.count == rhs.failed.count
                && zip(lhs.failed, rhs.failed).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    /// Walk `<root>` recursively, find every `.purplereel/<file>.json`
    /// sidecar, and delete any whose corresponding source file is no
    /// longer present (i.e. orphaned by a delete/move that happened
    /// without re-saving the sidecar).
    ///
    /// The reader's modtime gate already protects against stale
    /// payloads for files that DO exist; this sweeps the other case
    /// — files that are gone — so `.purplereel/` directories don't
    /// accumulate dead weight over a NAS's lifetime. Best-effort;
    /// permission errors get reported via `PruneResult.failed`.
    static func pruneOrphans(under root: URL) -> PruneResult {
        let fm = FileManager.default
        var result = PruneResult(scanned: 0, deleted: [], failed: [])
        // Note: NO `.skipsHiddenFiles` here — sidecars live under
        // `.purplereel/` which is hidden by convention. Skipping
        // hidden entries would skip the entire directory.
        guard let walker = fm.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return result }
        for case let url as URL in walker {
            // Sidecars are exactly `.json` under a `.purplereel` dir.
            guard url.pathExtension == "json",
                  url.deletingLastPathComponent().lastPathComponent == ".purplereel"
            else { continue }
            result.scanned += 1
            // The source file lives one level up at
            // `<parent-of-.purplereel>/<filename-without-.json>`.
            let sourceName = (url.lastPathComponent as NSString)
                .deletingPathExtension
            let sourcePath = url.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(sourceName).path
            if fm.fileExists(atPath: sourcePath) { continue }
            do {
                try fm.removeItem(at: url)
                result.deleted.append(url)
            } catch {
                result.failed.append((url, error.localizedDescription))
            }
        }
        return result
    }

    // MARK: - Hydrate

    /// Apply the user-metadata portion of a sidecar payload to the
    /// catalogue. Called once at scan-completion for every asset
    /// whose sidecar was fresh, only when the local DB has no user
    /// metadata for the asset yet — never overwrites a local edit.
    @MainActor
    static func hydrateUserMetadata(_ payload: Payload,
                                     assetId: Int64,
                                     db: DatabaseService) {
        // Rating: write only when nothing local.
        if let stars = payload.user.ratingStars, stars > 0,
           (try? db.rating(assetId: assetId)) == nil {
            try? db.setRating(assetId: assetId, stars: stars,
                              colorLabel: payload.user.ratingColorLabel,
                              description: payload.user.ratingDescription)
        }
        // Tags: union (additive — never removes local tags).
        let existing = Set(((try? db.tags(assetId: assetId)) ?? [])
                            .map { $0.name.lowercased() })
        for t in payload.user.tags
            where !existing.contains(t.lowercased()) {
            _ = try? db.addTag(name: t, assetId: assetId)
        }
        // Clip metadata: fill empty slots only.
        var meta = (try? db.clipMetadata(assetId: assetId))
                   ?? ClipMetadata(assetId: assetId,
                                   title: nil, description: nil,
                                   reel: nil, scene: nil, shot: nil,
                                   take: nil, angle: nil, camera: nil)
        var changed = false
        func fill(_ source: String?, into field: inout String?) {
            if (field ?? "").isEmpty, let v = source, !v.isEmpty {
                field = v; changed = true
            }
        }
        fill(payload.user.title,       into: &meta.title)
        fill(payload.user.description, into: &meta.description)
        fill(payload.user.reel,        into: &meta.reel)
        fill(payload.user.scene,       into: &meta.scene)
        fill(payload.user.shot,        into: &meta.shot)
        fill(payload.user.take,        into: &meta.take)
        fill(payload.user.angle,       into: &meta.angle)
        fill(payload.user.camera,      into: &meta.camera)
        fill(payload.user.audioChannelNames, into: &meta.audioChannelNames)
        if changed { try? db.setClipMetadata(meta) }

        // Markers: additive with ±1/fps + note de-dupe.
        let existingMarkers = (try? db.markers(assetId: assetId)) ?? []
        let fps = payload.tech.frameRate ?? 30
        let epsilon = max(0.05, 1.0 / max(fps, 1))
        for m in payload.markers {
            let dup = existingMarkers.contains {
                abs($0.timecodeIn - m.timecodeIn) <= epsilon
                && ($0.note ?? "") == (m.note ?? "")
            }
            if !dup {
                _ = try? db.addMarker(
                    assetId: assetId,
                    timecodeIn: m.timecodeIn,
                    timecodeOut: m.timecodeOut,
                    note: m.note
                )
            }
        }
        // Subclips: additive with name + timecode-range de-dupe.
        let existingSubs = (try? db.subclips(parentAssetId: assetId)) ?? []
        for s in payload.subclips {
            let dup = existingSubs.contains {
                $0.name == s.name
                && abs($0.timecodeIn - s.timecodeIn) <= epsilon
                && abs($0.timecodeOut - s.timecodeOut) <= epsilon
            }
            if !dup {
                _ = try? db.addSubclip(
                    parentAssetId: assetId, name: s.name,
                    timecodeIn: s.timecodeIn, timecodeOut: s.timecodeOut
                )
            }
        }
    }
}

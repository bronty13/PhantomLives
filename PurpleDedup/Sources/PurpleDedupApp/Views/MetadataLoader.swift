import SwiftUI
import PurpleDedupCore

/// Owns the per-cluster metadata state the comparison pane reads from:
/// EXIF + Photos-app fields, reverse-geocoded place names, and the Photos
/// lookup-index hits. Extracted from `ComparisonView` so the host view stays
/// a thin composition layer.
///
/// `@MainActor` because every published property is read by SwiftUI views;
/// the heavy work (ImageIO + PhotoKit + GeoCache + DB lookups) runs in
/// detached / TaskGroup children and writes back via `await MainActor.run`.
@MainActor
final class MetadataLoader: ObservableObject {
    @Published var metadata: [URL: FileMetadata] = [:]
    @Published var loading: Bool = false
    /// Reverse-geocoded place names per file URL. Filled async after metadata
    /// resolves; missing entries fall back to raw lat/lon in the table.
    @Published var placeNames: [URL: String] = [:]
    /// URLs in the current selection whose content hash is in the host's
    /// `photosLookupHashes`. Per-file DB lookup; cheap when warm.
    @Published var lookupHits: Set<URL> = []

    /// Reset and reload for a new selection. `task(id: selection.id)` in the
    /// host cancels and re-launches this on each selection change.
    func load(for selection: ClusterSelection, photosLookupHashes: Set<String>) async {
        loading = true
        defer { loading = false }
        let urls = selection.files.map(\.url)
        let extractor = MetadataExtractor()
        var results: [URL: FileMetadata] = [:]

        await withTaskGroup(of: (URL, FileMetadata).self) { group in
            for url in urls {
                group.addTask {
                    var meta = await extractor.extract(url: url)
                    // Enrich with Photos-app metadata when the file lives in a
                    // `.photoslibrary`. PhotoKit fetch is a no-op for non-
                    // library paths and for auth states < .limited.
                    if url.path.contains(".photoslibrary/") {
                        if let p = await PhotoKitDeletionService.shared.fetchMetadata(forPath: url) {
                            meta.photosAlbumNames = p.albumNames
                            meta.photosMediaSubtypes = p.mediaSubtypes
                            meta.photosIsFavorite = p.isFavorite
                            meta.photosIsHidden = p.isHidden
                            meta.photosCreationDate = p.creationDate
                            meta.photosHasAdjustments = p.hasAdjustments
                            meta.photosBurstIdentifier = p.burstIdentifier
                            meta.photosIsBurstRepresentative = p.isBurstRepresentative
                        }
                    }
                    return (url, meta)
                }
            }
            for await (url, m) in group { results[url] = m }
        }
        if Task.isCancelled { return }
        self.metadata = results

        // Reverse-geocode any GPS coords. Cache-coalesced through `GeoCache`
        // so the same neighborhood doesn't burn N requests on a 12-photo
        // burst. Best-effort: failures leave the row showing raw lat/lon.
        // Runs in a detached task so the metadata table appears immediately
        // and place names fill in as they resolve.
        Task { [urls, results, weak self] in
            for url in urls {
                if Task.isCancelled { return }
                guard let m = results[url],
                      let lat = m.gpsLatitude, let lon = m.gpsLongitude else { continue }
                if let name = await GeoCache.shared.placeName(latitude: lat, longitude: lon) {
                    await MainActor.run {
                        // Only commit if the user is still on this cluster;
                        // otherwise placeNames pollutes future sessions.
                        guard let self = self, self.metadata[url] != nil else { return }
                        self.placeNames[url] = name
                    }
                }
            }
        }

        // Lookup-mode badge population. Per-file DB read; the cache already
        // holds content hashes for files that were exact-stage candidates.
        if !photosLookupHashes.isEmpty {
            var hits: Set<URL> = []
            if let db = try? Database.openDefault() {
                for url in urls {
                    if let f = try? db.file(at: url.path),
                       let blob = f.contentHash {
                        let hex = blob.map { String(format: "%02x", $0) }.joined()
                        if photosLookupHashes.contains(hex) {
                            hits.insert(url)
                        }
                    }
                }
            }
            if Task.isCancelled { return }
            self.lookupHits = hits
        } else {
            self.lookupHits = []
        }
    }

    // MARK: - row helpers (used by MetadataDiffTable)

    /// All metadata row IDs that appear on any file in the cluster — preserves
    /// the natural display order from `FileMetadata.rows()` by interleaving the
    /// union.
    func unifiedRowKeys(for s: ClusterSelection) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for f in s.files {
            guard let m = metadata[f.url] else { continue }
            for row in m.rows() where !seen.contains(row.id) {
                seen.insert(row.id)
                ordered.append(row.id)
            }
        }
        return ordered
    }

    func valuesForRow(_ id: String, in s: ClusterSelection) -> [URL: String] {
        var out: [URL: String] = [:]
        for f in s.files {
            guard let m = metadata[f.url] else { continue }
            if let row = m.rows().first(where: { $0.id == id }) {
                if id == "gps", let place = placeNames[f.url] {
                    // Decorate with the reverse-geocoded place when known;
                    // raw coords stay visible for precision-sensitive eyes.
                    out[f.url] = "\(place)  ·  \(row.value)"
                } else {
                    out[f.url] = row.value
                }
            }
        }
        return out
    }

    func labelFor(_ id: String) -> String {
        // Mirror the labels FileMetadata.Row uses; we look one up by walking
        // any metadata that happens to contain this id.
        for m in metadata.values {
            if let row = m.rows().first(where: { $0.id == id }) { return row.label }
        }
        return id
    }
}

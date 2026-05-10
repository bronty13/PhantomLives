import Foundation
import PurpleDedupCore

/// On-demand detection runs that the user kicks off from the bulk-actions
/// strip: burst series (rapid-fire photo sequences) and rotated copies
/// (the same photo at 90°/180°/270°). Both are extra passes over the
/// already-walked photo set; neither participates in the main scan
/// pipeline. Lifted out of `ContentView` so the runners live next to the
/// other coordinators (`Scan`, `Trash`).
///
/// Both runs exclude files that are already in an exact cluster — byte-
/// identical files rotated/burst-shot identically are already caught
/// there. Files in similar_photo clusters ARE eligible because a
/// perceptual match doesn't preclude a rotated/burst neighbour
/// existing elsewhere in the scan.
struct DetectionCoordinator {

    /// Cluster rapid-fire photo bursts via EXIF capture-date + pHash.
    /// Returns the resulting cluster list and the count of dated
    /// candidates we were able to hash (the status message includes
    /// that for context — "found N bursts across M dated photos").
    struct BurstOutcome {
        let clusters: [BurstClusterer.Cluster]
        let datedCandidatesCount: Int
    }

    func detectBursts(
        photos: [DiscoveredFile],
        exactClusters: [ExactClusterer.Cluster]
    ) async -> BurstOutcome {
        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })
        let candidates = photos.filter { !exactURLs.contains($0.url) }

        let extractor = MetadataExtractor()
        let hasher = PerceptualHasher()

        var entries: [BurstClusterer.Entry] = []
        await withTaskGroup(of: BurstClusterer.Entry?.self) { group in
            for f in candidates {
                group.addTask {
                    let m = await extractor.extract(url: f.url)
                    guard let date = m.captureDate else { return nil }
                    guard let h = try? hasher.hash(imageAt: f.url) else { return nil }
                    return BurstClusterer.Entry(file: f, captureDate: date, phash: h.phash)
                }
            }
            for await e in group { if let e = e { entries.append(e) } }
        }

        let clusters = BurstClusterer().clusterBursts(entries: entries)
        return BurstOutcome(clusters: clusters, datedCandidatesCount: entries.count)
    }

    /// Cluster rotated copies by re-hashing each photo with all four
    /// rotations and matching across the family.
    struct RotatedOutcome {
        let clusters: [RotatedClusterer.Cluster]
        let candidatesCount: Int
    }

    func detectRotated(
        photos: [DiscoveredFile],
        exactClusters: [ExactClusterer.Cluster]
    ) async -> RotatedOutcome {
        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })
        let candidates = photos.filter { !exactURLs.contains($0.url) }

        let hasher = PerceptualHasher()
        var entries: [RotatedClusterer.Entry] = []
        await withTaskGroup(of: RotatedClusterer.Entry?.self) { group in
            // Bounded concurrency for the same VideoToolbox-HEVC reason
            // as the perceptual stage — HEIC decode goes through a
            // serialised hardware decoder that punishes high
            // concurrency.
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = candidates.makeIterator()
            var inFlight = 0
            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard let h = try? hasher.hashWithRotations(imageAt: next.url) else { return nil }
                    return RotatedClusterer.Entry(file: next, rotationHashes: h)
                }
            }
            for _ in 0..<limit { submit() }
            while inFlight > 0 {
                if let r = try? await group.next() {
                    inFlight -= 1
                    if let e = r { entries.append(e) }
                    submit()
                } else {
                    break
                }
            }
        }

        let clusters = RotatedClusterer().clusterRotated(entries: entries)
        return RotatedOutcome(clusters: clusters, candidatesCount: entries.count)
    }
}

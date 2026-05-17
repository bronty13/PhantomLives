import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Cluster of perceptually-similar takes; the highest-rated /
/// longest-duration / sharpest member surfaces as the "best take".
struct SimilarTakeCluster: Identifiable {
    let id = UUID()
    let assets: [Asset]
    let bestAsset: Asset
    let reason: String   // human-readable why-this-was-picked
}

/// "Best-takes" picker. For each video we sample the middle frame,
/// compute a 64-bit dHash (difference hash), and cluster pairs whose
/// Hamming distance is below the threshold. Inside each cluster we
/// rank by (rating desc → duration desc) and surface the winner.
///
/// dHash trade: it's cheap (one frame, one CIContext render, 8×9 grid)
/// and robust to small reframing / exposure shifts. It will not catch
/// takes that differ in framing significantly — but for "near-dupes
/// of the same scene", it's accurate enough and fast.
enum SimilarTakesService {

    /// Pairwise Hamming distance threshold for clustering. 10 ≈ 16%
    /// of bits — empirically a sweet spot from PurpleDedup tuning.
    static let hammingThreshold = 10

    static func findClusters(assets: [Asset],
                              ratings: [Int64: Rating],
                              onProgress: @escaping (Int, Int) -> Void) async -> [SimilarTakeCluster] {
        // Filter to video-only entries with a row id.
        let videos = assets.filter { asset in
            guard asset.rowId != nil else { return false }
            return ["mov", "mp4", "m4v", "qt"].contains(
                (asset.filename as NSString).pathExtension.lowercased()
            )
        }

        var hashes: [(Asset, UInt64)] = []
        hashes.reserveCapacity(videos.count)
        for (i, asset) in videos.enumerated() {
            onProgress(i, videos.count)
            if let hash = await dHashMiddleFrame(url: URL(fileURLWithPath: asset.path)) {
                hashes.append((asset, hash))
            }
        }
        onProgress(videos.count, videos.count)

        // Naive O(n²) pairing — fine for the few hundred clips a
        // PurpleReel project typically has. For 10k-clip libraries
        // we'd want a BK-tree (port from PurpleDedup) but it's not
        // needed yet.
        var parent = Array(0..<hashes.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var i = x
            while parent[i] != r { let nxt = parent[i]; parent[i] = r; i = nxt }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        for i in 0..<hashes.count {
            for j in (i+1)..<hashes.count {
                if hamming(hashes[i].1, hashes[j].1) <= hammingThreshold {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<hashes.count {
            groups[find(i), default: []].append(i)
        }
        var clusters: [SimilarTakeCluster] = []
        for indices in groups.values where indices.count > 1 {
            let groupAssets = indices.map { hashes[$0].0 }
            let (best, reason) = pickBest(in: groupAssets, ratings: ratings)
            clusters.append(SimilarTakeCluster(
                assets: groupAssets, bestAsset: best, reason: reason
            ))
        }
        // Longest cluster first.
        return clusters.sorted { $0.assets.count > $1.assets.count }
    }

    // MARK: - dHash

    /// Extract the middle frame and compute an 8x9 luminance dHash.
    /// Returns nil if extraction fails (corrupted file, etc.).
    private static func dHashMiddleFrame(url: URL) async -> UInt64? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let duration = try await asset.load(.duration)
            let mid = CMTime(seconds: max(0.5, CMTimeGetSeconds(duration) / 2),
                              preferredTimescale: 600)
            let cg = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: mid)]) { _, image, _, _, error in
                    if let image = image { cont.resume(returning: image) }
                    else { cont.resume(throwing: error ?? NSError(domain: "PurpleReel", code: -1)) }
                }
            }
            return dHash(cgImage: cg)
        } catch {
            return nil
        }
    }

    /// 64-bit dHash: scale to 9x8 grayscale, compare each pixel to its
    /// right neighbor, pack 8x8 = 64 comparison bits.
    private static func dHash(cgImage: CGImage) -> UInt64 {
        let w = 9, h = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hash: UInt64 = 0
        var bit = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                let a = pixels[y * w + x]
                let b = pixels[y * w + x + 1]
                if a > b { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private static func pickBest(in assets: [Asset],
                                  ratings: [Int64: Rating]) -> (Asset, String) {
        // (rating stars desc, duration desc) — ties broken by filename.
        let scored = assets.sorted { lhs, rhs in
            let lStars = (lhs.rowId.flatMap { ratings[$0]?.stars }) ?? 0
            let rStars = (rhs.rowId.flatMap { ratings[$0]?.stars }) ?? 0
            if lStars != rStars { return lStars > rStars }
            let lDur = lhs.durationSeconds ?? 0
            let rDur = rhs.durationSeconds ?? 0
            if lDur != rDur { return lDur > rDur }
            return lhs.filename < rhs.filename
        }
        let winner = scored.first!
        let stars = (winner.rowId.flatMap { ratings[$0]?.stars }) ?? 0
        let reason: String
        if stars > 0 {
            reason = "Highest rated (\(stars)★) in cluster of \(assets.count)"
        } else if let dur = winner.durationSeconds {
            reason = "Longest take (\(String(format: "%.1f", dur))s) in cluster of \(assets.count)"
        } else {
            reason = "Cluster of \(assets.count) similar takes"
        }
        return (winner, reason)
    }
}

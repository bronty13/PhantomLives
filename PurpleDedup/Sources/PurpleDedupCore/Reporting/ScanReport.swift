import Foundation

/// JSON-friendly report a CLI run can emit. Adding new cluster kinds is non-breaking —
/// consumers iterate `clusters` and switch on `kind`. New optional fields appear only on
/// the cluster types that have them.
public struct ScanReport: Codable, Sendable {

    public struct Cluster: Codable, Sendable {
        public let kind: String                      // "exact" | "similar_photo" | "similar_video"
        public let contentHash: String?              // exact: SHA256 hex
        public let sizeBytes: Int64?                 // exact only
        public let fileCount: Int
        public let reclaimableBytes: Int64
        public let maxPairwiseDistance: Int?         // similar_photo: pHash diameter
        public let maxPairwiseMeanDistance: Int?     // similar_video: aligned-mean diameter
        public let files: [File]
    }

    public struct File: Codable, Sendable {
        public let path: String
        public let sizeBytes: Int64
        public let modificationTimeISO: String
        public let isLocked: Bool
        public let phash: String?                    // hex, present on similar_photo
        public let dhash: String?
        public let width: Int?
        public let height: Int?
        public let durationSeconds: Double?          // similar_video only
        public let frameCount: Int?                  // similar_video only
    }

    public let appName: String
    public let appVersion: String
    public let generatedAtISO: String
    public let sources: [String]
    public let totalFilesScanned: Int
    public let totalCandidatesHashed: Int
    public let exactClusterCount: Int
    public let similarClusterCount: Int
    public let similarVideoClusterCount: Int
    public let totalClusters: Int
    public let totalReclaimableBytes: Int64
    public let similarityThreshold: Int?
    public let videoSimilarityThreshold: Int?
    public let clusters: [Cluster]

    public static func from(
        sources: [ScanSource],
        filesScanned: Int,
        candidatesHashed: Int,
        exactClusters: [ExactClusterer.Cluster],
        similarClusters: [PerceptualClusterer.Cluster],
        similarVideoClusters: [VideoClusterer.Cluster],
        similarityThreshold: Int,
        videoSimilarityThreshold: Int
    ) -> ScanReport {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let exactReport: [Cluster] = exactClusters.map { c in
            Cluster(
                kind: "exact",
                contentHash: c.contentHashHex,
                sizeBytes: c.sizeBytes,
                fileCount: c.files.count,
                reclaimableBytes: c.totalReclaimableBytes,
                maxPairwiseDistance: nil,
                maxPairwiseMeanDistance: nil,
                files: c.files.map {
                    File(
                        path: $0.url.path,
                        sizeBytes: $0.sizeBytes,
                        modificationTimeISO: isoFormatter.string(from: $0.modificationTime),
                        isLocked: $0.isLocked,
                        phash: nil, dhash: nil, width: nil, height: nil,
                        durationSeconds: nil, frameCount: nil
                    )
                }
            )
        }

        let similarReport: [Cluster] = similarClusters.map { c in
            Cluster(
                kind: "similar_photo",
                contentHash: nil,
                sizeBytes: nil,
                fileCount: c.files.count,
                reclaimableBytes: c.totalReclaimableBytes,
                maxPairwiseDistance: c.maxPairwiseDistance,
                maxPairwiseMeanDistance: nil,
                files: zip(c.files, c.hashes).map { (f, h) in
                    File(
                        path: f.url.path,
                        sizeBytes: f.sizeBytes,
                        modificationTimeISO: isoFormatter.string(from: f.modificationTime),
                        isLocked: f.isLocked,
                        phash: String(h.phash, radix: 16),
                        dhash: String(h.dhash, radix: 16),
                        width: h.width, height: h.height,
                        durationSeconds: nil, frameCount: nil
                    )
                }
            )
        }

        let similarVideoReport: [Cluster] = similarVideoClusters.map { c in
            Cluster(
                kind: "similar_video",
                contentHash: nil,
                sizeBytes: nil,
                fileCount: c.files.count,
                reclaimableBytes: c.totalReclaimableBytes,
                maxPairwiseDistance: nil,
                maxPairwiseMeanDistance: c.maxPairwiseMeanDistance,
                files: zip(c.files, c.fingerprints).map { (f, fp) in
                    File(
                        path: f.url.path,
                        sizeBytes: f.sizeBytes,
                        modificationTimeISO: isoFormatter.string(from: f.modificationTime),
                        isLocked: f.isLocked,
                        phash: nil, dhash: nil,
                        width: fp.width, height: fp.height,
                        durationSeconds: fp.durationSeconds,
                        frameCount: fp.frameHashes.count
                    )
                }
            )
        }

        let allClusters = exactReport + similarReport + similarVideoReport

        let totalReclaim =
            exactClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }
            + similarClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }
            + similarVideoClusters.reduce(Int64(0)) { $0 + $1.totalReclaimableBytes }

        return ScanReport(
            appName: PurpleDedup.appName,
            appVersion: PurpleDedup.coreVersion,
            generatedAtISO: isoFormatter.string(from: Date()),
            sources: sources.map { $0.url.path },
            totalFilesScanned: filesScanned,
            totalCandidatesHashed: candidatesHashed,
            exactClusterCount: exactClusters.count,
            similarClusterCount: similarClusters.count,
            similarVideoClusterCount: similarVideoClusters.count,
            totalClusters: allClusters.count,
            totalReclaimableBytes: totalReclaim,
            similarityThreshold: similarClusters.isEmpty ? nil : similarityThreshold,
            videoSimilarityThreshold: similarVideoClusters.isEmpty ? nil : videoSimilarityThreshold,
            clusters: allClusters
        )
    }

    public func toJSONData(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try enc.encode(self)
    }
}

import Foundation

/// Whether a candidate's file was found in the archive copies. A candidate is only
/// **deletable** when it's present in the primary AND at least one mirror (the ≥2-copy gate).
public struct VerificationResult: Sendable, Equatable {
    public let inPrimary: Bool
    public let mirrorsMatched: Int
    public var verified: Bool { inPrimary && mirrorsMatched >= 1 }
}

/// One purge-eligible asset plus its archive-verification verdict.
public struct PurgeCandidate: Sendable, Identifiable {
    public let uuid: String
    public let filename: String
    public let date: Date
    public let sizeBytes: Int
    public let ismissing: Bool
    public let verification: VerificationResult
    public var id: String { uuid }
    public var deletable: Bool { verification.verified }
}

/// The result of planning a purge: what's eligible, what's verified (safe to delete), and
/// what's not. Nothing here deletes anything — this is pure analysis the UI presents.
public struct PurgePlan: Sendable {
    public let cutoff: Date
    public let recordsConsidered: Int
    public let candidates: [PurgeCandidate]

    public var verified: [PurgeCandidate] { candidates.filter { $0.deletable } }
    public var unverified: [PurgeCandidate] { candidates.filter { !$0.deletable } }
    public var verifiedBytes: Int { verified.reduce(0) { $0 + $1.sizeBytes } }
    public var dateRange: (earliest: Date, latest: Date)? {
        let dates = candidates.map { $0.date }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return (lo, hi)
    }
}

public enum PurgePlanner {

    /// Pure core: given fetched records, the policy, and pre-built archive indices, produce
    /// the plan. Records already in the Photos trash are skipped. Eligibility re-applies the
    /// FULL `RetentionPolicy` (window + pinning) as a second safety net even though the query
    /// pre-filtered by date.
    public static func plan(
        records: [OsxphotosRecord],
        policy: RetentionPolicy,
        now: Date,
        primary: ArchiveIndex,
        mirrors: [ArchiveIndex]
    ) -> PurgePlan {
        var candidates: [PurgeCandidate] = []
        let cutoff = Calendar.current.date(byAdding: .day, value: -policy.keepWindowDays, to: now) ?? now

        for r in records {
            if r.intrash { continue }
            guard let asset = r.asPhotoAsset() else { continue }   // unparseable date → keep
            guard policy.isPurgeEligible(asset, asOf: now) else { continue }

            // Verify by FILENAME presence + cross-copy size consistency — NOT against the
            // Photos `original_filesize`. The export embeds metadata via `--exiftool`, so an
            // archived original is a few hundred bytes larger than its pre-export size; matching
            // the Photos size rejected ~all files (incident 2026-06-11). A candidate is verified
            // when the primary holds the named file AND a mirror holds a byte-identical copy
            // (their size-sets for that name intersect) → two consistent copies exist.
            let name = r.originalFilename ?? ""
            let primarySizes = name.isEmpty ? Set<Int>() : primary.sizes(forFilename: name)
            let inPrimary = !primarySizes.isEmpty
            let mirrorsMatched = inPrimary
                ? mirrors.filter { !$0.sizes(forFilename: name).isDisjoint(with: primarySizes) }.count
                : 0

            candidates.append(PurgeCandidate(
                uuid: r.uuid,
                filename: name.isEmpty ? "(unknown)" : name,
                date: asset.created,
                sizeBytes: r.originalFilesize ?? 0,   // Photos' pre-export size, for the freed-space estimate
                ismissing: r.ismissing,
                verification: VerificationResult(inPrimary: inPrimary, mirrorsMatched: mirrorsMatched)
            ))
        }

        return PurgePlan(cutoff: cutoff, recordsConsidered: records.count, candidates: candidates)
    }

    /// IO wrapper: run the osxphotos query, build archive indices from the profile's primary
    /// + mirrors, then plan. Throws if osxphotos can't be queried.
    public static func compute(
        osxphotos: String,
        profile: ArchiveProfile,
        now: Date,
        logger: AtticLogger? = nil
    ) throws -> PurgePlan {
        let cutoff = Calendar.current.date(byAdding: .day, value: -profile.retention.keepWindowDays, to: now) ?? now
        logger?.info("Purge preview: querying photos created before \(cutoff)…")
        let records = try PhotoMetadataQuery.recordsCreatedBefore(
            cutoff, osxphotos: osxphotos, libraryPath: profile.photosLibraryPath)
        logger?.info("Purge preview: \(records.count) candidate records; indexing archive…")

        let primaryIndex = ArchiveIndex.build(archiveRoot: profile.primaryArchiveRoot)
        let mirrorIndices = profile.mirrorArchiveRoots.map { ArchiveIndex.build(archiveRoot: $0) }
        logger?.info("Purge preview: primary index \(primaryIndex.fileCount) files; \(mirrorIndices.count) mirror(s).")

        let plan = plan(records: records, policy: profile.retention, now: now,
                        primary: primaryIndex, mirrors: mirrorIndices)
        logger?.info("Purge preview: \(plan.candidates.count) eligible, \(plan.verified.count) verified-in-≥2-copies, \(plan.unverified.count) unverified.")
        return plan
    }
}

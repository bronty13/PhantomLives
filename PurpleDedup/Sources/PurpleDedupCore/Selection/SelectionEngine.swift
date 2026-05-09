import Foundation

/// One selection-relevant fact set per file. Bundling all the inputs the rule
/// chain might want to inspect into a single value type means the engine itself
/// stays pure: in → out, no I/O, easy to unit-test, can run inside a tight loop
/// over thousands of clusters without per-call file system hits.
public struct FileForSelection: Sendable {
    public let url: URL
    public let sizeBytes: Int64
    public let modificationTime: Date
    public let metadata: FileMetadata
    public let isLocked: Bool

    public init(
        url: URL,
        sizeBytes: Int64,
        modificationTime: Date,
        metadata: FileMetadata = FileMetadata(),
        isLocked: Bool = false
    ) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationTime = modificationTime
        self.metadata = metadata
        self.isLocked = isLocked
    }
}

/// What the engine decides about each file in a cluster.
public enum Decision: Sendable, Hashable, Codable {
    case keep(reason: String)
    case delete(reason: String)

    private enum CodingKeys: String, CodingKey { case kind, reason }
    private enum Kind: String, Codable { case keep, delete }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let reason = try c.decode(String.self, forKey: .reason)
        switch kind {
        case .keep:   self = .keep(reason: reason)
        case .delete: self = .delete(reason: reason)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keep(let r):
            try c.encode(Kind.keep, forKey: .kind)
            try c.encode(r, forKey: .reason)
        case .delete(let r):
            try c.encode(Kind.delete, forKey: .kind)
            try c.encode(r, forKey: .reason)
        }
    }
}

/// Per-file decisions for a single cluster. Round-trips through `Codable` so
/// the GUI can persist review state across app launches; URL keys are
/// serialised as path strings to avoid Swift's awkward URL-as-CodingKey
/// behaviour (which produces opaque numeric indices in JSON).
public struct ClusterDecisions: Sendable, Codable, Equatable {
    public var keeper: URL
    public var perFile: [URL: Decision]

    public init(keeper: URL, perFile: [URL: Decision]) {
        self.keeper = keeper
        self.perFile = perFile
    }

    private enum CodingKeys: String, CodingKey { case keeper, perFile }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let path = try c.decode(String.self, forKey: .keeper)
        keeper = URL(fileURLWithPath: path)
        let stringKeyed = try c.decode([String: Decision].self, forKey: .perFile)
        perFile = stringKeyed.reduce(into: [URL: Decision]()) {
            $0[URL(fileURLWithPath: $1.key)] = $1.value
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keeper.path, forKey: .keeper)
        let stringKeyed = perFile.reduce(into: [String: Decision]()) {
            $0[$1.key.path] = $1.value
        }
        try c.encode(stringKeyed, forKey: .perFile)
    }
}

/// Per-decision configuration injected at engine call time. Currently carries
/// just the folder-priority list (used by the `.folderPriority` rule). Lives
/// outside `Rule` itself so the enum stays a simple Codable raw-value type —
/// the chain serialises to a `[String]` of rule names without per-case
/// associated values to deal with.
public struct SelectionContext: Sendable {
    /// Ordered list of folder path prefixes; earlier entries win. A file in
    /// any of these folders scores higher than one that isn't, with longer
    /// (more specific) prefixes ranking above shorter ones for the same file.
    public var folderPriority: [String]

    public init(folderPriority: [String] = []) {
        self.folderPriority = folderPriority
    }
}

/// Available rules. The actual scoring lives on the enum so the rule chain is
/// just a list of `Rule.kind`s. Adding a new rule = one new case + one new
/// scoring branch.
public enum Rule: String, Sendable, Codable, CaseIterable {
    case folderPriority
    case highestResolution
    case largestSize
    case smallestSize
    case newestCaptureDate
    case oldestCaptureDate
    case newestModificationDate
    case oldestModificationDate
    case mostMetadata
    case shortestPath
    case longestPath

    public var displayName: String {
        switch self {
        case .folderPriority:           return "Folder priority"
        case .highestResolution:        return "Highest resolution"
        case .largestSize:              return "Largest file size"
        case .smallestSize:             return "Smallest file size"
        case .newestCaptureDate:        return "Newest by capture date"
        case .oldestCaptureDate:        return "Oldest by capture date"
        case .newestModificationDate:   return "Newest by modified date"
        case .oldestModificationDate:   return "Oldest by modified date"
        case .mostMetadata:             return "Most EXIF metadata"
        case .shortestPath:             return "Shortest filename / path"
        case .longestPath:              return "Longest filename / path"
        }
    }

    public var helpText: String {
        switch self {
        case .folderPriority:           return "Keep files in your preferred folders (configured below). Files in earlier-listed folders beat files in later ones; files outside the list score below all listed folders."
        case .highestResolution:        return "Keep the larger photo (width × height). Catches the case where a sharing app downsampled the original."
        case .largestSize:              return "Keep the larger file by bytes. Useful when resolution data isn't available."
        case .smallestSize:              return "Keep the smaller file by bytes. Inverts largest-size — useful when re-encodes are bloated and you'd rather keep the original."
        case .newestCaptureDate:        return "Keep the photo with the newest EXIF capture date. Falls through when EXIF is missing."
        case .oldestCaptureDate:        return "Keep the photo with the oldest EXIF capture date. Use when you suspect later copies have been edited."
        case .newestModificationDate:   return "Keep the file most recently modified on disk. Always populated."
        case .oldestModificationDate:   return "Keep the file least recently modified on disk."
        case .mostMetadata:             return "Keep the file with the richest EXIF/codec metadata. Camera originals usually beat shared-app re-encodes here."
        case .shortestPath:             return "Keep the file with the shortest path. Catches the ' (1)' / ' (2)' Finder duplicate suffixes."
        case .longestPath:              return "Keep the file with the longest path. Useful when descriptive subdirs encode meaning."
        }
    }

    /// Higher score = better keeper. Returning `nil` means "this rule has no
    /// opinion on this file" (e.g. capture date when EXIF is absent); the
    /// chain treats absence as the worst possible score so files with the
    /// data still beat files without.
    func score(for file: FileForSelection, context: SelectionContext) -> Double? {
        switch self {
        case .folderPriority:
            // Find the EARLIEST listed folder whose path is a prefix of the
            // file's; rank by reversed position so earlier-listed folders
            // beat later-listed ones. Adds the prefix length as a tiebreaker
            // so /a/b/originals beats /a/b for a file in /a/b/originals/foo.jpg
            // when both are listed.
            guard !context.folderPriority.isEmpty else { return nil }
            let path = file.url.path
            for (i, prefix) in context.folderPriority.enumerated() {
                let normalisedPrefix = prefix.hasSuffix("/") ? prefix : prefix + "/"
                if path == prefix || path.hasPrefix(normalisedPrefix) {
                    let positionScore = Double(context.folderPriority.count - i) * 1_000_000
                    return positionScore + Double(prefix.count)
                }
            }
            return nil
        case .highestResolution:
            guard let w = file.metadata.pixelWidth, let h = file.metadata.pixelHeight else { return nil }
            return Double(w) * Double(h)
        case .largestSize:
            return Double(file.sizeBytes)
        case .smallestSize:
            return -Double(file.sizeBytes)
        case .newestCaptureDate:
            guard let d = file.metadata.captureDate else { return nil }
            return d.timeIntervalSince1970
        case .oldestCaptureDate:
            guard let d = file.metadata.captureDate else { return nil }
            return -d.timeIntervalSince1970
        case .newestModificationDate:
            return file.modificationTime.timeIntervalSince1970
        case .oldestModificationDate:
            return -file.modificationTime.timeIntervalSince1970
        case .mostMetadata:
            return Double(file.metadata.rows().count)
        case .shortestPath:
            return -Double(file.url.path.count)
        case .longestPath:
            return Double(file.url.path.count)
        }
    }
}

/// Ordered chain of rules. First-applicable wins; ties fall through to the next
/// rule. The chain serializes to/from JSON so a future Settings UI can let the
/// user store a custom ordering.
public struct RuleChain: Sendable, Codable {
    public var rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    /// Sensible default for "what to keep when files are nominally identical."
    /// Resolution first because a 4 K original is almost always preferable to a
    /// shared-app downsample. Then most-metadata, because a hand-shared JPEG
    /// usually loses its EXIF and the camera-original keeps it. Then capture
    /// date (newer = the one you actually meant to keep). Then shortest-path
    /// because " (1)" / " (2)" suffixes are always the duplicates.
    public static let `default` = RuleChain(rules: [
        .highestResolution,
        .mostMetadata,
        .newestCaptureDate,
        .shortestPath,
    ])
}

/// Apply a `RuleChain` to a cluster and produce a `ClusterDecisions`. Pure
/// function; no I/O. Locked-source files never get marked for deletion (FR-1.5)
/// — they're forced to `.keep` regardless of rule outcome.
public struct SelectionEngine: Sendable {

    public init() {}

    public func decide(
        files: [FileForSelection],
        chain: RuleChain = .default,
        context: SelectionContext = SelectionContext()
    ) -> ClusterDecisions {
        precondition(!files.isEmpty, "selection engine requires ≥1 file")

        // Locked files always stay. If every file in the cluster is locked,
        // there's nothing to delete; pick the alphabetically first as the
        // nominal keeper so the UI has something to highlight.
        let lockedFiles = files.filter(\.isLocked)
        let unlocked = files.filter { !$0.isLocked }
        guard !unlocked.isEmpty else {
            let sorted = files.sorted { $0.url.path < $1.url.path }
            var perFile: [URL: Decision] = [:]
            for f in files {
                perFile[f.url] = .keep(reason: "locked source")
            }
            return ClusterDecisions(keeper: sorted.first!.url, perFile: perFile)
        }

        // Run the chain on unlocked candidates. Each rule narrows the pool to
        // those tied at the rule's max score; once one file remains, the rest
        // are losers and we break early.
        var pool = unlocked
        var winningRule: Rule? = nil
        for rule in chain.rules where pool.count > 1 {
            let scored: [(file: FileForSelection, score: Double?)] = pool.map { ($0, rule.score(for: $0, context: context)) }
            // Files with nil score lose to any file with a score (we treat nil
            // as -∞). If every file has nil, the rule has no effect and we
            // continue to the next rule.
            let realScores = scored.compactMap { $0.score }
            guard let topScore = realScores.max() else { continue }
            let winners = scored.filter { ($0.score ?? -.infinity) == topScore }.map(\.file)
            if winners.count < pool.count {
                pool = winners
                winningRule = rule
            }
        }

        // Final tiebreak: alphabetical path. Deterministic across runs.
        let keeperEntry = pool.sorted { $0.url.path < $1.url.path }.first!
        let keepReason = winningRule?.displayName ?? "first by path (no rule decided)"

        var perFile: [URL: Decision] = [:]
        perFile[keeperEntry.url] = .keep(reason: keepReason)
        for f in unlocked where f.url != keeperEntry.url {
            // Reason: the first rule on the chain where this file scored worse
            // than the keeper. Surfaces the human-readable "why" the UI shows
            // next to the DELETE badge.
            var reason = "lost final tiebreak (path)"
            for rule in chain.rules {
                let mine = rule.score(for: f, context: context) ?? -.infinity
                let theirs = rule.score(for: keeperEntry, context: context) ?? -.infinity
                if mine < theirs {
                    reason = "\(rule.displayName)"
                    break
                }
            }
            perFile[f.url] = .delete(reason: reason)
        }
        for f in lockedFiles {
            perFile[f.url] = .keep(reason: "locked source")
        }
        return ClusterDecisions(keeper: keeperEntry.url, perFile: perFile)
    }
}

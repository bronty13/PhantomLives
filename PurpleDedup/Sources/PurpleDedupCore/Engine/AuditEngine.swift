import Foundation

/// Audits a folder against an Apple Photos library: classifies every file in the
/// folder as *already in Photos* or *missing from Photos*, so the user can import
/// the missing ones.
///
/// This is the per-file inverse of `CachedScanEngine`'s "lookup-only" mode. Where
/// the dedup flow only *badges* cluster members that also live in Photos, the audit
/// produces a complete, flat classification of the folder — including singleton
/// files that never form a dedup cluster.
///
/// ### How a file is decided "in Photos"
/// - **Exact (SHA-1).** Photos stores an unmodified import byte-for-byte under
///   `<library>.photoslibrary/originals/`. So a folder file whose content hash is
///   present in the library's hash index is definitely there. This is the only
///   zero-false-positive signal and the only one safe to *gate import on*.
/// - **Perceptual (opt-in default).** A re-encoded / resized / edited copy SHA-1
///   mismatches even though "the same photo" is in Photos. In `.perceptual` mode we
///   also pHash/dHash the library's photos and reclassify a still-missing folder
///   *photo* to `.likelyInPhotosPerceptual` when it lands within Hamming threshold.
///   Advisory — surfaced with its distance so the user can review.
/// - **Filename (safety net).** When the caller supplies `knownPhotoBasenames` (the
///   set of original filenames PhotoKit reports for the library), a still-missing
///   file whose basename matches one is flagged `.likelyInPhotosFilename` rather than
///   `.missing`. This catches iCloud "Optimize Mac Storage" stubs whose `originals/`
///   bytes differ from the on-disk copy, so we don't re-import a duplicate.
///
/// Videos are matched exact-only in v1 (whole-library perceptual video matching is
/// out of scope).
public actor AuditEngine {

    public enum MatchMode: String, Sendable, Codable {
        /// Byte-exact SHA-1 only. Conservative; an in-Photos copy that was
        /// re-encoded will read as missing.
        case exact
        /// Exact first, then perceptual reclassification of still-missing photos.
        case perceptual
    }

    /// One audited folder file and the verdict on whether it's in Photos.
    public struct AuditedFile: Sendable, Equatable {
        public let url: URL
        public let sizeBytes: Int64
        public let modificationTime: Date
        public let contentHashHex: String?
        public let classification: Classification
        /// How the match relates to the Hidden album. Lets the UI flag matches
        /// that live only in Hidden (so the user can find them) distinctly from
        /// matches that are present both visibly AND hidden. `.none` for
        /// `.missing` and visible-only matches.
        public let hiddenMatch: HiddenMatch

        public enum HiddenMatch: Sendable, Equatable {
            /// No hidden copy (visible-only match, or not in Photos).
            case none
            /// The only library copy is in the Hidden album.
            case hiddenOnly
            /// Present in Photos both visibly AND as a hidden copy.
            case alsoHidden
        }

        public enum Classification: Sendable, Equatable {
            /// SHA-1 matched a library original — definitely present.
            case inPhotosExact
            /// pHash/dHash matched the library's on-device **preview** (the
            /// `originals/` file is in iCloud, not on this Mac). Confident — the
            /// preview is a faithful proxy for the original.
            case inPhotosPreview(distance: Int)
            /// pHash/dHash within threshold of an on-disk library original. Advisory.
            case likelyInPhotosPerceptual(distance: Int)
            /// Same filename as a known library original (hash differs — likely an
            /// iCloud-optimised stub). Advisory.
            case likelyInPhotosFilename(basename: String)
            /// Not found by any signal — a candidate for import.
            case missing
        }

        public init(url: URL, sizeBytes: Int64, modificationTime: Date,
                    contentHashHex: String?, classification: Classification,
                    hiddenMatch: HiddenMatch = .none) {
            self.url = url
            self.sizeBytes = sizeBytes
            self.modificationTime = modificationTime
            self.contentHashHex = contentHashHex
            self.classification = classification
            self.hiddenMatch = hiddenMatch
        }

        /// True for every non-`.missing` verdict.
        public var isInPhotos: Bool {
            if case .missing = classification { return false }
            return true
        }

        /// True when the match involves a hidden copy (hidden-only or also-hidden).
        public var inPhotosHidden: Bool { hiddenMatch != .none }
    }

    public struct AuditResult: Sendable {
        public let folder: URL
        public let photosLibrary: URL
        public let matchMode: MatchMode
        /// Every readable folder file, in stable (path-sorted) order.
        public let files: [AuditedFile]
        /// Files that could not be hashed (I/O error, permission). Kept distinct
        /// from `missing` — an ambiguous file must never be auto-imported.
        public let unreadable: [URL]
        /// Number of files indexed from the Photos library.
        public let photosIndexedCount: Int
        public let timing: ScanEngine.StageTiming

        public init(folder: URL, photosLibrary: URL, matchMode: MatchMode,
                    files: [AuditedFile], unreadable: [URL],
                    photosIndexedCount: Int, timing: ScanEngine.StageTiming) {
            self.folder = folder
            self.photosLibrary = photosLibrary
            self.matchMode = matchMode
            self.files = files
            self.unreadable = unreadable
            self.photosIndexedCount = photosIndexedCount
            self.timing = timing
        }

        /// Files judged already in Photos (exact, perceptual, or filename).
        public var inPhotos: [AuditedFile] { files.filter { $0.isInPhotos } }
        /// Files not found anywhere — the import candidates.
        public var missing: [AuditedFile] {
            files.filter { if case .missing = $0.classification { return true }; return false }
        }
        /// In-Photos matches that live only in the Hidden album.
        public var hiddenInPhotos: [AuditedFile] { files.filter { $0.inPhotosHidden } }

        public var summary: String {
            var bits = ["\(inPhotos.count) in Photos", "\(missing.count) missing"]
            let hidden = hiddenInPhotos.count
            if hidden > 0 { bits.append("\(hidden) hidden") }
            if !unreadable.isEmpty { bits.append("\(unreadable.count) unreadable") }
            return bits.joined(separator: " · ")
        }
    }

    private let walker: FileWalker
    private let contentHasher: ContentHasher
    private let perceptualHasher: PerceptualHasher
    private let database: Database?

    public init(
        database: Database? = nil,
        walker: FileWalker = FileWalker(),
        contentHasher: ContentHasher = ContentHasher(),
        perceptualHasher: PerceptualHasher = PerceptualHasher()
    ) {
        self.database = database
        self.walker = walker
        self.contentHasher = contentHasher
        self.perceptualHasher = perceptualHasher
    }

    public func audit(
        folder: URL,
        photosLibrary: URL,
        mode: MatchMode = .perceptual,
        options: ScanOptions = ScanOptions(),
        perceptualThreshold: Int = PerceptualClusterer.defaultThreshold,
        knownPhotoBasenames: Set<String>? = nil,
        hiddenPhotoBasenames: Set<String> = [],
        knownAssetUUIDs: Set<String> = [],
        includeHidden: Bool = true,
        hiddenAssetStems: Set<String> = [],
        matchDerivatives: Bool = true,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> AuditResult {
        let start = Date()
        var timing = ScanEngine.StageTiming()

        let cachedRows = (try? database?.loadAllCachedRows()) ?? [:]

        // 1. Walk + hash the target folder FIRST. We need the folder's content
        //    hashes anyway, and learning its set of file SIZES lets us skip
        //    hashing every library file that can't possibly match: a byte-exact
        //    duplicate must have an identical byte length, so a library file
        //    whose size matches no folder file can never be an exact match.
        let walkStart = Date()
        var folderFiles: [DiscoveredFile] = []
        for try await f in walker.walk(sources: [ScanSource(url: folder, isLocked: false)], options: options) {
            try Task.checkCancellation()
            folderFiles.append(f)
            if folderFiles.count % 256 == 0 {
                progress?(ScanProgress(phase: .walking, filesSeen: folderFiles.count,
                                       filesHashed: 0, totalCandidates: 0, clustersSoFar: 0))
            }
        }
        timing.walkSeconds = Date().timeIntervalSince(walkStart)

        let hashStart = Date()
        let (hashed, unreadable) = try await hashFolderFiles(
            folderFiles, cachedRows: cachedRows, totalCandidates: folderFiles.count, progress: progress
        )
        let folderSizes = Set(folderFiles.map(\.sizeBytes))

        // 2. Index the Photos library's content hashes — but only hash library
        //    files whose size appears in the folder (the size short-circuit
        //    above). On a large library audited against a small folder this is
        //    the dominant speedup: tens of files hashed instead of the whole
        //    library. Cache-aware regardless.
        let indexStart = Date()
        let hiddenStems = Set(hiddenAssetStems.map { $0.uppercased() })
        let index = try await buildLibraryIndex(
            library: photosLibrary,
            options: options,
            relevantSizes: folderSizes,
            includeHidden: includeHidden,
            hiddenStems: hiddenStems,
            cachedRows: cachedRows,
            progress: progress
        )
        timing.exactSeconds = Date().timeIntervalSince(indexStart)

        // 3. Partition folder files into exact-in-Photos vs still-missing.
        //    A match is tagged hidden when the only library copy is in the
        //    Hidden album (present in hiddenHashes, absent from visibleHashes).
        var audited: [AuditedFile] = []
        var stillMissing: [(DiscoveredFile, String?)] = []   // file + its hex (for re-eval)
        // Filename safety net keyed on the lowercased *stem* (no extension). The
        // set comes from PhotoKit (every asset, including iCloud-only ones not on
        // disk), so it's the only signal that survives Optimize-Mac-Storage. A
        // Photos drag-export keeps the original filename stem even when the format
        // changes (IMG_1234.HEIC → IMG_1234.jpeg), so stem matching catches it
        // where full-basename matching would not.
        let knownStems = knownPhotoBasenames.map { Set($0.map { Self.filenameStem($0) }) }
        // Stems of hidden assets' original filenames — lets a filename match be
        // tagged as hidden even when only the name (not the bytes) is available.
        let hiddenFilenameStems = Set(hiddenPhotoBasenames.map { Self.filenameStem($0) })
        // Asset UUIDs (lowercased) — a folder file named with the library's
        // internal UUID (Photos exports some assets this way) is unambiguously
        // from the library, even with no original filename and no on-disk bytes.
        let knownUUIDStems = Set(knownAssetUUIDs.map { $0.lowercased() })
        for (f, hex) in hashed {
            if let hex, index.hashes.contains(hex) {
                let hm = Self.hiddenMatch(inHidden: index.hiddenHashes.contains(hex),
                                          inVisible: index.visibleHashes.contains(hex))
                audited.append(AuditedFile(url: f.url, sizeBytes: f.sizeBytes,
                                           modificationTime: f.modificationTime,
                                           contentHashHex: hex, classification: .inPhotosExact,
                                           hiddenMatch: hm))
            } else {
                stillMissing.append((f, hex))
            }
        }

        // 4. Perceptual reclassification of still-missing photos (perceptual mode).
        //    The library's perceptual index is built LAZILY here — only when at
        //    least one folder photo missed the exact match. A fully-backed-up
        //    folder skips the (minutes-long, cache-aside) library pHash pass.
        var resolved: Set<URL> = []
        if mode == .perceptual {
            let missingPhotos = stillMissing.filter {
                FileKind.photoExtensions.contains($0.0.url.pathExtension.lowercased())
            }.map { $0.0 }
            if !missingPhotos.isEmpty {
                // Perceptual index = on-disk originals (full-res) PLUS the
                // on-device preview derivatives of iCloud-only assets (those
                // without an on-disk original). The derivative previews are
                // faithful pHash proxies, so this finds photos whose originals
                // live only in iCloud — the common case under Optimize Mac Storage.
                var libraryPHashes: [LibraryPHash] = []
                if !index.photoFiles.isEmpty {
                    libraryPHashes += try await perceptualHashAll(
                        index.photoFiles, source: .original, cachedRows: cachedRows, progress: progress
                    )
                }
                if matchDerivatives {
                    let derivatives = try await discoverDerivatives(
                        library: photosLibrary, excluding: index.onDiskOriginalStems,
                        includeHidden: includeHidden, hiddenStems: hiddenStems, progress: progress
                    )
                    if !derivatives.isEmpty {
                        libraryPHashes += try await perceptualHashAll(
                            derivatives, source: .derivative, cachedRows: cachedRows, progress: progress
                        )
                    }
                }
                if !libraryPHashes.isEmpty {
                    let matches = try await perceptualMatch(
                        missingPhotos, against: libraryPHashes,
                        threshold: perceptualThreshold, progress: progress
                    )
                    for (f, hex) in stillMissing {
                        if let match = matches[f.url] {
                            let classification: AuditedFile.Classification = match.source == .derivative
                                ? .inPhotosPreview(distance: match.distance)
                                : .likelyInPhotosPerceptual(distance: match.distance)
                            audited.append(AuditedFile(url: f.url, sizeBytes: f.sizeBytes,
                                                       modificationTime: f.modificationTime,
                                                       contentHashHex: hex,
                                                       classification: classification,
                                                       hiddenMatch: match.state))
                            resolved.insert(f.url)
                        }
                    }
                }
            }
        }

        // 5. Filename / UUID safety net + final missing.
        for (f, hex) in stillMissing where !resolved.contains(f.url) {
            let base = f.url.lastPathComponent
            let stem = Self.filenameStem(base)
            if (knownStems?.contains(stem) ?? false) || knownUUIDStems.contains(stem) {
                let hidden = hiddenFilenameStems.contains(stem) || hiddenStems.contains(stem.uppercased())
                audited.append(AuditedFile(url: f.url, sizeBytes: f.sizeBytes,
                                           modificationTime: f.modificationTime,
                                           contentHashHex: hex,
                                           classification: .likelyInPhotosFilename(basename: base),
                                           hiddenMatch: hidden ? .hiddenOnly : .none))
            } else {
                audited.append(AuditedFile(url: f.url, sizeBytes: f.sizeBytes,
                                           modificationTime: f.modificationTime,
                                           contentHashHex: hex, classification: .missing))
            }
        }

        audited.sort { $0.url.path < $1.url.path }
        timing.perceptualSeconds = Date().timeIntervalSince(hashStart)
        timing.totalSeconds = Date().timeIntervalSince(start)

        progress?(ScanProgress(phase: .done, filesSeen: folderFiles.count,
                               filesHashed: hashed.count, totalCandidates: folderFiles.count,
                               clustersSoFar: 0))

        return AuditResult(folder: folder, photosLibrary: photosLibrary, matchMode: mode,
                           files: audited, unreadable: unreadable,
                           photosIndexedCount: index.count, timing: timing)
    }

    // MARK: - Library index

    /// Where a perceptual match came from — a full-resolution on-disk original,
    /// or the on-device preview derivative of an iCloud-only asset.
    private enum MatchSource: Sendable { case original, derivative }

    private struct LibraryIndex {
        var hashes: Set<String> = []
        /// Hashes whose library file is a hidden asset, and those whose library
        /// file is visible. A match is "hidden" only when it's in `hiddenHashes`
        /// and NOT in `visibleHashes` (i.e. the only copy lives in the Hidden
        /// album).
        var hiddenHashes: Set<String> = []
        var visibleHashes: Set<String> = []
        /// Library photo files (with hidden flag), kept so a *deferred*
        /// perceptual pass can hash them without re-walking — but only if some
        /// folder photo misses the exact match (see step 4 in `audit`).
        var photoFiles: [(file: DiscoveredFile, hidden: Bool)] = []
        /// Uppercased UUID stems of every original actually on disk. Lets the
        /// derivative pass skip assets whose full-res original we already have.
        var onDiskOriginalStems: Set<String> = []
        var count = 0
    }

    /// Uppercased filename stem (UUID) — matches Photos.sqlite's ZUUID and the
    /// hidden-asset stem set.
    private nonisolated static func stem(_ url: URL) -> String {
        (url.lastPathComponent as NSString).deletingPathExtension.uppercased()
    }

    /// Lowercased filename stem (no extension) for the filename safety net, so a
    /// format-changing export (`IMG_1234.HEIC` → `IMG_1234.jpeg`) still matches.
    private nonisolated static func filenameStem(_ name: String) -> String {
        (name as NSString).deletingPathExtension.lowercased()
    }

    /// Collapse "matched a hidden copy?" / "matched a visible copy?" into the
    /// three-state verdict.
    private nonisolated static func hiddenMatch(inHidden: Bool, inVisible: Bool) -> AuditedFile.HiddenMatch {
        guard inHidden else { return .none }
        return inVisible ? .alsoHidden : .hiddenOnly
    }

    /// Walk the Photos library and build its content-hash set, hashing ONLY
    /// files whose size is in `relevantSizes` (the sizes present in the folder
    /// being audited) — a byte-exact match must share an exact byte length, so
    /// size-mismatched library files can be skipped without reading them.
    /// Cache-aware: a file already in the SQLite cache with matching
    /// `(size, mtime)` is read straight from cache. The library's perceptual
    /// hashes are NOT built here — that's deferred to `audit` so it only runs
    /// when there's something to match.
    private func buildLibraryIndex(
        library: URL,
        options: ScanOptions,
        relevantSizes: Set<Int64>,
        includeHidden: Bool,
        hiddenStems: Set<String>,
        cachedRows: [String: Database.CachedRow],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> LibraryIndex {
        progress?(ScanProgress(phase: .indexing, filesSeen: 0, filesHashed: 0,
                               totalCandidates: 0, clustersSoFar: 0))

        let source = ScanSource(url: library, isLookupOnly: true)
        var libFiles: [DiscoveredFile] = []
        for try await f in walker.walk(sources: [source], options: options) {
            try Task.checkCancellation()
            libFiles.append(f)
            if libFiles.count % 256 == 0 {
                progress?(ScanProgress(phase: .indexing, filesSeen: libFiles.count, filesHashed: 0,
                                       totalCandidates: 0, clustersSoFar: 0))
            }
        }
        func isHidden(_ url: URL) -> Bool { hiddenStems.contains(Self.stem(url)) }

        var index = LibraryIndex()
        index.count = libFiles.count
        index.onDiskOriginalStems = Set(libFiles.map { Self.stem($0.url) })
        // Library photos for the deferred perceptual pass, carrying hidden state.
        // Drop hidden photos entirely when the user excluded them.
        index.photoFiles = libFiles.compactMap { f in
            guard FileKind.photoExtensions.contains(f.url.pathExtension.lowercased()) else { return nil }
            let hidden = isHidden(f.url)
            if hidden && !includeHidden { return nil }
            return (f, hidden)
        }
        guard !libFiles.isEmpty else { return index }

        // Content hashes — only for library files whose size matches a folder
        // file. Everything else can't be a byte-exact duplicate, so we never
        // read its bytes. Hidden files are dropped here when excluded.
        let candidates = libFiles.filter { relevantSizes.contains($0.sizeBytes) }
        let (hashed, _) = try await hashFolderFiles(
            candidates, cachedRows: cachedRows, totalCandidates: candidates.count, progress: progress, phase: .indexing
        )
        for (f, hex) in hashed {
            guard let hex else { continue }
            let hidden = isHidden(f.url)
            if hidden {
                if !includeHidden { continue }   // excluded → not in the index at all
                index.hiddenHashes.insert(hex)
            } else {
                index.visibleHashes.insert(hex)
            }
            index.hashes.insert(hex)
        }
        return index
    }

    /// Find the on-device preview derivative for each iCloud-only asset (one per
    /// asset, the largest available rendition), so the perceptual pass can match
    /// photos whose full-res original isn't on this Mac. Derivatives live at
    /// `resources/derivatives/<shard>/<UUID>_1_<code>_<q>.jpeg`; the UUID is the
    /// filename's leading segment. Assets whose original IS on disk are skipped
    /// (already matched at full res). `.ithmb` thumbnail packs are ignored
    /// automatically (not a photo extension).
    private func discoverDerivatives(
        library: URL,
        excluding onDiskStems: Set<String>,
        includeHidden: Bool,
        hiddenStems: Set<String>,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [(file: DiscoveredFile, hidden: Bool)] {
        let derivURL = library.appendingPathComponent("resources/derivatives", isDirectory: true)
        guard FileManager.default.fileExists(atPath: derivURL.path) else { return [] }

        // Keep the largest derivative file per asset UUID — bigger renders are
        // the best pHash source (resolution is irrelevant to the hash, but more
        // detail is never worse).
        var bestByUUID: [String: DiscoveredFile] = [:]
        for try await f in walker.walk(sources: [ScanSource(url: derivURL)],
                                       options: ScanOptions(kinds: [.photo])) {
            try Task.checkCancellation()
            let leading = f.url.deletingPathExtension().lastPathComponent
                .split(separator: "_").first.map(String.init) ?? ""
            let uuid = leading.uppercased()
            guard !uuid.isEmpty, !onDiskStems.contains(uuid) else { continue }
            if let cur = bestByUUID[uuid], cur.sizeBytes >= f.sizeBytes { continue }
            bestByUUID[uuid] = f
        }
        return bestByUUID.compactMap { (uuid, f) in
            let hidden = hiddenStems.contains(uuid)
            if hidden && !includeHidden { return nil }
            return (f, hidden)
        }
    }

    // MARK: - Hashing

    /// Cache-aware SHA-1 over a file list. Returns `(file, hex?)` for every readable
    /// file (hex nil only on the rare case the cache stored no hash) and the URLs
    /// that failed to read. Persists fresh hashes so a re-run is instant.
    private func hashFolderFiles(
        _ files: [DiscoveredFile],
        cachedRows: [String: Database.CachedRow],
        totalCandidates: Int,
        progress: (@Sendable (ScanProgress) -> Void)?,
        phase: ScanProgress.Phase = .hashing
    ) async throws -> (hashed: [(DiscoveredFile, String?)], unreadable: [URL]) {
        var result: [(DiscoveredFile, String?)] = []
        var stale: [DiscoveredFile] = []
        for f in files {
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let blob = row.file.contentHash {
                result.append((f, blob.hexEncodedString()))
            } else {
                stale.append(f)
            }
        }

        let hasher = contentHasher
        var fresh: [(DiscoveredFile, Data)] = []
        var unreadable: [URL] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, Data?)?.self) { group in
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var iterator = stale.makeIterator()
            var inFlight = 0
            func submit() {
                if Task.isCancelled { return }
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do { return (next, try hasher.hash(fileAt: next.url)) }
                    catch {
                        Log.hash.notice("Audit hash failed for \(next.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (next, nil)
                    }
                }
            }
            for _ in 0..<limit { submit() }
            var done = 0
            let cachedHits = result.count
            while inFlight > 0 {
                if Task.isCancelled { group.cancelAll(); throw CancellationError() }
                if let r = try await group.next() {
                    inFlight -= 1; done += 1
                    if let entry = r {
                        if let blob = entry.1 { fresh.append((entry.0, blob)) }
                        else { unreadable.append(entry.0.url) }
                    }
                    if done % 64 == 0 {
                        progress?(ScanProgress(phase: phase, filesSeen: files.count,
                                               filesHashed: cachedHits + done,
                                               totalCandidates: totalCandidates, clustersSoFar: 0))
                    }
                    submit()
                } else { break }
            }
        }

        for (f, blob) in fresh { result.append((f, blob.hexEncodedString())) }

        // Persist fresh hashes for next time.
        if let database, !fresh.isEmpty {
            let rows = fresh.map { (f, blob) in
                Database.ScannedFile(
                    path: f.url.path, sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: Self.classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(), contentHash: blob
                )
            }
            try? database.upsertScannedBatch(rows)
        }
        return (result, unreadable)
    }

    /// A library photo's perceptual hash plus whether it's a hidden asset and
    /// whether it came from a full-res original or a preview derivative.
    private struct LibraryPHash: Sendable { let hash: PerceptualHash; let hidden: Bool; let source: MatchSource }

    /// pHash/dHash a list of library photos (each tagged hidden/visible),
    /// cache-aware. Capped at 6 concurrent for the same HEVC-decoder reason as
    /// the dedup engine. The hidden flag + `source` ride alongside each hash so a
    /// match can be tagged.
    private func perceptualHashAll(
        _ photos: [(file: DiscoveredFile, hidden: Bool)],
        source: MatchSource,
        cachedRows: [String: Database.CachedRow],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [LibraryPHash] {
        guard !photos.isEmpty else { return [] }
        var hashes: [LibraryPHash] = []
        var stale: [(file: DiscoveredFile, hidden: Bool)] = []
        for p in photos {
            let f = p.file
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let fp = row.fingerprint, let ph = fp.phash, let dh = fp.dhash {
                hashes.append(LibraryPHash(hash: PerceptualHash(phash: UInt64(littleEndianHashData: ph),
                                             dhash: UInt64(littleEndianHashData: dh),
                                             width: Int(fp.width ?? 0), height: Int(fp.height ?? 0)),
                                           hidden: p.hidden, source: source))
            } else {
                stale.append(p)
            }
        }

        let hasher = perceptualHasher
        var fresh: [(DiscoveredFile, PerceptualHash)] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, Bool, PerceptualHash)?.self) { group in
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = stale.makeIterator()
            var inFlight = 0
            func submit() {
                if Task.isCancelled { return }
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do { return (next.file, next.hidden, try hasher.hash(imageAt: next.file.url)) }
                    catch { return nil }
                }
            }
            for _ in 0..<limit { submit() }
            var done = 0
            while inFlight > 0 {
                if Task.isCancelled { group.cancelAll(); throw CancellationError() }
                if let r = try await group.next() {
                    inFlight -= 1; done += 1
                    if let entry = r {
                        fresh.append((entry.0, entry.2))
                        hashes.append(LibraryPHash(hash: entry.2, hidden: entry.1, source: source))
                    }
                    if done % 32 == 0 {
                        progress?(ScanProgress(phase: .indexing, filesSeen: photos.count,
                                               filesHashed: hashes.count, totalCandidates: photos.count,
                                               clustersSoFar: 0))
                    }
                    submit()
                } else { break }
            }
        }

        if let database, !fresh.isEmpty {
            let rows = fresh.map { (f, h) in
                Database.FingerprintWrite(
                    path: f.url.path, sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: Self.classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(),
                    phash: h.phash, dhash: h.dhash, width: h.width, height: h.height,
                    videoFingerprint: nil
                )
            }
            try? database.upsertFingerprintsBatch(rows)
        }
        return hashes
    }

    /// For each candidate photo, find the smallest OR-of-distances (min of pHash and
    /// dHash Hamming) to any library photo; return those within threshold, plus
    /// whether the best match is a hidden asset. Linear scan — only the
    /// still-missing set is searched, and Hamming is a single CPU cycle.
    private func perceptualMatch(
        _ candidates: [DiscoveredFile],
        against library: [LibraryPHash],
        threshold: Int,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [URL: (distance: Int, state: AuditedFile.HiddenMatch, source: MatchSource)] {
        guard !candidates.isEmpty, !library.isEmpty else { return [:] }
        let hasher = perceptualHasher
        let lib = library
        let thr = threshold
        return try await withThrowingTaskGroup(of: (URL, Int, AuditedFile.HiddenMatch, MatchSource)?.self) { group in
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = candidates.makeIterator()
            var inFlight = 0
            func submit() {
                if Task.isCancelled { return }
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard let h = try? hasher.hash(imageAt: next.url) else { return nil }
                    // Scan all library photos: track the best distance (and its
                    // source) and whether any within-threshold match is hidden /
                    // visible, so the verdict distinguishes hidden-only from
                    // also-hidden and original from preview.
                    var best = Int.max
                    var bestSource: MatchSource = .original
                    var sawHidden = false, sawVisible = false
                    for l in lib {
                        let d = min(PerceptualHash.hammingDistance(h.phash, l.hash.phash),
                                    PerceptualHash.hammingDistance(h.dhash, l.hash.dhash))
                        if d < best { best = d; bestSource = l.source }
                        if d <= thr { if l.hidden { sawHidden = true } else { sawVisible = true } }
                    }
                    let state = Self.hiddenMatch(inHidden: sawHidden, inVisible: sawVisible)
                    return best <= thr ? (next.url, best, state, bestSource) : nil
                }
            }
            for _ in 0..<limit { submit() }
            var out: [URL: (distance: Int, state: AuditedFile.HiddenMatch, source: MatchSource)] = [:]
            while inFlight > 0 {
                if Task.isCancelled { group.cancelAll(); throw CancellationError() }
                if let r = try await group.next() {
                    inFlight -= 1
                    if let entry = r { out[entry.0] = (entry.1, entry.2, entry.3) }
                    submit()
                } else { break }
            }
            return out
        }
    }

    private nonisolated static func classify(_ ext: String) -> String {
        let lower = ext.lowercased()
        if FileKind.photoExtensions.contains(lower) { return "photo" }
        if FileKind.videoExtensions.contains(lower) { return "video" }
        return "other"
    }
}

/// The three views the audit UI (and tests) partition a result into.
public enum AuditFilter: String, Sendable, CaseIterable {
    case all
    case inPhotos
    case missing
}

extension AuditEngine.AuditResult {
    /// Files matching a filter, preserving the result's stable order. Pure —
    /// unit-tested without any UI.
    public func files(for filter: AuditFilter) -> [AuditEngine.AuditedFile] {
        switch filter {
        case .all:      return files
        case .inPhotos: return inPhotos
        case .missing:  return missing
        }
    }

    /// URLs of exactly the missing files — the only set safe to import. By
    /// construction this never contains a file already judged in Photos.
    public var missingURLs: [URL] { missing.map { $0.url } }
}

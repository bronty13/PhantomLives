import Foundation

/// Verified-backup engine matching the Kyno Premium feature set.
///
/// For each file under `source`:
///   1. Stream-hash the source with the chosen algorithm.
///   2. Copy to each destination (creating intermediate directories).
///   3. Re-hash each destination copy.
///   4. Compare against source hash; fail the file if any destination
///      mismatches.
///
/// At the end, write one MHL XML per destination (a manifest of all
/// successfully verified files) into the destination root.
///
/// Concurrency: file-level loop is serial (one file at a time). Within
/// a file, copy-to-each-destination is sequential too — keeping the
/// pattern simple and giving deterministic progress. Multi-destination
/// parallel copy is a Phase-2 optimization.
enum VerifiedBackupService {

    static func run(job: BackupJob, toolVersion: String) async {
        await MainActor.run {
            job.isRunning = true
            job.startedAt = Date()
            job.finishedAt = nil
            job.summary = ""
            job.mhlPaths = []
        }
        defer {
            Task { @MainActor in
                job.isRunning = false
                job.finishedAt = Date()
            }
        }

        // ---- Discover files ------------------------------------------------
        let items: [BackupFileItem]
        do {
            items = try await discover(source: job.source)
        } catch {
            await MainActor.run {
                job.summary = "Could not enumerate source: \(error.localizedDescription)"
            }
            return
        }
        await MainActor.run { job.items = items }

        // ---- Per-destination accumulators ---------------------------------
        var entriesByDestination: [URL: [MHLEntry]] = [:]
        for dst in job.destinations { entriesByDestination[dst] = [] }

        var succeeded = 0
        var failed = 0
        var cancelledCount = 0

        for item in items {
            // C37 — bail between files when the user has hit
            // cancel. Files NOT yet processed get marked
            // .cancelled so the run sheet shows the truncated
            // state rather than leaving them stuck on .queued.
            if await MainActor.run(body: { job.isCancelled }) {
                await MainActor.run { item.state = .cancelled }
                cancelledCount += 1
                continue
            }
            do {
                // Hash source
                await MainActor.run { item.state = .hashing(bytesRead: 0) }
                let sourceHash = try await hashAsync(
                    url: item.sourceURL,
                    algorithm: job.algorithm,
                    onProgress: { bytes in
                        Task { @MainActor in
                            item.state = .hashing(bytesRead: bytes)
                        }
                    }
                )
                await MainActor.run { item.sourceHash = sourceHash }

                // Copy + verify against each destination in PARALLEL.
                // For most workloads each destination is on a different
                // physical drive — serializing forces total throughput
                // to drive_slow_min, whereas parallel saturates them
                // independently and roughly halves wall time for 2
                // destinations. Source-hash work happened once above.
                await MainActor.run { item.state = .copying }
                let results = await withTaskGroup(
                    of: (URL, Result<String, Error>).self
                ) { group in
                    for dst in job.destinations {
                        group.addTask {
                            do {
                                let dstURL = dst.appendingPathComponent(item.relativePath)
                                try FileManager.default.createDirectory(
                                    at: dstURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true
                                )
                                if FileManager.default.fileExists(atPath: dstURL.path) {
                                    try FileManager.default.removeItem(at: dstURL)
                                }
                                try FileManager.default.copyItem(at: item.sourceURL, to: dstURL)
                                let hash = try await hashAsync(
                                    url: dstURL, algorithm: job.algorithm,
                                    onProgress: { _ in }
                                )
                                return (dst, .success(hash))
                            } catch {
                                return (dst, .failure(error))
                            }
                        }
                    }
                    var collected: [(URL, Result<String, Error>)] = []
                    for await r in group { collected.append(r) }
                    return collected
                }

                var allDestinationsVerified = true
                var perFileError: String?
                for (dst, result) in results {
                    switch result {
                    case .success(let dstHash):
                        await MainActor.run { item.destinationHashes[dst] = dstHash }
                        if dstHash != sourceHash {
                            allDestinationsVerified = false
                            perFileError = "Hash mismatch at \(dst.lastPathComponent)"
                        } else {
                            await MainActor.run { item.state = .verifying(destination: dst) }
                        }
                    case .failure(let err):
                        allDestinationsVerified = false
                        perFileError = err.localizedDescription
                    }
                }

                if allDestinationsVerified {
                    let attrs = try FileManager.default.attributesOfItem(atPath: item.sourceURL.path)
                    let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                    let entry = MHLEntry(
                        relativePath: item.relativePath,
                        sizeBytes: item.sizeBytes,
                        lastModified: modDate,
                        hash: sourceHash,
                        hashAlgorithm: job.algorithm,
                        hashDate: Date()
                    )
                    for dst in job.destinations {
                        entriesByDestination[dst, default: []].append(entry)
                    }
                    succeeded += 1
                    await MainActor.run { item.state = .done }
                } else {
                    throw NSError(
                        domain: "PurpleReel.Backup", code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            perFileError ?? "verification failed"]
                    )
                }
            } catch {
                failed += 1
                await MainActor.run { item.state = .failed(error.localizedDescription) }
            }
        }

        // ---- Emit MHL per destination -------------------------------------
        let startedAt = await MainActor.run { job.startedAt ?? Date() }
        let finishedAt = Date()
        var mhlPaths: [URL] = []
        for dst in job.destinations {
            let entries = entriesByDestination[dst] ?? []
            let stamp = mhlTimestamp(date: finishedAt)
            let ext = job.mhlFormat.fileExtension
            let mhlURL = dst.appendingPathComponent(
                "\(job.source.lastPathComponent)_\(stamp).\(ext)"
            )
            do {
                switch job.mhlFormat {
                case .legacy:
                    try MHLWriter.write(
                        entries: entries,
                        rootName: job.source.lastPathComponent,
                        startDate: startedAt,
                        finishDate: finishedAt,
                        toolVersion: toolVersion,
                        to: mhlURL
                    )
                case .ascMHL:
                    try ASCMHLWriter.write(
                        entries: entries,
                        rootName: job.source.lastPathComponent,
                        startDate: startedAt,
                        finishDate: finishedAt,
                        toolVersion: toolVersion,
                        to: mhlURL
                    )
                }
                mhlPaths.append(mhlURL)
            } catch {
                NSLog("[PurpleReel] MHL write failed at \(dst.path): \(error)")
            }
        }

        // Snapshot before the MainActor hop. Capturing the `var`s
        // directly is a Swift 6 strict-concurrency error — they're
        // shared with the async caller's stack frame.
        let finalMHL = mhlPaths
        let finalSucceeded = succeeded
        let finalFailed = failed
        await MainActor.run {
            job.mhlPaths = finalMHL
            job.summary = "Done: \(finalSucceeded) verified, \(finalFailed) failed, \(finalMHL.count) MHL(s) written"
        }
    }

    // MARK: - Helpers

    private static func discover(source: URL) async throws -> [BackupFileItem] {
        try await Task.detached {
            var items: [BackupFileItem] = []
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: source,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            let rootPath = source.path
            // nextObject() instead of for-in (Swift 6 strict-concurrency).
            while let object = enumerator.nextObject() {
                guard let url = object as? URL else { continue }
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true { continue }
                let rel: String
                if url.path.hasPrefix(rootPath + "/") {
                    rel = String(url.path.dropFirst(rootPath.count + 1))
                } else {
                    rel = url.lastPathComponent
                }
                // Extract the size before the MainActor hop so the
                // non-Sendable URLResourceValues doesn't cross the
                // boundary (Swift 6 strict-concurrency).
                let size = Int64(values.fileSize ?? 0)
                let item = await MainActor.run {
                    BackupFileItem(
                        sourceURL: url,
                        relativePath: rel,
                        sizeBytes: size
                    )
                }
                items.append(item)
            }
            return items
        }.value
    }

    /// Hash on a detached task so we don't block the main actor while
    /// CryptoKit churns through gigabytes of file data.
    private static func hashAsync(url: URL,
                                   algorithm: HashAlgorithm,
                                   onProgress: @escaping (Int64) -> Void) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try HashingService.hash(file: url, algorithm: algorithm, onProgress: onProgress)
        }.value
    }

    private static func mhlTimestamp(date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: date)
    }
}

import Foundation

enum SFTPFileState: Equatable {
    case queued
    case uploading(progress: Double)
    case done
    case failed(String)
}

@MainActor
final class SFTPFileItem: ObservableObject, Identifiable {
    let id = UUID()
    let localURL: URL
    let remoteName: String
    let sizeBytes: Int64
    @Published var state: SFTPFileState = .queued

    init(localURL: URL, remoteName: String, sizeBytes: Int64) {
        self.localURL = localURL
        self.remoteName = remoteName
        self.sizeBytes = sizeBytes
    }
}

@MainActor
final class SFTPJob: ObservableObject, Identifiable {
    let id = UUID()
    let destination: SFTPDestination
    @Published var items: [SFTPFileItem]
    @Published var isRunning = false
    @Published var summary = ""
    @Published var rawLog = ""

    init(destination: SFTPDestination, items: [SFTPFileItem]) {
        self.destination = destination
        self.items = items
    }
}

/// Wraps the system `sftp` CLI. We build a batch file (`-b`) that
/// `mkdir`s the remote path (idempotent — sftp tolerates the error)
/// then `put`s each local file, and capture stdout/stderr for the log.
///
/// Per-file progress: sftp's `-v` doesn't emit byte counts useful for
/// progress bars in batch mode. For the MVP we show queued → uploading
/// → done/failed states; granular byte progress is a Phase-2 polish.
enum SFTPService {

    static func run(job: SFTPJob) async {
        await MainActor.run {
            job.isRunning = true
            job.summary = ""
            job.rawLog = ""
        }
        defer {
            Task { @MainActor in job.isRunning = false }
        }

        let dst = job.destination
        let items = await MainActor.run { job.items }

        // Reference dict for the streaming parser to update item state
        // by local-path as sftp emits "Uploading ..." / "100%" lines.
        let itemsByLocalPath: [String: SFTPFileItem] = Dictionary(
            uniqueKeysWithValues: items.map { ($0.localURL.path, $0) }
        )

        let status = await runSFTPStreaming(
            destination: dst, items: items,
            itemsByLocalPath: itemsByLocalPath,
            job: job
        )

        await MainActor.run {
            // Anything still in .uploading without a "done" trigger is
            // resolved by the final log scan.
            var failedCount = 0
            for item in items {
                switch item.state {
                case .done: continue
                case .failed: failedCount += 1; continue
                default: break
                }
                if job.rawLog.contains("remote open(") &&
                    job.rawLog.contains(item.remoteName) {
                    item.state = .failed("remote open failed")
                    failedCount += 1
                } else {
                    item.state = .failed("upload error")
                    failedCount += 1
                }
            }
            job.summary = status == 0
                ? "Done: \(items.count - failedCount) uploaded, \(failedCount) failed"
                : "sftp exited \(status). \(failedCount) of \(items.count) failed."
        }
    }

    /// Pure command construction — exposed for testability / dry-run.
    /// `-v` makes sftp emit per-file progress lines that the streaming
    /// log parser converts into `SFTPFileItem.state` updates.
    static func buildArguments(destination dst: SFTPDestination,
                                batchPath: String) -> [String] {
        var args: [String] = []
        if dst.acceptNewHostKeys {
            args += ["-o", "StrictHostKeyChecking=accept-new"]
        }
        if !dst.identityFile.isEmpty {
            args += ["-i", expandTilde(dst.identityFile)]
        }
        args += ["-P", String(dst.port)]
        args += ["-b", batchPath]
        args += ["\(dst.user)@\(dst.host)"]
        return args
    }

    static func buildBatchScript(destination dst: SFTPDestination,
                                  items: [(localURL: URL, remoteName: String)]) -> String {
        var s = ""
        s += "-mkdir \"\(dst.remotePath)\"\n"
        s += "cd \"\(dst.remotePath)\"\n"
        for item in items {
            // Quote both sides; sftp's batch parser handles quoted
            // paths with spaces correctly.
            s += "put \"\(item.localURL.path)\" \"\(item.remoteName)\"\n"
        }
        s += "bye\n"
        return s
    }

    // MARK: - Private

    /// Streaming variant: writes the batch file, launches sftp, reads
    /// stdout/stderr incrementally, parses progress lines, and updates
    /// `SFTPFileItem.state` live on the main actor.
    @MainActor
    private static func runSFTPStreaming(
        destination dst: SFTPDestination,
        items: [SFTPFileItem],
        itemsByLocalPath: [String: SFTPFileItem],
        job: SFTPJob
    ) async -> Int32 {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("purplereel-sftp-\(UUID().uuidString).batch")
        let script = buildBatchScript(destination: dst, items: items.map {
            (localURL: $0.localURL, remoteName: $0.remoteName)
        })
        do {
            try script.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            job.rawLog = "Could not write batch file: \(error.localizedDescription)"
            return -1
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        for item in items { item.state = .queued }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        task.arguments = buildArguments(destination: dst, batchPath: tmp)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            job.rawLog = "Could not start sftp: \(error.localizedDescription)"
            return -1
        }

        // Stream the pipe on a background queue, hopping back to the
        // main actor for state updates. We accumulate the raw log as
        // we go so the disclosure view stays live.
        let parserState = ParserState()
        let handle = pipe.fileHandleForReading

        // Termination + final state happens on a continuation that
        // resumes when the task exits *and* the pipe is drained.
        return await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty {
                    // EOF: process exited and pipe drained.
                    fh.readabilityHandler = nil
                    let status = task.terminationStatus
                    Task { @MainActor in
                        cont.resume(returning: status)
                    }
                    return
                }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    job.rawLog += chunk
                    parseProgress(chunk: chunk,
                                  state: parserState,
                                  itemsByLocalPath: itemsByLocalPath)
                }
            }
        }
    }

    /// Holds the "current upload" path between progress-line chunks
    /// because the percentage line is on a different line from the
    /// "Uploading X" announcement.
    @MainActor private final class ParserState {
        var currentPath: String?
        var leftover: String = ""
    }

    /// Parse a streamed chunk of sftp -v output and update live item
    /// states. Handles three line shapes:
    ///   `sftp> put "/local/foo" "foo"` → ignore
    ///   `Uploading /local/foo to foo`  → start tracking foo
    ///   `100% 1024MB  10.5MB/s  00:00` → percentage update
    @MainActor
    private static func parseProgress(chunk: String,
                                       state: ParserState,
                                       itemsByLocalPath: [String: SFTPFileItem]) {
        let combined = state.leftover + chunk
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        // Keep the last incomplete line for the next chunk.
        state.leftover = lines.last.map(String.init) ?? ""
        for raw in lines.dropLast() {
            let line = String(raw)
            // "Uploading /Users/.../clip.mov to clip.mov" — start file
            if let range = line.range(of: "Uploading ") {
                let after = line[range.upperBound...]
                // Path runs up to " to "
                if let toRange = after.range(of: " to ") {
                    let path = String(after[..<toRange.lowerBound])
                    state.currentPath = path
                    if let item = itemsByLocalPath[path] {
                        item.state = .uploading(progress: 0)
                    }
                }
                continue
            }
            // "100% 1024MB" — extract leading percentage
            if let pct = leadingPercentage(line: line),
               let path = state.currentPath,
               let item = itemsByLocalPath[path] {
                item.state = .uploading(progress: pct)
                if pct >= 1.0 {
                    item.state = .done
                    state.currentPath = nil
                }
                continue
            }
            // Failure markers — sftp prints these on stderr.
            if line.contains("remote open(") || line.contains("Permission denied")
                || line.contains("Couldn't ") {
                if let path = state.currentPath, let item = itemsByLocalPath[path] {
                    item.state = .failed(line.trimmingCharacters(in: .whitespaces))
                    state.currentPath = nil
                }
            }
        }
    }

    /// Parses a leading `<digits>%` token at the start of a line.
    /// Returns the fraction (0…1) or nil if no match.
    private static func leadingPercentage(line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        for c in trimmed {
            if c.isNumber { digits.append(c) }
            else if c == "%", !digits.isEmpty {
                if let n = Int(digits) { return min(1.0, Double(n) / 100.0) }
                return nil
            } else {
                return nil
            }
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

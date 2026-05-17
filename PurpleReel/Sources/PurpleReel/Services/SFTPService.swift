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

        // Mark all as uploading up front; sftp in batch mode runs
        // sequentially so this gives the user visual feedback even
        // without granular per-file deltas.
        await MainActor.run {
            for item in items { item.state = .uploading(progress: 0) }
        }

        let (status, log) = await Task.detached(priority: .userInitiated) {
            invokeSFTP(destination: dst, items: items.map {
                (localURL: $0.localURL, remoteName: $0.remoteName)
            })
        }.value

        // Resolve per-file final state from the captured log. sftp
        // prints "Uploading <local> to <remote>" before each transfer
        // and lines starting with the byte counter (e.g. "100% 1024MB").
        // Failures show as "remote open(...): ..." or transfer errors.
        await MainActor.run {
            job.rawLog = log
            var failedCount = 0
            for item in items {
                let needle = item.remoteName
                if log.contains("Uploading \(item.localURL.path) to ") &&
                    !log.contains("remote open(\(needle))") &&
                    !log.contains("Couldn't ") &&
                    !log.contains("Permission denied") {
                    item.state = .done
                } else if log.contains("remote open(") && log.contains(needle) {
                    item.state = .failed("remote open failed")
                    failedCount += 1
                } else if !log.contains(item.localURL.path) {
                    item.state = .failed("not attempted")
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

    private static func invokeSFTP(destination dst: SFTPDestination,
                                     items: [(localURL: URL, remoteName: String)]) -> (Int32, String) {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("purplereel-sftp-\(UUID().uuidString).batch")
        let script = buildBatchScript(destination: dst, items: items)
        do {
            try script.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            return (-1, "Could not write batch file: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        task.arguments = buildArguments(destination: dst, batchPath: tmp)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return (-1, "Could not start sftp: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let log = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, log)
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

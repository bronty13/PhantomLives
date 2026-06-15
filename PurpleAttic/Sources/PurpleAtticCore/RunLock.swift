import Foundation

/// A single-writer **advisory file lock** so manual, scheduled (hourly), and drive-connect-
/// triggered runs can never overlap. An overlap is exactly what wedged the old Cryptomator vault
/// (a manual run collided with the scheduled one). Two deliberate properties:
///
///   - **Crash-safe.** The lock lives on an open file descriptor via `flock`; the kernel releases
///     it the instant this process exits for *any* reason (clean exit, crash, `kill -9`). Unlike a
///     PID file, a died run never leaves a stale lock that blocks every future run.
///   - **Non-blocking.** `tryAcquire` returns nil immediately if another run holds the lock — the
///     caller then makes this run a clean no-op rather than queuing behind a possibly hours-long
///     initial seed (the right behavior for a laptop with an hourly + on-mount schedule).
public final class RunLock {
    private let fd: Int32
    public let path: String

    private init(fd: Int32, path: String) { self.fd = fd; self.path = path }

    /// `~/Library/Application Support/PurpleAttic/run.lock` (created on demand).
    public static func defaultURL() -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PurpleAttic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("run.lock")
    }

    /// Try to take the exclusive lock without blocking. Returns nil if another run holds it (or the
    /// lock file can't be opened). On success the holder's pid is written for diagnostics.
    public static func tryAcquire(at url: URL = defaultURL()) -> RunLock? {
        let path = url.path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        ftruncate(fd, 0)
        let info = "\(getpid())\n"
        _ = info.withCString { write(fd, $0, strlen($0)) }
        return RunLock(fd: fd, path: path)
    }

    /// Release the lock (idempotent-safe via `deinit`).
    public func release() {
        flock(fd, LOCK_UN)
        close(fd)
    }

    deinit { release() }
}

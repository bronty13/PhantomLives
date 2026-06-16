import Foundation

/// Deletes media files from disk — either to the Trash (recoverable) or permanently. A
/// file that's already gone counts as succeeded (idempotent). Pure and synchronous; callers
/// run it off the main actor.
enum DeleteService {

    struct Outcome: Sendable {
        var succeeded: [URL] = []
        var failed: [(url: URL, reason: String)] = []
    }

    static func deleteFiles(_ urls: [URL], permanently: Bool) -> Outcome {
        let fm = FileManager.default
        var outcome = Outcome()
        for url in urls {
            if !fm.fileExists(atPath: url.path) {
                outcome.succeeded.append(url)   // already gone — nothing to do
                continue
            }
            do {
                if permanently {
                    try fm.removeItem(at: url)
                } else {
                    var resulting: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &resulting)
                }
                outcome.succeeded.append(url)
            } catch {
                outcome.failed.append((url, error.localizedDescription))
            }
        }
        return outcome
    }
}

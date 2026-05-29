import Foundation
import CryptoKit

/// On-disk cache for `WaveformGenerator.Result`. Keys waveforms by the
/// source file's absolute path + size + mtime so a re-saved file
/// invalidates its cache automatically. Lives at
/// `~/Library/Caches/PurpleVoice/waveforms/<sha256>.json`.
///
/// Cache files are JSON for inspectability — they're ~12 KB each, and
/// the savings vs. binary aren't worth the debugging cost.
actor WaveformCache {

    static let shared = WaveformCache()

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = base
                .appendingPathComponent("PurpleVoice/waveforms",
                                        isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory,
                                                  withIntermediateDirectories: true)
    }

    func load(for sourceURL: URL) -> WaveformGenerator.Result? {
        let url = cacheFileURL(for: sourceURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WaveformGenerator.Result.self, from: data)
    }

    func store(_ result: WaveformGenerator.Result, for sourceURL: URL) {
        let url = cacheFileURL(for: sourceURL)
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Fetch from cache or generate fresh. Cache miss → produce →
    /// store → return. Errors during generation propagate; cache
    /// errors are swallowed (best-effort speed-up, never block).
    func waveform(for sourceURL: URL,
                  targetPeaks: Int = 1500) async throws -> WaveformGenerator.Result {
        if let cached = load(for: sourceURL) {
            return cached
        }
        let fresh = try await WaveformGenerator.generate(url: sourceURL,
                                                          targetPeaks: targetPeaks)
        store(fresh, for: sourceURL)
        return fresh
    }

    // MARK: - Internals

    /// Cache key. Includes file path, byte size, and mtime so an
    /// in-place edit (same path, new content) invalidates the entry.
    nonisolated private func cacheFileURL(for sourceURL: URL) -> URL {
        let attrs = try? FileManager.default
            .attributesOfItem(atPath: sourceURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
        let mtime = (attrs?[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(sourceURL.path)|\(size)|\(mtime)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hex).json")
    }
}

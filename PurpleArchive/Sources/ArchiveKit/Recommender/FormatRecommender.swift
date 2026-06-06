import Foundation

/// "Smart format recommender" — given what you're about to compress and your
/// constraints, suggest the best format with a one-line rationale. No other Mac
/// tool guides this; users guess between zip/7z/tar.* blindly.
public enum FormatRecommender {

    public struct Recommendation: Sendable, Equatable {
        public let format: ArchiveFormat
        public let rationale: String
    }

    /// What the user cares about for this archive.
    public struct Constraints: Sendable {
        public var needsWindowsCompatibility: Bool
        public var needsEncryption: Bool
        public var prioritizeMaxCompression: Bool   // size over speed
        public init(needsWindowsCompatibility: Bool = false,
                    needsEncryption: Bool = false,
                    prioritizeMaxCompression: Bool = false) {
            self.needsWindowsCompatibility = needsWindowsCompatibility
            self.needsEncryption = needsEncryption
            self.prioritizeMaxCompression = prioritizeMaxCompression
        }
    }

    /// File extensions whose contents are already compressed — re-compressing
    /// them wastes CPU for ~no size win, so prefer a fast/store-y path.
    static let alreadyCompressed: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "webp", "mp4", "mov", "m4v", "mkv",
        "avi", "mp3", "m4a", "aac", "flac", "ogg", "opus", "zip", "7z", "rar",
        "gz", "bz2", "xz", "zst", "tgz", "dmg", "pdf", "docx", "xlsx", "pptx",
        "epub", "apk", "jar", "webm",
    ]

    public static func recommend(inputs: [URL], constraints: Constraints) -> Recommendation {
        // Encryption today means zip (AES-256) — the only format we can encrypt.
        if constraints.needsEncryption {
            return Recommendation(format: .zip,
                rationale: "ZIP with AES-256 — the only widely-readable encrypted format, opens on every OS.")
        }
        // Cross-platform sharing → zip is the universal lingua franca.
        if constraints.needsWindowsCompatibility {
            return Recommendation(format: .zip,
                rationale: "ZIP — every Windows/macOS/Linux machine opens it without extra software.")
        }

        let (files, mostlyCompressed) = analyze(inputs)
        let single = files == 1

        if mostlyCompressed {
            return Recommendation(format: single ? .zip : .tarZst,
                rationale: "Contents are already compressed (media/office files) — \(single ? "ZIP stores" : "TAR+zstd bundles") them fast without wasting CPU re-compressing.")
        }
        if constraints.prioritizeMaxCompression {
            return Recommendation(format: .tarXz,
                rationale: "TAR + xz — highest compression ratio when smallest size matters more than speed.")
        }
        // The all-rounder: zstd is near-xz ratios at many times the speed, and
        // multithreads across Apple-Silicon cores.
        return Recommendation(format: .tarZst,
            rationale: "TAR + zstd — excellent ratio at high speed, multithreaded across all your cores. The best default.")
    }

    /// (file count, whether ≥70% of files are already-compressed types).
    static func analyze(_ inputs: [URL]) -> (files: Int, mostlyCompressed: Bool) {
        let fm = FileManager.default
        var all: [URL] = []
        for input in inputs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: input.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let en = fm.enumerator(at: input, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let u as URL in en {
                        if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                            all.append(u)
                        }
                    }
                }
            } else { all.append(input) }
        }
        guard !all.isEmpty else { return (0, false) }
        let compressed = all.filter { alreadyCompressed.contains($0.pathExtension.lowercased()) }.count
        return (all.count, Double(compressed) / Double(all.count) >= 0.7)
    }
}

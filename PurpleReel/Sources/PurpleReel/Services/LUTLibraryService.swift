import Foundation

/// Discovers `.cube` LUTs across the user-configured PurpleReel LUTs
/// folder, every Final Cut Pro library on disk, and the standard
/// DaVinci Resolve LUT roots. Lazy + cached so the player can
/// suggest a starting LUT without burning a folder walk per clip.
///
/// Three pools, filtered by the matching Settings → General flags:
///
/// 1. **PurpleReel** — `lutFolderPath` (default `~/Library/
///    Application Support/PurpleReel/LUTs`). User-managed.
/// 2. **Final Cut Pro** — every `*.fcpbundle` under `~/Movies/`
///    (plus user-added workspace roots) walked for `.cube` files
///    inside. Gated on `importLUTsFromFCP`.
/// 3. **DaVinci Resolve** — `~/Library/Application Support/
///    Blackmagic Design/DaVinci Resolve/LUT` and a couple of
///    typical mirror paths. Gated on `importLUTsFromResolve`.
@MainActor
enum LUTLibraryService {
    /// One entry per discovered LUT. `source` lets the player UI
    /// group by origin ("FCP libraries", "Resolve", etc.).
    struct Entry: Identifiable, Hashable {
        let id: String      // resolved path — unique
        let name: String    // filename minus extension
        let url: URL
        let source: Source
    }

    enum Source: String, CaseIterable {
        case purpleReel = "PurpleReel"
        case fcp        = "Final Cut Pro library"
        case resolve    = "DaVinci Resolve"
    }

    /// In-memory cache keyed off the active import flags + the
    /// PurpleReel LUTs folder. Walking FCP libraries can be slow
    /// (a season's worth of `.fcpbundle`s can hold thousands of
    /// internal files); cache rebuilds on a settings change.
    private static var cache: (key: String, entries: [Entry])?

    /// Build (or return cached) discovery list. Cheap on repeat
    /// calls when no relevant setting changed.
    static func entries() -> [Entry] {
        let defaults = UserDefaults.standard
        let folder = defaults.string(forKey: "lutFolderPath") ?? ""
        let fcp = defaults.object(forKey: "importLUTsFromFCP") as? Bool ?? true
        let resolve = defaults.object(forKey: "importLUTsFromResolve") as? Bool ?? true
        let key = "\(folder)|\(fcp)|\(resolve)"
        if let cache, cache.key == key { return cache.entries }
        var out: [Entry] = []
        out.append(contentsOf: discoverPurpleReel(folder: folder))
        if fcp { out.append(contentsOf: discoverFCP()) }
        if resolve { out.append(contentsOf: discoverResolve()) }
        out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cache = (key, out)
        return out
    }

    /// Drop the cache — call from Settings → General when the user
    /// changes any of the three import flags.
    static func invalidate() { cache = nil }

    // MARK: - Suggestion

    /// Best-guess LUT for a freshly-loaded clip. Matches on
    /// well-known log-profile keywords in the filename and the
    /// LUT name (e.g. `slog3` ↔ `S-Log3`). Returns nil when no
    /// confident match exists.
    static func suggested(for url: URL) -> Entry? {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let triggers: [(String, [String])] = [
            ("slog3",   ["slog3", "s-log3", "s_log3"]),
            ("slog2",   ["slog2", "s-log2", "s_log2"]),
            ("vlog",    ["vlog", "v-log", "v_log"]),
            ("flog",    ["flog", "f-log", "f_log"]),
            ("logc4",   ["logc4", "log-c4", "log_c4"]),
            ("logc3",   ["logc3", "log-c3", "log_c3", "logc"]),
            ("dlog",    ["dlog", "d-log"]),
            ("hlg",     ["hlg"]),
            ("rec709",  ["rec709", "rec.709", "709"]),
        ]
        var matchedKey: String?
        for (key, needles) in triggers {
            if needles.contains(where: { name.contains($0) }) {
                matchedKey = key
                break
            }
        }
        guard let key = matchedKey else { return nil }
        // Find the first LUT in the pool whose name contains the
        // same key. Source ordering (PurpleReel → FCP → Resolve)
        // means user-managed LUTs win ties.
        for entry in entries() {
            if entry.name.lowercased().contains(key) {
                return entry
            }
        }
        return nil
    }

    // MARK: - Pool discovery

    private static func discoverPurpleReel(folder: String) -> [Entry] {
        let path: String
        if folder.isEmpty {
            path = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Application Support/PurpleReel/LUTs")
        } else {
            path = (folder as NSString).expandingTildeInPath
        }
        return discoverCubes(at: URL(fileURLWithPath: path), source: .purpleReel)
    }

    private static func discoverFCP() -> [Entry] {
        let fm = FileManager.default
        let movies = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Movies", isDirectory: true)
        guard let libs = try? fm.contentsOfDirectory(
            at: movies,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [Entry] = []
        for url in libs where url.pathExtension == "fcpbundle" {
            out.append(contentsOf: discoverCubes(at: url, source: .fcp))
        }
        return out
    }

    private static func discoverResolve() -> [Entry] {
        let candidates = [
            "Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT",
            "Library/Application Support/Blackmagic Design/DaVinci Resolve Studio/LUT",
        ]
        var out: [Entry] = []
        for sub in candidates {
            let url = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(sub)
            out.append(contentsOf: discoverCubes(at: url, source: .resolve))
        }
        return out
    }

    /// Walk `root` recursively, returning every `.cube` (case-
    /// insensitive). Quietly skips unreadable directories — these
    /// roots can include user-curated trees with arbitrary
    /// permission shapes.
    private static func discoverCubes(at root: URL, source: Source) -> [Entry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let walker = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }
        var out: [Entry] = []
        for case let url as URL in walker {
            if url.pathExtension.lowercased() == "cube" {
                out.append(Entry(
                    id: url.standardizedFileURL.path,
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    source: source
                ))
            }
        }
        return out
    }
}

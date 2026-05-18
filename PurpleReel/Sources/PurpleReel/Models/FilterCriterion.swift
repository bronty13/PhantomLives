import Foundation

/// One row of the advanced Filter dropdown — composable, additive
/// (every criterion is an AND with the others). Cases stay value-typed
/// so the active-filter list can persist easily via UserDefaults as a
/// compact string and survive across launches.
///
/// To add a new criterion, extend this enum + `matches(_:tagIndex:)`,
/// + the encode/decode helpers below, + the toolbar menu in
/// `BrowserView.filterMenu`. The pill display string comes from
/// `displayLabel` so users see something readable for every
/// criterion they pin.
enum FilterCriterion: Hashable, Identifiable {
    case ratingAtLeast(Int)
    case hasTag(String)
    case videoCodec(String)
    case audioCodec(String)
    case resolutionPreset(ResolutionPreset)
    case frameRatePreset(FrameRatePreset)
    case durationAtLeastSeconds(Double)
    case durationAtMostSeconds(Double)
    case sizeAtLeastMB(Int)
    case sizeAtMostMB(Int)
    case modifiedSince(DateBucket)   // last N days / specific date
    case recordedSince(DateBucket)
    case underFolder(String)         // path-prefix scope
    case frameRateMode(FrameRateMode)  // VFR vs CFR (Kyno 1.7 parity)

    var id: String { encoded() }

    var displayLabel: String {
        switch self {
        case .ratingAtLeast(let n):
            return "Rating ≥ \(n)★"
        case .hasTag(let tag):
            return "Tag: \(tag)"
        case .videoCodec(let codec):
            return "Video: \(codec.uppercased())"
        case .audioCodec(let codec):
            return "Audio: \(codec.uppercased())"
        case .resolutionPreset(let r):
            return "Resolution: \(r.displayName)"
        case .frameRatePreset(let f):
            return "FPS: \(f.displayName)"
        case .durationAtLeastSeconds(let s):
            return "Duration ≥ \(formatDuration(s))"
        case .durationAtMostSeconds(let s):
            return "Duration ≤ \(formatDuration(s))"
        case .sizeAtLeastMB(let mb):
            return "Size ≥ \(mb) MB"
        case .sizeAtMostMB(let mb):
            return "Size ≤ \(mb) MB"
        case .modifiedSince(let b):
            return "Modified: \(b.displayName)"
        case .recordedSince(let b):
            return "Recorded: \(b.displayName)"
        case .underFolder(let p):
            let label = (p as NSString).lastPathComponent
            return "In folder: \(label.isEmpty ? p : label)"
        case .frameRateMode(let m):
            return "Frame rate: \(m.displayName)"
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    /// Test whether an asset passes this criterion. The `tagIndex`
    /// (path → Set<String> of tags) is precomputed once per filter
    /// pass to avoid per-asset DB hits.
    func matches(_ asset: Asset,
                  ratingForAsset: (Asset) -> Int,
                  tagIndex: [String: Set<String>]) -> Bool {
        switch self {
        case .ratingAtLeast(let n):
            return ratingForAsset(asset) >= n
        case .hasTag(let tag):
            return tagIndex[asset.path]?.contains(tag) ?? false
        case .videoCodec(let codec):
            let c = (asset.codec ?? "").lowercased()
            return c.contains(codec.lowercased())
        case .resolutionPreset(let preset):
            return preset.matches(width: asset.widthPx, height: asset.heightPx)
        case .frameRatePreset(let preset):
            return preset.matches(asset.frameRate)
        case .durationAtLeastSeconds(let s):
            return (asset.durationSeconds ?? 0) >= s
        case .durationAtMostSeconds(let s):
            return (asset.durationSeconds ?? Double.infinity) <= s
        case .sizeAtLeastMB(let mb):
            return asset.sizeBytes >= Int64(mb) * 1_000_000
        case .sizeAtMostMB(let mb):
            return asset.sizeBytes <= Int64(mb) * 1_000_000
        case .audioCodec(let codec):
            let c = (asset.audioCodec ?? "").lowercased()
            return c.contains(codec.lowercased())
        case .modifiedSince(let bucket):
            return bucket.matches(asset.modifiedAt)
        case .recordedSince(let bucket):
            guard let recorded = asset.recordedAt else { return false }
            return bucket.matches(recorded)
        case .underFolder(let prefix):
            let normalized = (prefix as NSString).standardizingPath
            let pfx = normalized.hasSuffix("/") ? normalized : normalized + "/"
            return (asset.path as NSString).standardizingPath.hasPrefix(pfx)
        case .frameRateMode(let mode):
            return mode.matches(asset.isVFR)
        }
    }

    // MARK: - Persistence (compact string form)

    /// Encode each criterion as a single token: `<tag>:<value>`.
    /// Used to round-trip the active-filter list through
    /// UserDefaults (`activeFilters` key).
    func encoded() -> String {
        switch self {
        case .ratingAtLeast(let n):           return "rating>=\(n)"
        case .hasTag(let tag):                return "tag=\(tag)"
        case .videoCodec(let codec):          return "vcodec=\(codec)"
        case .resolutionPreset(let p):        return "res=\(p.rawValue)"
        case .frameRatePreset(let p):         return "fps=\(p.rawValue)"
        case .durationAtLeastSeconds(let s):  return "dur>=\(s)"
        case .durationAtMostSeconds(let s):   return "dur<=\(s)"
        case .sizeAtLeastMB(let mb):          return "sizeMB>=\(mb)"
        case .sizeAtMostMB(let mb):           return "sizeMB<=\(mb)"
        case .audioCodec(let codec):          return "acodec=\(codec)"
        case .modifiedSince(let b):           return "modified=\(b.rawValue)"
        case .recordedSince(let b):           return "recorded=\(b.rawValue)"
        case .underFolder(let p):             return "folder=\(p)"
        case .frameRateMode(let m):           return "frmode=\(m.rawValue)"
        }
    }

    static func decoded(_ token: String) -> FilterCriterion? {
        if let v = strip(token, prefix: "rating>="), let n = Int(v) {
            return .ratingAtLeast(n)
        }
        if let v = strip(token, prefix: "tag=") {
            return .hasTag(v)
        }
        if let v = strip(token, prefix: "vcodec=") {
            return .videoCodec(v)
        }
        if let v = strip(token, prefix: "res="),
           let p = ResolutionPreset(rawValue: v) {
            return .resolutionPreset(p)
        }
        if let v = strip(token, prefix: "fps="),
           let p = FrameRatePreset(rawValue: v) {
            return .frameRatePreset(p)
        }
        if let v = strip(token, prefix: "dur>="), let s = Double(v) {
            return .durationAtLeastSeconds(s)
        }
        if let v = strip(token, prefix: "dur<="), let s = Double(v) {
            return .durationAtMostSeconds(s)
        }
        if let v = strip(token, prefix: "sizeMB>="), let mb = Int(v) {
            return .sizeAtLeastMB(mb)
        }
        if let v = strip(token, prefix: "sizeMB<="), let mb = Int(v) {
            return .sizeAtMostMB(mb)
        }
        if let v = strip(token, prefix: "acodec=") {
            return .audioCodec(v)
        }
        if let v = strip(token, prefix: "modified="),
           let b = DateBucket(rawValue: v) {
            return .modifiedSince(b)
        }
        if let v = strip(token, prefix: "recorded="),
           let b = DateBucket(rawValue: v) {
            return .recordedSince(b)
        }
        if let v = strip(token, prefix: "folder=") {
            return .underFolder(v)
        }
        if let v = strip(token, prefix: "frmode="),
           let m = FrameRateMode(rawValue: v) {
            return .frameRateMode(m)
        }
        return nil
    }

    private static func strip(_ s: String, prefix: String) -> String? {
        guard s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }
}

// MARK: - Preset enums

/// Common video resolution presets. `custom` is a future-extension
/// hook; not surfaced in the UI yet.
enum ResolutionPreset: String, CaseIterable, Identifiable {
    case uhd8k = "8k", uhd4k = "4k", qhd = "1440p"
    case hd1080 = "1080p", hd720 = "720p", sd480 = "480p"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uhd8k:  return "8K (≥4320p)"
        case .uhd4k:  return "4K UHD (≥2160p)"
        case .qhd:    return "1440p"
        case .hd1080: return "1080p (FHD)"
        case .hd720:  return "720p (HD)"
        case .sd480:  return "480p (SD)"
        }
    }

    func matches(width w: Int?, height h: Int?) -> Bool {
        guard let h else { return false }
        let v = max(h, w ?? 0)   // also handles portrait clips
        switch self {
        case .uhd8k:  return v >= 4320
        case .uhd4k:  return v >= 2160 && v < 4320
        case .qhd:    return v >= 1440 && v < 2160
        case .hd1080: return v >= 1080 && v < 1440
        case .hd720:  return v >= 720  && v < 1080
        case .sd480:  return v >= 480  && v < 720
        }
    }
}

/// Date-window presets used by `.modifiedSince` and `.recordedSince`.
/// Each bucket maps to a number of seconds back from now; `matches`
/// returns true when the asset's date falls inside the window. Kept
/// as discrete enum cases (rather than free-form dates) so the active
/// filter set persists cleanly via UserDefaults without serialising
/// timestamps that go stale a day later.
enum DateBucket: String, CaseIterable, Identifiable {
    case lastHour      = "1h"
    case last24h       = "24h"
    case last7d        = "7d"
    case last30d       = "30d"
    case last90d       = "90d"
    case lastYear      = "1y"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastHour: return "Last hour"
        case .last24h:  return "Last 24 hours"
        case .last7d:   return "Last 7 days"
        case .last30d:  return "Last 30 days"
        case .last90d:  return "Last 90 days"
        case .lastYear: return "Last year"
        }
    }

    private var windowSeconds: TimeInterval {
        switch self {
        case .lastHour: return 3600
        case .last24h:  return 86_400
        case .last7d:   return 7 * 86_400
        case .last30d:  return 30 * 86_400
        case .last90d:  return 90 * 86_400
        case .lastYear: return 365 * 86_400
        }
    }

    func matches(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) <= windowSeconds
    }
}

/// VFR / CFR / unknown bucket for the Filter dropdown. Reads off
/// `Asset.isVFR`, populated by MediaScanner at scan time. The
/// "unknown" bucket catches assets scanned before v5 migration
/// landed (their isVFR is NULL until rescan) and audio/image
/// assets that have no concept of frame timing.
enum FrameRateMode: String, CaseIterable, Identifiable {
    case constant = "cfr"
    case variable = "vfr"
    case unknown  = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .constant: return "Constant (CFR)"
        case .variable: return "Variable (VFR) — flag for editing"
        case .unknown:  return "Unknown / not video"
        }
    }

    func matches(_ assetIsVFR: Bool?) -> Bool {
        switch self {
        case .constant: return assetIsVFR == false
        case .variable: return assetIsVFR == true
        case .unknown:  return assetIsVFR == nil
        }
    }
}

/// Common edit-time frame-rate buckets. Match tolerates ±0.05 to
/// catch the 23.976/24.000 family-confusion edge case.
enum FrameRatePreset: String, CaseIterable, Identifiable {
    case fps2398 = "23.98"
    case fps24   = "24"
    case fps25   = "25"
    case fps2997 = "29.97"
    case fps30   = "30"
    case fps50   = "50"
    case fps5994 = "59.94"
    case fps60   = "60"

    var id: String { rawValue }
    var displayName: String { rawValue + " fps" }

    func matches(_ rate: Double?) -> Bool {
        guard let r = rate else { return false }
        let target: Double = {
            switch self {
            case .fps2398: return 23.976
            case .fps24:   return 24.0
            case .fps25:   return 25.0
            case .fps2997: return 29.97
            case .fps30:   return 30.0
            case .fps50:   return 50.0
            case .fps5994: return 59.94
            case .fps60:   return 60.0
            }
        }()
        return abs(r - target) < 0.05
    }
}

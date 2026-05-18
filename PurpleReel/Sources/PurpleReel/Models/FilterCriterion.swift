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
    case resolutionPreset(ResolutionPreset)
    case frameRatePreset(FrameRatePreset)
    case durationAtLeastSeconds(Double)
    case durationAtMostSeconds(Double)
    case sizeAtLeastMB(Int)
    case sizeAtMostMB(Int)

    var id: String { encoded() }

    var displayLabel: String {
        switch self {
        case .ratingAtLeast(let n):
            return "Rating ≥ \(n)★"
        case .hasTag(let tag):
            return "Tag: \(tag)"
        case .videoCodec(let codec):
            return "Codec: \(codec.uppercased())"
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

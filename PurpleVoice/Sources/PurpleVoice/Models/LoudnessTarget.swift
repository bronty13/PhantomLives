import Foundation

/// Target integrated loudness for the final mix, in LUFS. Maps to
/// ffmpeg's `loudnorm` filter with the broadcaster-standard true-peak
/// (-1.5 dBTP) and loudness range (11 LU) parameters. Single-pass — a
/// future version could add a two-pass mode for higher precision.
enum LoudnessTarget: String, CaseIterable, Identifiable, Codable {
    case none
    /// -16 LUFS — Apple Podcasts target, common podcast spec.
    case podcast
    /// -14 LUFS — Spotify / Apple Music / YouTube streaming target.
    case streaming
    /// -23 LUFS — EBU R128 broadcast standard.
    case broadcast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "Off"
        case .podcast:   return "Podcast (-16 LUFS)"
        case .streaming: return "Streaming (-14 LUFS)"
        case .broadcast: return "Broadcast (-23 LUFS)"
        }
    }

    /// The integrated-loudness target in LUFS. `nil` for `.none`.
    var integratedLUFS: Double? {
        switch self {
        case .none:      return nil
        case .podcast:   return -16
        case .streaming: return -14
        case .broadcast: return -23
        }
    }

    /// Filter string to append to the `-af` chain, or `nil` if off.
    /// True peak fixed at -1.5 dBTP; LRA at 11 LU — both broadcast-
    /// safe defaults that work across podcast / streaming targets.
    var filterString: String? {
        guard let i = integratedLUFS else { return nil }
        return "loudnorm=I=\(i):TP=-1.5:LRA=11"
    }
}

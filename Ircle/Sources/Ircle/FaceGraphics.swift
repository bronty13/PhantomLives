import Foundation

/// Pure (SwiftUI-free, testable) helpers for generated monogram avatars: a
/// deterministic color + initials derived from a nick. "Deterministic" matters
/// — `String.hashValue` is randomized per process, so the same nick would get a
/// different color each launch. We use a stable FNV-1a hash over the folded
/// nick instead, so a face's color is consistent across sessions and machines.
enum FaceGraphics {

    /// Stable hue in 0..<1 for a nick, for `Color(hue:saturation:brightness:)`.
    static func hue(for nick: String) -> Double {
        var h: UInt32 = 2166136261                 // FNV-1a offset basis
        for byte in IRCCase.fold(nick).utf8 {
            h = (h ^ UInt32(byte)) &* 16777619     // FNV-1a prime
        }
        return Double(h % 360) / 360.0
    }

    /// 1–2 uppercase initials for the monogram. Splits on non-alphanumerics so
    /// `bob_smith` → "BS"; a single token uses its first two letters
    /// (`alice` → "AL"); anything letterless → "?".
    static func initials(for nick: String) -> String {
        let parts = nick.split { !$0.isLetter && !$0.isNumber }
        if parts.count >= 2,
           let a = parts[0].first, let b = parts[1].first {
            return (String(a) + String(b)).uppercased()
        }
        if let only = parts.first {
            return String(only.prefix(2)).uppercased()
        }
        return "?"
    }
}

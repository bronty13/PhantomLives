import SwiftUI

/// Hex-string Color helper — accepts `#RRGGBB` or `#RRGGBBAA`.
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >>  8) & 0xff) / 255
            b = Double( v        & 0xff) / 255
            a = 1
        } else {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >>  8) & 0xff) / 255
            a = Double( v        & 0xff) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Best-effort `#RRGGBB` rendering of the color (uses NSColor sRGB conversion).
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

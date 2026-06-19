import SwiftUI
import AppKit

/// The classic Mac OS 8/9 "Platinum" look, plus a modern dark "Graphite"
/// variant. Recreated from observation of Ircle 3.x — grey bevels, monospaced
/// message text, the signature server/topic colorways — no proprietary assets.
struct PlatinumPalette {
    // Window + pane chrome
    let windowBG: Color
    let paneBG: Color          // beveled control backgrounds (channelbar, lists)
    var textBG: Color          // the message area / input field interior
    let bevelLight: Color      // top/left highlight edge
    let bevelDark: Color       // bottom/right shadow edge
    let hairline: Color        // 1px separators
    let chromeText: Color      // labels on chrome

    // Message colors
    var normalText: Color
    let timestamp: Color
    let serverText: Color      // MOTD / numerics
    let topicText: Color       // topic + system status
    let joinText: Color
    let partText: Color
    let noticeText: Color
    let actionText: Color
    let errorText: Color
    let ownNick: Color
    let otherNick: Color
    let mentionBG: Color
    let selection: Color       // selected channelbar/nick row
    /// Luminance (0…1) of `textBG`, so the mIRC renderer can keep colored text
    /// legible against the message-area background.
    var messageBackgroundLuminance: Double

    static func platinum() -> PlatinumPalette {
        PlatinumPalette(
            windowBG:   Color(white: 0.866),               // #DDDDDD
            paneBG:     Color(white: 0.80),                // #CCCCCC
            textBG:     .white,
            bevelLight: .white,
            bevelDark:  Color(white: 0.45),
            hairline:   Color(white: 0.55),
            chromeText: .black,
            normalText: .black,
            timestamp:  Color(white: 0.50),
            serverText: Color(red: 0.0,  green: 0.0,  blue: 0.70),
            topicText:  Color(red: 0.55, green: 0.0,  blue: 0.62),
            joinText:   Color(red: 0.0,  green: 0.45, blue: 0.0),
            partText:   Color(red: 0.55, green: 0.30, blue: 0.0),
            noticeText: Color(red: 0.0,  green: 0.45, blue: 0.50),
            actionText: Color(red: 0.55, green: 0.0,  blue: 0.62),
            errorText:  Color(red: 0.78, green: 0.0,  blue: 0.0),
            ownNick:    Color(red: 0.0,  green: 0.0,  blue: 0.55),
            otherNick:  Color(red: 0.30, green: 0.20, blue: 0.0),
            mentionBG:  Color(red: 1.0,  green: 1.0,  blue: 0.60),
            selection:  Color(red: 0.30, green: 0.45, blue: 0.85),
            messageBackgroundLuminance: 1.0   // white
        )
    }

    static func graphite() -> PlatinumPalette {
        PlatinumPalette(
            windowBG:   Color(white: 0.18),
            paneBG:     Color(white: 0.24),
            textBG:     Color(white: 0.11),
            bevelLight: Color(white: 0.36),
            bevelDark:  Color(white: 0.06),
            hairline:   Color(white: 0.40),
            chromeText: Color(white: 0.88),
            normalText: Color(white: 0.88),
            timestamp:  Color(white: 0.45),
            serverText: Color(red: 0.45, green: 0.65, blue: 1.0),
            topicText:  Color(red: 0.82, green: 0.50, blue: 0.95),
            joinText:   Color(red: 0.40, green: 0.80, blue: 0.45),
            partText:   Color(red: 0.85, green: 0.60, blue: 0.35),
            noticeText: Color(red: 0.40, green: 0.80, blue: 0.82),
            actionText: Color(red: 0.82, green: 0.50, blue: 0.95),
            errorText:  Color(red: 1.0,  green: 0.42, blue: 0.42),
            ownNick:    Color(red: 0.55, green: 0.72, blue: 1.0),
            otherNick:  Color(red: 0.85, green: 0.78, blue: 0.55),
            mentionBG:  Color(red: 0.40, green: 0.38, blue: 0.10),
            selection:  Color(red: 0.25, green: 0.40, blue: 0.78),
            messageBackgroundLuminance: 0.11   // Color(white: 0.11)
        )
    }

    static func forAppearance(_ a: IrcleAppearance) -> PlatinumPalette {
        switch a {
        case .platinum: return .platinum()
        case .graphite: return .graphite()
        }
    }

    /// Apply optional user overrides for the message text + background colours
    /// (hex strings; empty = keep the theme's). Recomputes the contrast
    /// luminance from a custom background so mIRC colours stay legible.
    func applying(textHex: String, backgroundHex: String) -> PlatinumPalette {
        var p = self
        if let c = Color(ircleHex: textHex) { p.normalText = c }
        if let c = Color(ircleHex: backgroundHex) {
            p.textBG = c
            p.messageBackgroundLuminance = PlatinumPalette.luminance(of: c)
        }
        return p
    }

    /// Perceived (Rec. 601) luminance 0…1 of a SwiftUI colour, via sRGB.
    static func luminance(of color: Color) -> Double {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return 1.0 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }

    // Fonts: Monaco (classic Mac monospace) for messages; Geneva (classic Mac
    // UI font) for chrome. Both ship with macOS, so no proprietary fonts.
    func messageFont(_ size: Double) -> Font { .custom("Monaco", size: size) }
    func chromeFont(_ size: Double = 11) -> Font { .custom("Geneva", size: size) }
    func chromeFontBold(_ size: Double = 11) -> Font { .custom("Geneva", size: size).bold() }

    func color(for kind: LineKind) -> Color {
        switch kind {
        case .message:    return normalText
        case .action:     return actionText
        case .notice:     return noticeText
        case .join:       return joinText
        case .part, .quit, .nickChange, .mode: return partText
        case .topic:      return topicText
        case .motd:       return serverText
        case .system:     return topicText
        case .error:      return errorText
        }
    }
}

// MARK: - Platinum bevel chrome

/// A classic two-tone 3D bevel: light highlight on the top/leading edges, dark
/// shadow on the bottom/trailing edges. `raised` = a button/tab popping out;
/// `!raised` = an inset well (message area, input field).
struct PlatinumBevel: ViewModifier {
    let palette: PlatinumPalette
    var raised: Bool = true
    var fill: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(fill ?? palette.paneBG)
            .overlay(BevelEdges(palette: palette, raised: raised))
    }
}

private struct BevelEdges: View {
    let palette: PlatinumPalette
    let raised: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let light = raised ? palette.bevelLight : palette.bevelDark
            let dark  = raised ? palette.bevelDark  : palette.bevelLight
            Path { p in
                // top + leading
                p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
            }.stroke(light, lineWidth: 1)
            Path { p in
                // bottom + trailing
                p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
            }.stroke(dark, lineWidth: 1)
        }
    }
}

extension View {
    func platinumBevel(_ palette: PlatinumPalette, raised: Bool = true, fill: Color? = nil) -> some View {
        modifier(PlatinumBevel(palette: palette, raised: raised, fill: fill))
    }
}

// MARK: - Hex ⇄ Color

extension Color {
    /// Parse a `#RRGGBB` / `RRGGBB` hex string. Empty/invalid → nil.
    init?(ircleHex hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces)
                   .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >> 8) & 0xFF) / 255.0,
                     blue: Double(v & 0xFF) / 255.0)
    }

    /// `#RRGGBB` for persistence, via sRGB. nil if the colour can't be resolved.
    var ircleHexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

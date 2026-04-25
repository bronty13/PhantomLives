import SwiftUI
import AppKit

// MARK: - Events worth a distinct sound

/// Coarse event categories the user can map to a sound. Kept small on purpose
/// — per-IRC-line sounds get maddening fast. Add here when there's a concrete
/// UX case.
enum SoundEventKind: String, CaseIterable, Identifiable, Codable {
    case mention        // someone said your nick
    case watchlistHit   // a watched nick came online / spoke
    case connect        // network connected
    case disconnect     // network disconnected / dropped
    case ctcp           // incoming CTCP request
    case privateMessage // incoming query PM (not channel)
    case highlight      // user-configured HighlightRule matched
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mention:        return "Own-nick mention"
        case .watchlistHit:   return "Watchlist hit"
        case .connect:        return "Connected"
        case .disconnect:     return "Disconnected"
        case .ctcp:           return "CTCP request"
        case .privateMessage: return "Private message"
        case .highlight:      return "Highlight match"
        }
    }
}

/// Names available through `NSSound(named:)` on macOS. These come pre-installed
/// so the user doesn't have to ship audio files. "" means "no sound".
let builtInSoundNames: [String] = [
    "", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
    "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
]

/// Plays the NSSound for an event, if one is configured. `SettingsStore` owns
/// the mapping; this stays stateless.
enum SoundPlayer {
    @MainActor
    static func play(_ kind: SoundEventKind, settings: AppSettings) {
        guard settings.soundsEnabled else { return }
        let name = settings.eventSounds[kind.rawValue] ?? ""
        guard !name.isEmpty, let snd = NSSound(named: name) else { return }
        snd.play()
    }
}

// MARK: - Chat fonts

/// Font family choices for chat-area text. The system options use Apple's
/// dynamic-type-aware `.system(...)` faces; the named ones drop down to
/// `Font.custom(...)` so we get a consistent look regardless of the user's
/// macOS body font.
enum ChatFontFamily: String, CaseIterable, Codable, Identifiable {
    case systemMono  = "System monospaced"
    case sfMono      = "SF Mono"
    case menlo       = "Menlo"
    case monaco      = "Monaco"
    case courier     = "Courier New"
    case proportional = "System proportional"
    var id: String { rawValue }

    func font(size: CGFloat) -> Font {
        switch self {
        case .systemMono:   return .system(size: size, design: .monospaced)
        case .sfMono:       return .custom("SF Mono", size: size)
        case .menlo:        return .custom("Menlo", size: size)
        case .monaco:       return .custom("Monaco", size: size)
        case .courier:      return .custom("Courier New", size: size)
        case .proportional: return .system(size: size)
        }
    }
}

// MARK: - Themes

/// A minimal color theme: just the knobs that actually show up in the chat
/// surface. Adding more is cheap (just extend here + MessageRow).
struct Theme: Identifiable, Hashable {
    let id: String
    let displayName: String
    let ownNickColor: Color
    let infoColor: Color
    let errorColor: Color
    let motdColor: Color
    let noticeColor: Color
    let actionColor: Color
    let joinColor: Color
    let partColor: Color
    let nickNickColor: Color
    let mentionBackground: Color
    let watchlistBackground: Color
    let findBackground: Color
    /// Nicks are hashed into this palette for consistent per-user coloring.
    let nickPalette: [Color]
}

extension Theme {
    static let classic = Theme(
        id: "classic",
        displayName: "Classic",
        ownNickColor: .accentColor,
        infoColor: .secondary,
        errorColor: .red,
        motdColor: .secondary,
        noticeColor: .purple,
        actionColor: .purple,
        joinColor: .green,
        partColor: .orange,
        nickNickColor: .blue,
        mentionBackground: .orange.opacity(0.18),
        watchlistBackground: .purple.opacity(0.12),
        findBackground: .yellow.opacity(0.30),
        nickPalette: [.pink, .teal, .indigo, .mint, .orange, .cyan, .brown, .purple]
    )

    static let midnight = Theme(
        id: "midnight",
        displayName: "Midnight",
        ownNickColor: Color(red: 0.55, green: 0.85, blue: 1.0),
        infoColor: Color(white: 0.65),
        errorColor: Color(red: 1.0, green: 0.45, blue: 0.45),
        motdColor: Color(white: 0.55),
        noticeColor: Color(red: 0.75, green: 0.55, blue: 0.95),
        actionColor: Color(red: 0.75, green: 0.55, blue: 0.95),
        joinColor: Color(red: 0.45, green: 0.90, blue: 0.55),
        partColor: Color(red: 0.95, green: 0.70, blue: 0.30),
        nickNickColor: Color(red: 0.35, green: 0.65, blue: 1.0),
        mentionBackground: Color(red: 1.0, green: 0.60, blue: 0.30).opacity(0.22),
        watchlistBackground: Color(red: 0.60, green: 0.40, blue: 0.90).opacity(0.18),
        findBackground: Color.yellow.opacity(0.28),
        nickPalette: [
            Color(red: 1.00, green: 0.55, blue: 0.75),
            Color(red: 0.45, green: 0.85, blue: 0.95),
            Color(red: 0.55, green: 0.70, blue: 1.00),
            Color(red: 0.45, green: 0.95, blue: 0.75),
            Color(red: 1.00, green: 0.75, blue: 0.40),
            Color(red: 0.50, green: 0.95, blue: 0.95),
            Color(red: 0.90, green: 0.70, blue: 0.55),
            Color(red: 0.80, green: 0.65, blue: 1.00)
        ]
    )

    static let candy = Theme(
        id: "candy",
        displayName: "Candy",
        ownNickColor: Color(red: 0.80, green: 0.35, blue: 0.65),
        infoColor: Color(red: 0.55, green: 0.45, blue: 0.60),
        errorColor: Color(red: 0.90, green: 0.25, blue: 0.35),
        motdColor: Color(red: 0.55, green: 0.45, blue: 0.60),
        noticeColor: Color(red: 0.70, green: 0.30, blue: 0.85),
        actionColor: Color(red: 0.85, green: 0.45, blue: 0.75),
        joinColor: Color(red: 0.30, green: 0.75, blue: 0.55),
        partColor: Color(red: 0.95, green: 0.55, blue: 0.30),
        nickNickColor: Color(red: 0.30, green: 0.50, blue: 0.95),
        mentionBackground: Color(red: 1.0, green: 0.60, blue: 0.75).opacity(0.28),
        watchlistBackground: Color(red: 0.85, green: 0.55, blue: 1.0).opacity(0.22),
        findBackground: Color(red: 1.0, green: 0.95, blue: 0.30).opacity(0.45),
        nickPalette: [
            Color(red: 0.95, green: 0.50, blue: 0.70),
            Color(red: 0.40, green: 0.80, blue: 0.90),
            Color(red: 0.60, green: 0.45, blue: 0.90),
            Color(red: 0.45, green: 0.80, blue: 0.55),
            Color(red: 1.00, green: 0.65, blue: 0.35),
            Color(red: 0.35, green: 0.80, blue: 0.80),
            Color(red: 0.75, green: 0.55, blue: 0.40),
            Color(red: 0.75, green: 0.45, blue: 0.85)
        ]
    )

    // MARK: - Curated themes

    /// Solarized Light (Ethan Schoonover). Warm cream background; the
    /// "softest" of the bright themes — easy on the eyes for long sessions.
    static let solarizedLight = Theme(
        id: "solarizedLight",
        displayName: "Solarized Light",
        ownNickColor: Color(hex: "#268BD2") ?? .blue,
        infoColor: Color(hex: "#586E75") ?? .secondary,
        errorColor: Color(hex: "#DC322F") ?? .red,
        motdColor: Color(hex: "#93A1A1") ?? .secondary,
        noticeColor: Color(hex: "#6C71C4") ?? .purple,
        actionColor: Color(hex: "#D33682") ?? .pink,
        joinColor: Color(hex: "#859900") ?? .green,
        partColor: Color(hex: "#CB4B16") ?? .orange,
        nickNickColor: Color(hex: "#268BD2") ?? .blue,
        mentionBackground: (Color(hex: "#B58900") ?? .yellow).opacity(0.20),
        watchlistBackground: (Color(hex: "#6C71C4") ?? .purple).opacity(0.16),
        findBackground: (Color(hex: "#B58900") ?? .yellow).opacity(0.32),
        nickPalette: [
            Color(hex: "#DC322F") ?? .red, Color(hex: "#268BD2") ?? .blue,
            Color(hex: "#859900") ?? .green, Color(hex: "#D33682") ?? .pink,
            Color(hex: "#2AA198") ?? .teal, Color(hex: "#6C71C4") ?? .purple,
            Color(hex: "#CB4B16") ?? .orange, Color(hex: "#B58900") ?? .yellow
        ]
    )

    /// Solarized Dark — same accent palette, dark teal background.
    static let solarizedDark = Theme(
        id: "solarizedDark",
        displayName: "Solarized Dark",
        ownNickColor: Color(hex: "#268BD2") ?? .blue,
        infoColor: Color(hex: "#93A1A1") ?? .secondary,
        errorColor: Color(hex: "#DC322F") ?? .red,
        motdColor: Color(hex: "#586E75") ?? .secondary,
        noticeColor: Color(hex: "#6C71C4") ?? .purple,
        actionColor: Color(hex: "#D33682") ?? .pink,
        joinColor: Color(hex: "#859900") ?? .green,
        partColor: Color(hex: "#CB4B16") ?? .orange,
        nickNickColor: Color(hex: "#2AA198") ?? .teal,
        mentionBackground: (Color(hex: "#B58900") ?? .yellow).opacity(0.22),
        watchlistBackground: (Color(hex: "#6C71C4") ?? .purple).opacity(0.20),
        findBackground: (Color(hex: "#B58900") ?? .yellow).opacity(0.34),
        nickPalette: [
            Color(hex: "#DC322F") ?? .red, Color(hex: "#268BD2") ?? .blue,
            Color(hex: "#859900") ?? .green, Color(hex: "#D33682") ?? .pink,
            Color(hex: "#2AA198") ?? .teal, Color(hex: "#6C71C4") ?? .purple,
            Color(hex: "#CB4B16") ?? .orange, Color(hex: "#B58900") ?? .yellow
        ]
    )

    /// Nord (https://www.nordtheme.com) — cool, low-saturation arctic palette.
    static let nord = Theme(
        id: "nord",
        displayName: "Nord",
        ownNickColor: Color(hex: "#88C0D0") ?? .cyan,
        infoColor: Color(hex: "#D8DEE9") ?? .secondary,
        errorColor: Color(hex: "#BF616A") ?? .red,
        motdColor: Color(hex: "#4C566A") ?? .secondary,
        noticeColor: Color(hex: "#B48EAD") ?? .purple,
        actionColor: Color(hex: "#B48EAD") ?? .purple,
        joinColor: Color(hex: "#A3BE8C") ?? .green,
        partColor: Color(hex: "#D08770") ?? .orange,
        nickNickColor: Color(hex: "#81A1C1") ?? .blue,
        mentionBackground: (Color(hex: "#EBCB8B") ?? .yellow).opacity(0.22),
        watchlistBackground: (Color(hex: "#B48EAD") ?? .purple).opacity(0.20),
        findBackground: (Color(hex: "#EBCB8B") ?? .yellow).opacity(0.34),
        nickPalette: [
            Color(hex: "#BF616A") ?? .red, Color(hex: "#A3BE8C") ?? .green,
            Color(hex: "#EBCB8B") ?? .yellow, Color(hex: "#81A1C1") ?? .blue,
            Color(hex: "#B48EAD") ?? .purple, Color(hex: "#88C0D0") ?? .cyan,
            Color(hex: "#D08770") ?? .orange, Color(hex: "#5E81AC") ?? .indigo
        ]
    )

    /// Dracula (https://draculatheme.com) — vibrant accents on a deep
    /// purple background. Popular dev/chat theme.
    static let dracula = Theme(
        id: "dracula",
        displayName: "Dracula",
        ownNickColor: Color(hex: "#FF79C6") ?? .pink,
        infoColor: Color(hex: "#6272A4") ?? .secondary,
        errorColor: Color(hex: "#FF5555") ?? .red,
        motdColor: Color(hex: "#6272A4") ?? .secondary,
        noticeColor: Color(hex: "#BD93F9") ?? .purple,
        actionColor: Color(hex: "#BD93F9") ?? .purple,
        joinColor: Color(hex: "#50FA7B") ?? .green,
        partColor: Color(hex: "#FFB86C") ?? .orange,
        nickNickColor: Color(hex: "#8BE9FD") ?? .cyan,
        mentionBackground: (Color(hex: "#F1FA8C") ?? .yellow).opacity(0.22),
        watchlistBackground: (Color(hex: "#BD93F9") ?? .purple).opacity(0.22),
        findBackground: (Color(hex: "#F1FA8C") ?? .yellow).opacity(0.36),
        nickPalette: [
            Color(hex: "#FF79C6") ?? .pink,    Color(hex: "#8BE9FD") ?? .cyan,
            Color(hex: "#50FA7B") ?? .green,   Color(hex: "#FFB86C") ?? .orange,
            Color(hex: "#BD93F9") ?? .purple,  Color(hex: "#F1FA8C") ?? .yellow,
            Color(hex: "#FF5555") ?? .red,     Color(hex: "#6272A4") ?? .blue
        ]
    )

    /// High contrast — pure black/white with bold saturated accents.
    /// Designed for low-vision users + bright environments.
    static let highContrast = Theme(
        id: "highContrast",
        displayName: "High Contrast",
        ownNickColor: Color(red: 0.30, green: 0.55, blue: 1.0),
        infoColor: .primary,
        errorColor: Color(red: 1.0,  green: 0.20, blue: 0.20),
        motdColor: .primary,
        noticeColor: Color(red: 0.85, green: 0.30, blue: 1.0),
        actionColor: Color(red: 0.85, green: 0.30, blue: 1.0),
        joinColor: Color(red: 0.0,   green: 0.75, blue: 0.0),
        partColor: Color(red: 1.0,   green: 0.55, blue: 0.0),
        nickNickColor: Color(red: 0.20, green: 0.40, blue: 1.0),
        mentionBackground: Color.yellow.opacity(0.55),
        watchlistBackground: Color.purple.opacity(0.45),
        findBackground: Color.yellow.opacity(0.65),
        nickPalette: [
            .red, .blue, .green, .purple,
            .orange, .pink, .cyan, .brown
        ]
    )

    /// Sepia — warm cream + brown for low-blue-light reading.
    static let sepia = Theme(
        id: "sepia",
        displayName: "Sepia",
        ownNickColor: Color(hex: "#8B5E3C") ?? .brown,
        infoColor: Color(hex: "#7A6753") ?? .secondary,
        errorColor: Color(hex: "#A03020") ?? .red,
        motdColor: Color(hex: "#9C8A6E") ?? .secondary,
        noticeColor: Color(hex: "#765940") ?? .brown,
        actionColor: Color(hex: "#A05F30") ?? .orange,
        joinColor: Color(hex: "#5C7B3A") ?? .green,
        partColor: Color(hex: "#A06030") ?? .orange,
        nickNickColor: Color(hex: "#5B4636") ?? .brown,
        mentionBackground: (Color(hex: "#D2A55E") ?? .orange).opacity(0.30),
        watchlistBackground: (Color(hex: "#A07A5C") ?? .brown).opacity(0.25),
        findBackground: (Color(hex: "#E5C97D") ?? .yellow).opacity(0.45),
        nickPalette: [
            Color(hex: "#A03020") ?? .red,    Color(hex: "#5C7B3A") ?? .green,
            Color(hex: "#D2A55E") ?? .orange, Color(hex: "#765940") ?? .brown,
            Color(hex: "#A05F30") ?? .orange, Color(hex: "#5B4636") ?? .brown,
            Color(hex: "#7A6753") ?? .secondary, Color(hex: "#9C8A6E") ?? .secondary
        ]
    )

    static let all: [Theme] = [
        .classic, .midnight, .candy,
        .solarizedLight, .solarizedDark,
        .nord, .dracula,
        .sepia, .highContrast
    ]

    static func named(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? .classic
    }
}

// MARK: - Color(hex:)

extension Color {
    /// Parse "#RRGGBB" / "RRGGBB" / "#AARRGGBB" / "AARRGGBB". Returns nil for
    /// anything else. Used by HighlightRule.colorHex so SwiftUI ColorPicker's
    /// native Color can round-trip through Codable settings.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double( v        & 0xFF) / 255.0
            a = 1.0
        case 8:
            a = Double((v >> 24) & 0xFF) / 255.0
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double( v        & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// #RRGGBB representation of this color (falls back to #000000 on
    /// extraction failure). Used to persist the ColorPicker selection.
    var hexRGB: String {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#000000"
        #endif
    }
}

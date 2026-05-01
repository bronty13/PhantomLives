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

// MARK: - Timestamp formats

/// Curated DateFormatter patterns for chat-line timestamps. Each `rawValue`
/// is a real `dateFormat` string, so the picker writes the chosen pattern
/// straight into AppSettings and BufferView feeds it to a DateFormatter.
/// Stored as String in settings so a future "custom format" field can
/// drop in without touching the data layer.
enum TimestampFormat: String, CaseIterable, Identifiable, Codable {
    case time24       = "HH:mm:ss"
    case time24NoSec  = "HH:mm"
    case time12       = "h:mm:ss a"
    case time12NoSec  = "h:mm a"
    case dateTime     = "MMM d, HH:mm"
    case dateTimeFull = "yyyy-MM-dd HH:mm:ss"
    case isoCompact   = "yyyy-MM-dd HH:mm"
    var id: String { rawValue }

    /// Human-readable preview for the picker — sample value plus a
    /// short hint so users don't have to read DateFormatter syntax.
    var displayName: String {
        switch self {
        case .time24:        return "23:59:59 — 24-hour, with seconds (default)"
        case .time24NoSec:   return "23:59 — 24-hour"
        case .time12:        return "11:59:59 PM — 12-hour, with seconds"
        case .time12NoSec:   return "11:59 PM — 12-hour"
        case .dateTime:      return "Apr 25, 23:59 — short date + time"
        case .dateTimeFull:  return "2026-04-25 23:59:59 — full timestamp"
        case .isoCompact:    return "2026-04-25 23:59 — date + time"
        }
    }
}

// MARK: - Themes

/// A minimal color theme: just the knobs that actually show up in the chat
/// surface. Adding more is cheap (just extend here + MessageRow).
struct Theme: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Surface colour for the message pane. Themes that want to follow the
    /// OS appearance (light vs dark) keep this at `Color(nsColor: .textBackgroundColor)`;
    /// fixed themes (Solarized, Sepia, Dracula, Paper, etc.) supply their
    /// own background so picking "Solarized Light" actually shows cream
    /// even when the user's macOS is in dark mode.
    let chatBackground: Color
    /// Default body text colour — applied via .foregroundStyle on the
    /// chat container so child Text views inherit when they don't override.
    let chatForeground: Color
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

    /// True when the theme is meant to read as a light theme (light bg).
    /// Used by the Appearance tab to group / sort cards. Heuristic: green
    /// channel value of `chatBackground` over 0.55 → light. Adaptive themes
    /// (Classic, High Contrast) fall back to the OS appearance and aren't
    /// classified.
    var isLightish: Bool {
        #if canImport(AppKit)
        let ns = NSColor(chatBackground).usingColorSpace(.sRGB) ?? .clear
        // Approximate luminance via the green channel — close enough for
        // grouping; full Y′ would mean importing more or hand-rolling.
        return ns.greenComponent > 0.55
        #else
        return false
        #endif
    }
}

extension Theme {
    static let classic = Theme(
        id: "classic",
        displayName: "Classic",
        chatBackground: Color(nsColor: .textBackgroundColor),
        chatForeground: .primary,
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
        chatBackground: Color(red: 0.10, green: 0.12, blue: 0.16),
        chatForeground: Color(white: 0.92),
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
        chatBackground: Color(red: 1.00, green: 0.96, blue: 0.97),
        chatForeground: Color(red: 0.30, green: 0.10, blue: 0.25),
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
        chatBackground: Color(hex: "#FDF6E3") ?? .white,
        chatForeground: Color(hex: "#586E75") ?? .black,
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
        chatBackground: Color(hex: "#002B36") ?? .black,
        chatForeground: Color(hex: "#93A1A1") ?? .white,
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
        chatBackground: Color(hex: "#2E3440") ?? .black,
        chatForeground: Color(hex: "#D8DEE9") ?? .white,
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
        chatBackground: Color(hex: "#282A36") ?? .black,
        chatForeground: Color(hex: "#F8F8F2") ?? .white,
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
        chatBackground: Color(nsColor: .textBackgroundColor),
        chatForeground: .primary,
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
        chatBackground: Color(hex: "#F4F0E8") ?? .white,
        chatForeground: Color(hex: "#5B4636") ?? .black,
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

    /// Paper — clean off-white reading surface with restrained accents.
    /// The "minimal light" option for users who want something distinctly
    /// non-dark on top of (or independent of) the OS appearance.
    static let paper = Theme(
        id: "paper",
        displayName: "Paper",
        chatBackground: Color(hex: "#FAFAF7") ?? .white,
        chatForeground: Color(hex: "#2A2A2A") ?? .black,
        ownNickColor: Color(hex: "#1A6FB0") ?? .blue,
        infoColor: Color(hex: "#777777") ?? .secondary,
        errorColor: Color(hex: "#B5302A") ?? .red,
        motdColor: Color(hex: "#888888") ?? .secondary,
        noticeColor: Color(hex: "#7B47B5") ?? .purple,
        actionColor: Color(hex: "#B5447B") ?? .pink,
        joinColor: Color(hex: "#3F8C3F") ?? .green,
        partColor: Color(hex: "#B86A22") ?? .orange,
        nickNickColor: Color(hex: "#1A6FB0") ?? .blue,
        mentionBackground: (Color(hex: "#FFD45C") ?? .yellow).opacity(0.30),
        watchlistBackground: (Color(hex: "#7B47B5") ?? .purple).opacity(0.16),
        findBackground: (Color(hex: "#FFD45C") ?? .yellow).opacity(0.45),
        nickPalette: [
            Color(hex: "#B5302A") ?? .red,    Color(hex: "#1A6FB0") ?? .blue,
            Color(hex: "#3F8C3F") ?? .green,  Color(hex: "#B86A22") ?? .orange,
            Color(hex: "#7B47B5") ?? .purple, Color(hex: "#0F8B8D") ?? .teal,
            Color(hex: "#B5447B") ?? .pink,   Color(hex: "#5C5C5C") ?? .secondary
        ]
    )

    /// Tokyo Night — popular dark dev theme; deep navy background with
    /// vibrant cool accents.
    static let tokyoNight = Theme(
        id: "tokyoNight",
        displayName: "Tokyo Night",
        chatBackground: Color(hex: "#1A1B26") ?? .black,
        chatForeground: Color(hex: "#C0CAF5") ?? .white,
        ownNickColor: Color(hex: "#7AA2F7") ?? .blue,
        infoColor: Color(hex: "#565F89") ?? .secondary,
        errorColor: Color(hex: "#F7768E") ?? .red,
        motdColor: Color(hex: "#414868") ?? .secondary,
        noticeColor: Color(hex: "#BB9AF7") ?? .purple,
        actionColor: Color(hex: "#BB9AF7") ?? .purple,
        joinColor: Color(hex: "#9ECE6A") ?? .green,
        partColor: Color(hex: "#FF9E64") ?? .orange,
        nickNickColor: Color(hex: "#2AC3DE") ?? .cyan,
        mentionBackground: (Color(hex: "#E0AF68") ?? .yellow).opacity(0.22),
        watchlistBackground: (Color(hex: "#BB9AF7") ?? .purple).opacity(0.20),
        findBackground: (Color(hex: "#E0AF68") ?? .yellow).opacity(0.34),
        nickPalette: [
            Color(hex: "#F7768E") ?? .red,    Color(hex: "#9ECE6A") ?? .green,
            Color(hex: "#E0AF68") ?? .yellow, Color(hex: "#7AA2F7") ?? .blue,
            Color(hex: "#BB9AF7") ?? .purple, Color(hex: "#2AC3DE") ?? .cyan,
            Color(hex: "#FF9E64") ?? .orange, Color(hex: "#73DACA") ?? .mint
        ]
    )

    /// Lavender — flagship light. Soft lavender surface with deep plum
    /// text and royal-purple accents. PurpleIRC's signature light look.
    static let lavender = Theme(
        id: "lavender",
        displayName: "Lavender",
        chatBackground: Color(hex: "#F5F0FA") ?? .white,
        chatForeground: Color(hex: "#3D1D5C") ?? .black,
        ownNickColor: Color(hex: "#7B2CBF") ?? .purple,
        infoColor: Color(hex: "#7C5C95") ?? .secondary,
        errorColor: Color(hex: "#C8302D") ?? .red,
        motdColor: Color(hex: "#9A85B2") ?? .secondary,
        noticeColor: Color(hex: "#9A4CC4") ?? .purple,
        actionColor: Color(hex: "#C246A0") ?? .pink,
        joinColor: Color(hex: "#3F8C5F") ?? .green,
        partColor: Color(hex: "#C26A30") ?? .orange,
        nickNickColor: Color(hex: "#5C45A0") ?? .blue,
        mentionBackground: (Color(hex: "#FFD45C") ?? .yellow).opacity(0.30),
        watchlistBackground: (Color(hex: "#9A4CC4") ?? .purple).opacity(0.18),
        findBackground: (Color(hex: "#FFD45C") ?? .yellow).opacity(0.40),
        nickPalette: [
            Color(hex: "#7B2CBF") ?? .purple, Color(hex: "#3F8C5F") ?? .green,
            Color(hex: "#C26A30") ?? .orange, Color(hex: "#5C45A0") ?? .blue,
            Color(hex: "#C246A0") ?? .pink,   Color(hex: "#0F8B8D") ?? .teal,
            Color(hex: "#C8302D") ?? .red,    Color(hex: "#7C5C95") ?? .secondary
        ]
    )

    /// Royal Cream — warm cream surface with deep plum text. The "long
    /// reading" companion to Lavender for users who prefer warm vs cool
    /// light themes.
    static let royalCream = Theme(
        id: "royalCream",
        displayName: "Royal Cream",
        chatBackground: Color(hex: "#FAF5F2") ?? .white,
        chatForeground: Color(hex: "#4A2870") ?? .black,
        ownNickColor: Color(hex: "#7B2CBF") ?? .purple,
        infoColor: Color(hex: "#8B6E7E") ?? .secondary,
        errorColor: Color(hex: "#B5302A") ?? .red,
        motdColor: Color(hex: "#9C8A8A") ?? .secondary,
        noticeColor: Color(hex: "#9A4CC4") ?? .purple,
        actionColor: Color(hex: "#B5447B") ?? .pink,
        joinColor: Color(hex: "#5C7B3A") ?? .green,
        partColor: Color(hex: "#A06030") ?? .orange,
        nickNickColor: Color(hex: "#4A2870") ?? .purple,
        mentionBackground: (Color(hex: "#D4A95E") ?? .yellow).opacity(0.30),
        watchlistBackground: (Color(hex: "#9A4CC4") ?? .purple).opacity(0.20),
        findBackground: (Color(hex: "#E5C97D") ?? .yellow).opacity(0.40),
        nickPalette: [
            Color(hex: "#7B2CBF") ?? .purple, Color(hex: "#5C7B3A") ?? .green,
            Color(hex: "#D4A95E") ?? .orange, Color(hex: "#A05F30") ?? .brown,
            Color(hex: "#B5447B") ?? .pink,   Color(hex: "#4A2870") ?? .blue,
            Color(hex: "#0F8B8D") ?? .teal,   Color(hex: "#B5302A") ?? .red
        ]
    )

    /// Royal Purple — flagship dark. Deep eggplant surface with lavender
    /// text and warm gold + magenta accents. PurpleIRC's signature dark.
    static let royalPurple = Theme(
        id: "royalPurple",
        displayName: "Royal Purple",
        chatBackground: Color(hex: "#1B0F2E") ?? .black,
        chatForeground: Color(hex: "#E0D4F2") ?? .white,
        ownNickColor: Color(hex: "#FFB347") ?? .orange,
        infoColor: Color(hex: "#9985B5") ?? .secondary,
        errorColor: Color(hex: "#FF7A8A") ?? .red,
        motdColor: Color(hex: "#7C6896") ?? .secondary,
        noticeColor: Color(hex: "#D9A6E8") ?? .pink,
        actionColor: Color(hex: "#E8A4D4") ?? .pink,
        joinColor: Color(hex: "#A8E89C") ?? .green,
        partColor: Color(hex: "#FFC580") ?? .orange,
        nickNickColor: Color(hex: "#B8A4FF") ?? .blue,
        mentionBackground: (Color(hex: "#FFB347") ?? .orange).opacity(0.22),
        watchlistBackground: (Color(hex: "#D9A6E8") ?? .purple).opacity(0.22),
        findBackground: (Color(hex: "#FFE066") ?? .yellow).opacity(0.36),
        nickPalette: [
            Color(hex: "#FFB347") ?? .orange, Color(hex: "#B8A4FF") ?? .blue,
            Color(hex: "#A8E89C") ?? .green,  Color(hex: "#E8A4D4") ?? .pink,
            Color(hex: "#D9A6E8") ?? .purple, Color(hex: "#FFE066") ?? .yellow,
            Color(hex: "#7AC4D4") ?? .cyan,   Color(hex: "#FF9999") ?? .red
        ]
    )

    /// Twilight — softer dark purple. Easier-on-the-eyes companion to
    /// Royal Purple for long sessions.
    static let twilight = Theme(
        id: "twilight",
        displayName: "Twilight",
        chatBackground: Color(hex: "#2A1B3D") ?? .black,
        chatForeground: Color(hex: "#D8C4ED") ?? .white,
        ownNickColor: Color(hex: "#FFB6C1") ?? .pink,
        infoColor: Color(hex: "#8E78A8") ?? .secondary,
        errorColor: Color(hex: "#FF8A95") ?? .red,
        motdColor: Color(hex: "#6F5B85") ?? .secondary,
        noticeColor: Color(hex: "#C29AED") ?? .purple,
        actionColor: Color(hex: "#E8A8D9") ?? .pink,
        joinColor: Color(hex: "#90E0C0") ?? .green,
        partColor: Color(hex: "#FFB088") ?? .orange,
        nickNickColor: Color(hex: "#A8C8FF") ?? .blue,
        mentionBackground: (Color(hex: "#FFB6C1") ?? .pink).opacity(0.20),
        watchlistBackground: (Color(hex: "#C29AED") ?? .purple).opacity(0.20),
        findBackground: (Color(hex: "#FFE799") ?? .yellow).opacity(0.34),
        nickPalette: [
            Color(hex: "#FFB6C1") ?? .pink,   Color(hex: "#A8C8FF") ?? .blue,
            Color(hex: "#90E0C0") ?? .green,  Color(hex: "#FFE799") ?? .yellow,
            Color(hex: "#C29AED") ?? .purple, Color(hex: "#88D8E8") ?? .cyan,
            Color(hex: "#FFB088") ?? .orange, Color(hex: "#E8A8D9") ?? .pink
        ]
    )

    static let all: [Theme] = [
        // Flagship purple — signature looks for the product. Lead with these.
        .lavender, .royalCream, .royalPurple, .twilight,
        // Other lights
        .paper, .solarizedLight, .sepia, .candy,
        // System-adaptive
        .classic, .highContrast,
        // Other darks
        .midnight, .solarizedDark, .nord, .dracula, .tokyoNight
    ]

    static func named(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? .classic
    }

    /// Resolve a theme id against the union of built-ins and user themes.
    /// Built-ins win on id collision (don't let a user theme shadow
    /// `classic` by mistake). Falls back to `.classic` when no match.
    static func resolve(id: String, userThemes: [UserTheme]) -> Theme {
        if let built = all.first(where: { $0.id == id }) { return built }
        if let custom = userThemes.first(where: { $0.id.uuidString == id }) {
            return custom.materialised
        }
        return .classic
    }
}

// MARK: - Per-event color overlay

/// Stable string tags for `ChatLine.Kind` variants so the theme system
/// can keep a sparse `[String: Color]` overlay without depending on
/// SwiftUI Color's brittle Codable conformance. UserTheme stores hex
/// strings keyed by these tags; a missing key means "inherit from the
/// theme's base palette."
enum ChatLineKindTag: String, CaseIterable, Codable {
    case info        = "info"
    case error       = "error"
    case privmsgSelf = "privmsg.self"   // your own messages
    case privmsg     = "privmsg"        // others' messages
    case action      = "action"          // /me lines
    case notice      = "notice"
    case join        = "join"
    case part        = "part"
    case quit        = "quit"
    case nick        = "nick"
    case topic       = "topic"
    case raw         = "raw"
    case mention     = "mention"         // own-nick mention background
    case watchlist   = "watchlist"       // watch-hit row background

    var displayName: String {
        switch self {
        case .info:        return "System / info"
        case .error:       return "Error"
        case .privmsgSelf: return "Your own messages"
        case .privmsg:     return "Other people's messages"
        case .action:      return "/me actions"
        case .notice:      return "NOTICE lines"
        case .join:        return "Join"
        case .part:        return "Part"
        case .quit:        return "Quit"
        case .nick:        return "Nick change"
        case .topic:       return "Topic change"
        case .raw:         return "Raw protocol lines"
        case .mention:     return "Mention background"
        case .watchlist:   return "Watch-hit background"
        }
    }
}

// Per-event overrides aren't stored on `Theme` itself — that would force
// touching the 16 built-in theme literals + every Hashable conformance.
// Instead, ChatModel.kindColor(for:) resolves overrides by looking up
// the currently-active UserTheme (when one is selected) in
// `AppSettings.userThemes` and reading its `kindOverrideHex` map.
// MessageRow calls `model.kindColor(for:) ?? theme.someColor` at the
// render seam.

// MARK: - UserTheme (Codable, persisted in AppSettings.userThemes)

/// Round-trippable theme stored in `settings.json`. Mirrors `Theme`'s
/// fields as hex strings (so SwiftUI Color doesn't have to Codable
/// itself), plus a `kindOverrides` map for per-event palette tweaks.
///
/// On load, `materialised` produces a real `Theme` value the renderer
/// can use. The materialised theme carries its overrides via the
/// `_overrideStore` table so `Theme.kindOverride(for:)` returns them
/// without changing the built-in `Theme` struct's stored properties.
struct UserTheme: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Built-in theme this was duplicated from, if any. Pure metadata —
    /// the renderer doesn't use it; it's surfaced in the builder so the
    /// user can see where their custom started.
    var basedOn: String?
    /// Wall-clock creation time. Surfaced in the builder list so the
    /// user can sort their library.
    var createdAt: Date = Date()

    // Hex-encoded color slots — same names as Theme so the builder UI
    // can be a pure mapping table.
    var chatBackgroundHex: String
    var chatForegroundHex: String
    var ownNickColorHex: String
    var infoColorHex: String
    var errorColorHex: String
    var motdColorHex: String
    var noticeColorHex: String
    var actionColorHex: String
    var joinColorHex: String
    var partColorHex: String
    var nickNickColorHex: String
    var mentionBackgroundHex: String
    var watchlistBackgroundHex: String
    var findBackgroundHex: String
    /// Hex per nick-palette slot. Builder enforces 8 entries; loader
    /// pads or truncates to 8 so every theme has the same shape.
    var nickPaletteHex: [String]
    /// Per-event color overrides keyed by `ChatLineKindTag.rawValue`.
    /// Sparse — a missing key means "inherit from the slot above".
    var kindOverrideHex: [String: String] = [:]

    /// Build a UserTheme by snapshotting an existing built-in theme.
    /// The new theme gets a fresh UUID and a name derived from the base.
    static func duplicate(of base: Theme, name: String) -> UserTheme {
        UserTheme(
            name: name.isEmpty ? "Custom from \(base.displayName)" : name,
            basedOn: base.id,
            chatBackgroundHex:     base.chatBackground.hexRGB,
            chatForegroundHex:     base.chatForeground.hexRGB,
            ownNickColorHex:       base.ownNickColor.hexRGB,
            infoColorHex:          base.infoColor.hexRGB,
            errorColorHex:         base.errorColor.hexRGB,
            motdColorHex:          base.motdColor.hexRGB,
            noticeColorHex:        base.noticeColor.hexRGB,
            actionColorHex:        base.actionColor.hexRGB,
            joinColorHex:          base.joinColor.hexRGB,
            partColorHex:          base.partColor.hexRGB,
            nickNickColorHex:      base.nickNickColor.hexRGB,
            mentionBackgroundHex:  base.mentionBackground.hexRGB,
            watchlistBackgroundHex: base.watchlistBackground.hexRGB,
            findBackgroundHex:     base.findBackground.hexRGB,
            nickPaletteHex: base.nickPalette.map { $0.hexRGB }
        )
    }

    /// Construct the runtime `Theme` from this UserTheme. Hex strings
    /// that fail to parse fall back to a sane default. Per-event
    /// overrides are NOT applied here — `ChatModel.kindColor(for:)`
    /// resolves them at render time so MessageRow can fall back to
    /// the theme's typed slot when an override is missing.
    var materialised: Theme {
        let bg = Color(hex: chatBackgroundHex) ?? Color(nsColor: .textBackgroundColor)
        let fg = Color(hex: chatForegroundHex) ?? .primary
        // Pad/truncate the palette to 8 entries so renderers can index
        // safely without bounds checks.
        var palette = nickPaletteHex.compactMap { Color(hex: $0) }
        let fallback: [Color] = [.pink, .teal, .indigo, .mint, .orange, .cyan, .brown, .purple]
        if palette.count < 8 { palette.append(contentsOf: fallback.suffix(8 - palette.count)) }
        if palette.count > 8 { palette = Array(palette.prefix(8)) }

        return Theme(
            id: id.uuidString,
            displayName: name,
            chatBackground: bg,
            chatForeground: fg,
            ownNickColor:   Color(hex: ownNickColorHex)   ?? .accentColor,
            infoColor:      Color(hex: infoColorHex)      ?? .secondary,
            errorColor:     Color(hex: errorColorHex)     ?? .red,
            motdColor:      Color(hex: motdColorHex)      ?? .secondary,
            noticeColor:    Color(hex: noticeColorHex)    ?? .purple,
            actionColor:    Color(hex: actionColorHex)    ?? .purple,
            joinColor:      Color(hex: joinColorHex)      ?? .green,
            partColor:      Color(hex: partColorHex)      ?? .orange,
            nickNickColor:  Color(hex: nickNickColorHex)  ?? .blue,
            mentionBackground:   Color(hex: mentionBackgroundHex)   ?? .orange.opacity(0.18),
            watchlistBackground: Color(hex: watchlistBackgroundHex) ?? .purple.opacity(0.12),
            findBackground:      Color(hex: findBackgroundHex)      ?? .yellow.opacity(0.30),
            nickPalette: palette
        )
    }

    /// Per-event color overrides as a `[ChatLineKindTag: Color]` dict —
    /// the on-disk `[String: String]` parsed into typed Colors. Used
    /// by `ChatModel.kindColor(for:)` to resolve overrides at render
    /// time. Values that fail to parse are silently dropped (so a
    /// hand-edited corrupt entry doesn't break rendering).
    var kindOverridesMaterialised: [ChatLineKindTag: Color] {
        var out: [ChatLineKindTag: Color] = [:]
        for (k, v) in kindOverrideHex {
            if let tag = ChatLineKindTag(rawValue: k), let c = Color(hex: v) {
                out[tag] = c
            }
        }
        return out
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

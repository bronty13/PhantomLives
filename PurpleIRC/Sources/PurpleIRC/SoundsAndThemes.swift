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
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mention:        return "Own-nick mention"
        case .watchlistHit:   return "Watchlist hit"
        case .connect:        return "Connected"
        case .disconnect:     return "Disconnected"
        case .ctcp:           return "CTCP request"
        case .privateMessage: return "Private message"
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

    static let all: [Theme] = [.classic, .midnight, .candy]

    static func named(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? .classic
    }
}

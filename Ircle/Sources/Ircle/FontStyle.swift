import Foundation
import SwiftUI
import AppKit

/// Per-element font configuration for **Modern mode** themes. A `ModernTheme`
/// carries one `FontStyle` per `FontSlot`; in the classic (retro) look these are
/// never consulted — the palette falls back to Monaco/Geneva exactly as before.
///
/// Empty / zero / `.inherit` sentinels mean "inherit from the parent slot", so a
/// theme that only customises, say, the timestamp font leaves everything else on
/// the message-body root. Resolution chain:
///
///   nick / timestamp / systemLine → messageBody root (Monaco @ base size)
///   chrome → its own root (Geneva @ 11)
struct FontStyle: Codable, Equatable, Hashable {
    /// Family name. Empty string = inherit. Any installed font family name
    /// (NSFont resolves family or PostScript names), or "system-mono" /
    /// "system-proportional" built-in tokens.
    var family: String = ""

    /// Point size. 0 = inherit.
    var size: Double = 0

    /// Weight. `.inherit` = inherit from parent.
    var weight: Weight = .inherit

    /// Italic. nil = inherit.
    var italic: Bool? = nil

    /// Programmer-font ligature toggle. nil = inherit. Off by default at the
    /// root because IRC bodies contain sequences (->, !=, ==) that ligature
    /// substitution loves to mangle.
    var ligatures: Bool? = nil

    /// Letter-spacing in points. nil = inherit. 0 = no extra spacing.
    var tracking: Double? = nil

    enum Weight: String, Codable, CaseIterable, Identifiable {
        case inherit, light, regular, medium, semibold, bold
        var id: String { rawValue }

        var swiftUI: Font.Weight? {
            switch self {
            case .inherit:  return nil
            case .light:    return .light
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            case .bold:     return .bold
            }
        }

        var displayName: String {
            switch self {
            case .inherit:  return "Inherit"
            case .light:    return "Light"
            case .regular:  return "Regular"
            case .medium:   return "Medium"
            case .semibold: return "Semibold"
            case .bold:     return "Bold"
            }
        }
    }

    static let inherit = FontStyle()
}

/// Materialised font configuration after walking the inheritance chain. Carries
/// every value a view needs in concrete form.
struct ResolvedFont: Equatable {
    var family: String          // installed family name or built-in token
    var size: CGFloat
    var weight: Font.Weight
    var italic: Bool
    var ligaturesEnabled: Bool
    var tracking: CGFloat

    /// SwiftUI `Font` honouring family / size / weight / italic. Tracking and
    /// ligatures are applied at the view/run level, not on the `Font`.
    var swiftUIFont: Font {
        var base: Font
        switch family {
        case "system-mono":         base = .system(size: size, design: .monospaced)
        case "system-proportional": base = .system(size: size)
        default:                    base = .custom(family, size: size)
        }
        base = base.weight(weight)
        return italic ? base.italic() : base
    }
}

/// Per-element font slots a Modern theme can style independently.
enum FontSlot: String, Codable, CaseIterable, Identifiable {
    case messageBody   // body of PRIVMSG / NOTICE / ACTION
    case nick          // <nick> prefix in the message area
    case timestamp     // leading HH:mm column
    case systemLine    // join / part / quit / topic / server lines
    case chrome        // channelbar / nick list / status UI labels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .messageBody: return "Message body"
        case .nick:        return "Nicknames"
        case .timestamp:   return "Timestamps"
        case .systemLine:  return "System lines"
        case .chrome:      return "Interface (chrome)"
        }
    }

    /// Slots that inherit from `messageBody`; `messageBody` and `chrome` are
    /// roots with their own classic-font fallbacks.
    var isRoot: Bool { self == .messageBody || self == .chrome }
}

extension FontStyle {
    /// Walk the inheritance chain against an already-resolved parent slot.
    func resolved(parent: ResolvedFont) -> ResolvedFont {
        ResolvedFont(
            family: family.isEmpty ? parent.family : family,
            size: size > 0 ? CGFloat(size) : parent.size,
            weight: weight.swiftUI ?? parent.weight,
            italic: italic ?? parent.italic,
            ligaturesEnabled: ligatures ?? parent.ligaturesEnabled,
            tracking: tracking.map { CGFloat($0) } ?? parent.tracking
        )
    }

    /// Resolve a root slot (`messageBody` or `chrome`) against the classic
    /// fallback (Monaco for the body, Geneva for chrome). Any set field on the
    /// style overrides the classic default.
    func resolvedRoot(classicFamily: String, classicSize: Double) -> ResolvedFont {
        ResolvedFont(
            family: family.isEmpty ? classicFamily : family,
            size: size > 0 ? CGFloat(size) : CGFloat(classicSize),
            weight: weight.swiftUI ?? .regular,
            italic: italic ?? false,
            ligaturesEnabled: ligatures ?? false,
            tracking: tracking.map { CGFloat($0) } ?? 0
        )
    }
}

/// Convenience modifier: apply a `ResolvedFont` (font + tracking) to a `Text`.
extension View {
    func ircleFont(_ rf: ResolvedFont) -> some View {
        self.font(rf.swiftUIFont).tracking(rf.tracking)
    }
}

// MARK: - Installed-font discovery (for the Modern-mode font picker)

/// Cached snapshot of the user's installed font families. NSFontManager returns
/// ~500 on a typical Mac; fetched once on first use.
enum InstalledFonts {
    static let allFamilyNames: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    /// Families that respond to a monospaced trait — the natural candidates for
    /// the chat body. The picker can lead with these.
    static let monospacedFamilyNames: [String] = {
        let manager = NSFontManager.shared
        return allFamilyNames.filter { name in
            guard let f = NSFont(name: name, size: 12) else { return false }
            return manager.traits(of: f).contains(.fixedPitchFontMask)
        }
    }()
}

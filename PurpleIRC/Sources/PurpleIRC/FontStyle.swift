import Foundation
import SwiftUI
import AppKit

/// Per-element font configuration. Stored on `AppSettings` for chat body,
/// nick column, timestamp column, and system-line rows so each can be
/// styled independently. Empty / zero / `.inherit` sentinels mean "fall
/// back to the chat-body root configuration" so old `settings.json`
/// files (which only have `chatFontFamily` + `chatFontSize` +
/// `boldChatText`) continue to render unchanged.
///
/// Resolution chain:
///   nick / timestamp / system → chat body slot → enum + size root.
struct FontStyle: Codable, Equatable, Hashable {
    /// Family name. Empty string = inherit. May be a built-in token
    /// ("system-mono", "system-proportional") or any installed font's
    /// PostScript / family name (NSFont can resolve either).
    var family: String = ""

    /// Point size. 0 = inherit.
    var size: Double = 0

    /// Weight. `.inherit` = inherit. Stored as a string so we don't
    /// have to migrate the Codable surface every time SwiftUI adds a
    /// weight; only known values are honoured at resolve time.
    var weight: Weight = .inherit

    /// Italic. nil = inherit (the chat-body slot's italic wins; if even
    /// that's nil, treat as off).
    var italic: Bool? = nil

    /// Programmer-font ligature toggle. nil = inherit. Off by default
    /// at the root because IRC nicks contain characters (->, !=, ==)
    /// that ligature triggers love to mangle.
    var ligatures: Bool? = nil

    /// Letter-spacing in points. nil = inherit. 0 (after resolution)
    /// means "no extra spacing"; positive values widen, negative
    /// tighten.
    var tracking: Double? = nil

    /// Line-height multiplier on top of the font's natural leading.
    /// nil = inherit. 1.0 (after resolution) means "native"; values
    /// greater than 1 add space.
    var lineHeightMultiple: Double? = nil

    enum Weight: String, Codable, CaseIterable {
        case inherit, ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

        var swiftUI: Font.Weight? {
            switch self {
            case .inherit:    return nil
            case .ultraLight: return .ultraLight
            case .thin:       return .thin
            case .light:      return .light
            case .regular:    return .regular
            case .medium:     return .medium
            case .semibold:   return .semibold
            case .bold:       return .bold
            case .heavy:      return .heavy
            case .black:      return .black
            }
        }

        /// Human-readable label for picker menus.
        var displayName: String {
            switch self {
            case .inherit:    return "Inherit"
            case .ultraLight: return "Ultralight"
            case .thin:       return "Thin"
            case .light:      return "Light"
            case .regular:    return "Regular"
            case .medium:     return "Medium"
            case .semibold:   return "Semibold"
            case .bold:       return "Bold"
            case .heavy:      return "Heavy"
            case .black:      return "Black"
            }
        }
    }

    static let inherit = FontStyle()
}

/// Materialised font configuration after walking the inheritance chain.
/// Carries every value the renderer needs in concrete form so a Text
/// view can apply them without further branching.
struct ResolvedFont {
    let family: String              // built-in token or font name
    let size: CGFloat
    let weight: Font.Weight
    let italic: Bool
    let ligaturesEnabled: Bool
    let tracking: CGFloat
    let lineHeightMultiple: CGFloat
    let isBuiltInMonoToken: Bool    // true for "system-mono"
    let isBuiltInPropToken: Bool    // true for "system-proportional"

    /// SwiftUI `Font` honouring family / size / weight / italic. Tracking
    /// and lineHeight are applied via View modifiers (`textStyle(_:)`),
    /// not on the Font itself.
    var swiftUIFont: Font {
        var base: Font
        if isBuiltInMonoToken {
            base = .system(size: size, design: .monospaced)
        } else if isBuiltInPropToken {
            base = .system(size: size)
        } else {
            base = .custom(family, size: size)
        }
        base = base.weight(weight)
        return italic ? base.italic() : base
    }
}

extension FontStyle {
    /// Walk the inheritance chain. `parent` is the chat-body slot for
    /// nick / timestamp / system lines, and the legacy chat-body
    /// fallback (built from `chatFontFamily` + `chatFontSize` etc.) for
    /// the chat-body slot itself.
    func resolved(parent: ResolvedFont) -> ResolvedFont {
        let resolvedFamily = family.isEmpty ? parent.family : family
        let resolvedSize: CGFloat = size > 0 ? CGFloat(size) : parent.size
        let resolvedWeight = weight.swiftUI ?? parent.weight
        let resolvedItalic = italic ?? parent.italic
        let resolvedLig = ligatures ?? parent.ligaturesEnabled
        let resolvedTracking: CGFloat = tracking.map { CGFloat($0) } ?? parent.tracking
        let resolvedLine: CGFloat = lineHeightMultiple.map { CGFloat($0) } ?? parent.lineHeightMultiple
        return ResolvedFont(
            family: resolvedFamily,
            size: resolvedSize,
            weight: resolvedWeight,
            italic: resolvedItalic,
            ligaturesEnabled: resolvedLig,
            tracking: resolvedTracking,
            lineHeightMultiple: resolvedLine,
            isBuiltInMonoToken: resolvedFamily == "system-mono",
            isBuiltInPropToken: resolvedFamily == "system-proportional"
        )
    }

    /// Build the ROOT chat-body resolution from the legacy enum + size
    /// settings. Any FontStyle field overrides what comes from the
    /// legacy fields. Used by `ChatModel.font(for: .chatBody)`.
    static func resolveChatBody(legacy enumFamily: ChatFontFamily,
                                legacySize: Double,
                                legacyBold: Bool,
                                style: FontStyle) -> ResolvedFont {
        let legacyFamily: String = {
            switch enumFamily {
            case .systemMono:    return "system-mono"
            case .sfMono:        return "SF Mono"
            case .menlo:         return "Menlo"
            case .monaco:        return "Monaco"
            case .courier:       return "Courier New"
            case .proportional:  return "system-proportional"
            }
        }()
        let resolvedFamily = style.family.isEmpty ? legacyFamily : style.family
        let resolvedSize: CGFloat = style.size > 0 ? CGFloat(style.size) : CGFloat(legacySize)
        let baseWeight: Font.Weight = legacyBold ? .bold : .regular
        let resolvedWeight = style.weight.swiftUI ?? baseWeight
        let resolvedItalic = style.italic ?? false
        let resolvedLig = style.ligatures ?? false
        let resolvedTracking: CGFloat = style.tracking.map { CGFloat($0) } ?? 0
        let resolvedLine: CGFloat = style.lineHeightMultiple.map { CGFloat($0) } ?? 1.0
        return ResolvedFont(
            family: resolvedFamily,
            size: resolvedSize,
            weight: resolvedWeight,
            italic: resolvedItalic,
            ligaturesEnabled: resolvedLig,
            tracking: resolvedTracking,
            lineHeightMultiple: resolvedLine,
            isBuiltInMonoToken: resolvedFamily == "system-mono",
            isBuiltInPropToken: resolvedFamily == "system-proportional"
        )
    }
}

/// Per-element font slots. The four slots renderer-side code reads
/// instead of poking AppSettings directly. Adding a new slot is one
/// case here + one stored property on AppSettings + one branch in
/// `ChatModel.font(for:)`.
enum FontSlot {
    case chatBody    // body of PRIVMSG / NOTICE / ACTION / etc.
    case nick        // <nick> column
    case timestamp   // leading [HH:mm:ss]
    case systemLine  // join / part / quit / nick / topic / info / error
}

/// Convenience modifier that applies a `ResolvedFont` to a Text view —
/// font + tracking + line-spacing in one call. Use when the call site
/// already has a `ResolvedFont` (e.g. via `model.font(for: .chatBody)`).
///
/// Ligatures: SwiftUI's `Text` doesn't expose a ligature toggle on
/// macOS. We render the text via `AttributedString` with the
/// `NSAttributedString.Key.ligature` attribute when the resolved font
/// asks for ligatures off (`0`); a non-empty value (1) keeps the
/// font's default behaviour. Only applies to the chat body where we
/// have full control of the text run; nick / timestamp / system slots
/// inherit standard rendering.
extension View {
    func purpleFont(_ rf: ResolvedFont) -> some View {
        self.font(rf.swiftUIFont)
            .tracking(rf.tracking)
            .lineSpacing(max(0, (rf.lineHeightMultiple - 1.0) * rf.size))
    }
}

/// A `Text` factory that respects the resolved ligature toggle. SwiftUI's
/// `Text` doesn't take a ligature attribute on macOS, so when ligatures
/// are forced off we wrap the string in an `AttributedString` carrying
/// the `.ligature = 0` attribute. Caller still applies `.purpleFont(rf)`
/// to inherit family + size + tracking + line-spacing.
@MainActor
func purpleText(_ s: String, _ rf: ResolvedFont) -> Text {
    if rf.ligaturesEnabled {
        // Default behaviour — SwiftUI Text with the resolved font.
        return Text(s)
    }
    var attr = AttributedString(s)
    attr.attributedStringRepresentation = NSAttributedString(
        string: s,
        attributes: [.ligature: 0]
    )
    return Text(attr)
}

private extension AttributedString {
    /// Replace this AttributedString's contents with the runs from an
    /// NSAttributedString. Helper so `purpleText` can mint a SwiftUI
    /// Text from an NSAttributedString without the long
    /// `AttributedString(NSAttributedString)` initialiser dance.
    var attributedStringRepresentation: NSAttributedString {
        get { NSAttributedString(self) }
        set {
            if let converted = try? AttributedString(newValue, including: \.appKit) {
                self = converted
            }
        }
    }
}

// MARK: - Installed-font discovery

/// Cached snapshot of the user's installed font families (NSFontManager
/// returns ~500 on a typical Mac; querying once per render is wasteful).
/// The list is fetched lazily on first use; macOS doesn't change it
/// frequently enough to justify a refresh hook.
enum InstalledFonts {
    static let allFamilyNames: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    /// Subset that responds to a monospaced trait. Useful for the picker
    /// to lead with the most likely candidates for chat fonts.
    static let monospacedFamilyNames: [String] = {
        let manager = NSFontManager.shared
        return allFamilyNames.filter { name in
            // Probe the family at 12pt; the trait is intrinsic to the
            // family, not a size, so the chosen size doesn't matter.
            guard let f = NSFont(name: name, size: 12) else { return false }
            return manager.traits(of: f).contains(.fixedPitchFontMask)
        }
    }()
}

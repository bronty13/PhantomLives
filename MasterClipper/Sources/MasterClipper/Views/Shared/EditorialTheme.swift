import SwiftUI

// MARK: - Palette

enum EdColor {
    static let bone     = Color(red: 0xf1/255, green: 0xed/255, blue: 0xe4/255)
    static let ink      = Color(red: 0x14/255, green: 0x11/255, blue: 0x0d/255)
    static let acid     = Color(red: 0xdc/255, green: 0xff/255, blue: 0x37/255)
    static let inkOnBoneTint = Color(red: 0x14/255, green: 0x11/255, blue: 0x0d/255).opacity(0.06)

    static func ink(_ alpha: Double) -> Color { ink.opacity(alpha) }
}

// MARK: - Typography

enum EdFont {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let name: String
        switch (weight, italic) {
        case (.ultraLight, false), (.thin, false), (.light, false): name = "Source Serif 4 Light"
        case (.ultraLight, true),  (.thin, true),  (.light, true):  name = "Source Serif 4 Light Italic"
        case (.regular, false):                                     name = "Source Serif 4"
        case (.regular, true):                                      name = "Source Serif 4 Italic"
        case (.medium, false), (.semibold, false):                  name = "Source Serif 4 Semibold"
        case (.medium, true),  (.semibold, true):                   name = "Source Serif 4 Italic"
        case (.bold, false), (.heavy, false), (.black, false):      name = "Source Serif 4 Bold"
        case (.bold, true),  (.heavy, true),  (.black, true):       name = "Source Serif 4 Italic"
        default:                                                    name = "Source Serif 4"
        }
        return .custom(name, size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(italic ? "Inter Tight Italic" : "Inter Tight", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:                                               name = "JetBrains Mono Medium"
        case .semibold, .bold, .heavy, .black:                      name = "JetBrains Mono SemiBold"
        default:                                                    name = "JetBrains Mono"
        }
        return .custom(name, size: size)
    }
}

// MARK: - Eyebrow / micro-type

struct EdEyebrow: View {
    let text: String
    var withRule: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.uppercased())
                .font(EdFont.mono(10.5))
                .tracking(1.4)
                .foregroundStyle(EdColor.ink(0.55))
            if withRule {
                Rectangle().fill(EdColor.ink(0.18)).frame(height: 1)
            }
        }
    }
}

struct EdByline: View {
    let text: String
    var body: some View {
        Text(text)
            .font(EdFont.mono(10.5))
            .tracking(0.4)
            .foregroundStyle(EdColor.ink(0.55))
    }
}

// MARK: - Headline / deck

struct EdHeadline: View {
    let text: String
    var emphasized: String? = nil
    var size: CGFloat = 44
    var body: some View {
        // Source Serif 4 Bold, very tight leading, em words highlighted with acid underline.
        let attr: AttributedString = {
            var s = AttributedString(text)
            s.font = EdFont.serif(size, weight: .bold)
            s.kern = -size * 0.02
            if let em = emphasized, let r = s.range(of: em) {
                s[r].font = EdFont.serif(size, weight: .regular, italic: true)
                s[r].backgroundColor = EdColor.acid
                s[r].foregroundColor = EdColor.ink
            }
            return s
        }()
        Text(attr)
            .lineSpacing(-size * 0.05)
            .foregroundStyle(EdColor.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EdDeck: View {
    let text: String
    var body: some View {
        Text(text)
            .font(EdFont.serif(17, weight: .light, italic: true))
            .foregroundStyle(EdColor.ink(0.7))
            .lineSpacing(2.5)
            .frame(maxWidth: 340, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Section heading (used at the top of a panel)

struct EdSectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(EdFont.serif(22, weight: .semibold))
                    .foregroundStyle(EdColor.ink)
                Spacer()
                if let trailing {
                    Text(trailing.uppercased())
                        .font(EdFont.mono(10.5))
                        .tracking(0.84)
                        .foregroundStyle(EdColor.ink(0.55))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            Rectangle().fill(EdColor.ink).frame(height: 1)
        }
    }
}

// MARK: - Status pill

enum EdStatus: String {
    case new, editing, toPost, posting, live, offline

    var label: String {
        switch self {
        case .new:     return "NEW"
        case .editing: return "EDITING"
        case .toPost:  return "TO POST"
        case .posting: return "POSTING"
        case .live:    return "LIVE"
        case .offline: return "OFFLINE"
        }
    }
}

struct EdStatusPill: View {
    let status: EdStatus
    var labelOverride: String? = nil

    var body: some View {
        let label = labelOverride ?? status.label
        Text(label.uppercased())
            .font(EdFont.mono(10.5, weight: .semibold))
            .tracking(0.84)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(border)
            .fixedSize()
    }

    private var fg: Color {
        switch status {
        case .live:                    return EdColor.acid
        case .posting:                 return EdColor.ink
        case .toPost:                  return EdColor.ink
        case .editing:                 return EdColor.ink(0.85)
        case .new:                     return EdColor.ink(0.55)
        case .offline:                 return EdColor.ink(0.55)
        }
    }
    private var bg: some View {
        Group {
            switch status {
            case .live:    EdColor.ink
            case .posting: EdColor.acid
            default:       Color.clear
            }
        }
    }
    @ViewBuilder private var border: some View {
        switch status {
        case .new, .offline:
            Rectangle().strokeBorder(style: .init(lineWidth: 1, dash: [3, 3])).foregroundStyle(EdColor.ink(0.35))
        case .editing:
            Rectangle().strokeBorder(EdColor.ink(0.45), lineWidth: 1)
        default:
            Rectangle().strokeBorder(EdColor.ink, lineWidth: 1)
        }
    }
}

// MARK: - Site cell (the 22×22 site marker grid)

struct EdSiteCell: View {
    let code: String
    let posted: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(posted ? EdColor.ink : Color.clear)
                .overlay(Rectangle().strokeBorder(posted ? EdColor.ink : EdColor.ink(0.4), lineWidth: 1))
            Text(posted ? "×" : String(code.prefix(1)))
                .font(EdFont.mono(9.5, weight: .semibold))
                .foregroundStyle(posted ? EdColor.acid : EdColor.ink(0.45))
        }
        .frame(width: 22, height: 22)
        .help(posted ? "Posted to \(code)" : "Not posted to \(code)")
    }
}

// MARK: - Buttons

struct EdAcidPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EdFont.mono(11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(EdColor.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(EdColor.acid)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct EdInkPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EdFont.mono(11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(EdColor.acid)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(EdColor.ink)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct EdGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EdFont.sans(13, weight: .medium))
            .foregroundStyle(EdColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? EdColor.ink(0.06) : Color.clear)
            .overlay(Rectangle().strokeBorder(EdColor.ink, lineWidth: 1))
    }
}

// MARK: - Hairline rule

struct EdHairline: View {
    var color: Color = EdColor.ink
    var horizontal: Bool = true
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : nil)
    }
}

// MARK: - Root chrome modifier

struct EdRootBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EdColor.bone)
            .foregroundStyle(EdColor.ink)
            .font(EdFont.sans(13.5))
            .tint(EdColor.ink)
    }
}

extension View {
    /// Apply the editorial bone background + ink foreground + Inter Tight base font.
    func editorialChrome() -> some View { modifier(EdRootBackground()) }
}

// MARK: - Container card (a hairline-bordered panel)

struct EdPanel<Content: View>: View {
    var border: Color = EdColor.ink
    var background: Color = EdColor.bone
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(background)
            .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
    }
}

// MARK: - Number cell (used in the dashboard num strip)

struct EdNumberCell: View {
    let label: String
    let figure: String
    let hint: String?
    var accent: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(EdFont.mono(10.5))
                .tracking(1.4)
                .foregroundStyle(accent ? EdColor.ink(0.7) : EdColor.ink(0.6))
            Text(figure)
                .font(EdFont.serif(84, weight: .bold))
                .tracking(-2.9)
                .foregroundStyle(EdColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let hint {
                Text(hint)
                    .font(EdFont.mono(11))
                    .foregroundStyle(EdColor.ink(0.6))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent ? EdColor.acid : Color.clear)
    }
}

// MARK: - Page shell (masthead + body for every tab)

/// Editorial masthead used at the top of every section. Provides the
/// eyebrow → serif headline → italic deck rhythm and a hairline separator
/// between masthead and body.
struct EdPageShell<Content: View>: View {
    let eyebrow: String
    let headline: String
    var emphasized: String? = nil
    var deck: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    EdEyebrow(text: eyebrow, withRule: false)
                    EdHeadline(text: headline, emphasized: emphasized, size: 32)
                    if let deck { EdDeck(text: deck) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    trailing
                        .frame(alignment: .topTrailing)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 14)
            EdHairline()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EdColor.bone)
    }
}

// MARK: - Persona swatch

struct EdPersonaSwatch: View {
    let color: Color
    var size: CGFloat = 12
    var body: some View {
        Rectangle().fill(color).frame(width: size, height: size)
    }
}

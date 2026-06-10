import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme preview

/// One tile in the theme gallery. Renders a few stylised chat lines using
/// the theme's actual color knobs so the user can pick by eye instead of
/// having to apply each option to find out what it looks like. Click a
/// card to commit; the selected theme gets an accent ring + checkmark.
struct ThemePreviewCard: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(theme.displayName).font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            // Mini chat sample — uses real semantic colours from the theme.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("<alice>").foregroundStyle(theme.ownNickColor)
                    Text("hey, anyone tried Swift 6?").foregroundStyle(.primary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("<bob>").foregroundStyle(theme.nickPalette.first ?? .blue)
                    Text("just yesterday").foregroundStyle(.primary)
                }
                Text("* alice waves").foregroundStyle(theme.actionColor).italic()
                Text("→ carol joined").foregroundStyle(theme.joinColor)
                Text("-NickServ- you are now identified")
                    .foregroundStyle(theme.noticeColor)
            }
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Use the theme's own chat background so cards visibly differ —
            // cream for Solarized Light, deep navy for Tokyo Night, etc.
            .background(theme.chatBackground)
            .foregroundStyle(theme.chatForeground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            // Palette strip — quick read on the per-nick colours that
            // would land in this theme.
            HStack(spacing: 3) {
                ForEach(0..<min(theme.nickPalette.count, 8), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.nickPalette[i])
                        .frame(height: 6)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2 : 0.5)
        )
    }
}

// MARK: - Appearance

/// Theme picker + chat font controls. Lives in its own tab so the user
/// can find visual customisation without hunting through Behavior.
/// Themes are grouped into Light / Adaptive / Dark sections so the gallery
/// reads like a proper picker instead of a wall of cards.
struct AppearanceSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Time display") {
                Picker("Timestamp format", selection: $settings.settings.timestampFormat) {
                    ForEach(TimestampFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                    if !TimestampFormat.allCases.contains(where: { $0.rawValue == settings.settings.timestampFormat }) {
                        Text("Custom: \(settings.settings.timestampFormat)")
                            .tag(settings.settings.timestampFormat)
                    }
                }
                Text("Live preview — change applies immediately to every chat buffer. /timestamp on|off|<pattern> works as a slash command too.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Density") {
                Picker("Chat row density", selection: $settings.settings.chatDensity) {
                    ForEach(ChatDensity.allCases) { d in
                        Text(d.displayName).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                Text("Vertical breathing room between chat rows. /density compact|cozy|comfortable also works.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Reading aids") {
                Toggle("Relaxed row spacing (accessibility)", isOn: $settings.settings.relaxedRowSpacing)
                Toggle("Collapse runs of join / part / quit lines",
                       isOn: $settings.settings.collapseJoinPart)
                Text("Each toggle applies immediately.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Where to find moved settings") {
                Text("• Theme grid → **Themes** tab")
                Text("• Font family / size / weight / bold → **Fonts** tab")
                Text("• Sounds + alert channels → **Notifications & Sounds** tab")
            }
            .font(.caption)
        }
        .formStyle(.grouped)
    }
}


import SwiftUI
import AppKit
import PurpleMarkRenderCore

// MARK: - Color ⇄ hex

extension Color {
    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { self = .gray; return }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

func hexString(from color: Color) -> String {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
    let r = Int((ns.redComponent * 255).rounded())
    let g = Int((ns.greenComponent * 255).rounded())
    let b = Int((ns.blueComponent * 255).rounded())
    return String(format: "#%02x%02x%02x", r, g, b)
}

// MARK: - Swatch (theme picker card)

struct ThemeSwatch: View {
    let name: String
    let colors: ThemeColors
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hexString: colors.background))
                    .frame(width: 80, height: 52)
                    .overlay(
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color(hexString: colors.link)).frame(width: 36, height: 4)
                            Capsule().fill(Color(hexString: colors.foreground)).frame(width: 48, height: 3)
                            Capsule().fill(Color(hexString: colors.muted)).frame(width: 30, height: 3)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.15),
                                          lineWidth: selected ? 2 : 1))
                Text(name).font(.caption2).lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor sheet

/// An edit session for a custom theme (new or existing).
struct ThemeEditSession: Identifiable {
    let id = UUID()
    var theme: CustomTheme
    var isNew: Bool
}

struct ThemeEditorView: View {
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State var session: ThemeEditSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.isNew ? "New Custom Theme" : "Edit Theme").font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        TextField("Name", text: $session.theme.name)
                        Toggle("Dark theme", isOn: $session.theme.colors.isDark)
                    }
                    Section("Colors") {
                        colorRow("Background", \.background)
                        colorRow("Text", \.foreground)
                        colorRow("Muted text", \.muted)
                        colorRow("Links", \.link)
                        colorRow("Rules / borders", \.rule)
                        colorRow("Strong rule (quote bar)", \.ruleStrong)
                        colorRow("Inline code background", \.codeBackground)
                        colorRow("Code block background", \.preBackground)
                        colorRow("Table stripe", \.stripe)
                    }
                }
                .formStyle(.grouped)
                .frame(width: 320)

                Divider()
                ThemePreview(colors: session.theme.colors)
                    .frame(width: 300)
                    .padding()
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.theme.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 660, height: 540)
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<ThemeColors, String>) -> some View {
        ColorPicker(label, selection: Binding(
            get: { Color(hexString: session.theme.colors[keyPath: keyPath]) },
            set: { session.theme.colors[keyPath: keyPath] = hexString(from: $0) }),
            supportsOpacity: false)
    }

    private func save() {
        let trimmed = session.theme.name.trimmingCharacters(in: .whitespaces)
        var theme = session.theme
        theme.name = trimmed.isEmpty ? "Custom" : trimmed
        if session.isNew {
            let id = themes.addCustom(name: theme.name, colors: theme.colors)
            settings.themeRaw = id            // select the new theme
        } else {
            themes.updateCustom(theme.id, name: theme.name, colors: theme.colors)
        }
        dismiss()
    }
}

/// A lightweight, native preview of a theme (no web view) for the editor.
private struct ThemePreview: View {
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heading")
                .font(.title2.bold())
                .foregroundStyle(Color(hexString: colors.foreground))
            Rectangle().fill(Color(hexString: colors.rule)).frame(height: 1)
            Text("Body text with a ")
                .foregroundStyle(Color(hexString: colors.foreground))
            + Text("link").foregroundStyle(Color(hexString: colors.link))
            + Text(" and ").foregroundStyle(Color(hexString: colors.foreground))
            Text("inline code")
                .font(.callout.monospaced())
                .foregroundStyle(Color(hexString: colors.foreground))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color(hexString: colors.codeBackground), in: RoundedRectangle(cornerRadius: 5))
            Text("Muted caption")
                .font(.caption)
                .foregroundStyle(Color(hexString: colors.muted))
            HStack(spacing: 0) {
                Rectangle().fill(Color(hexString: colors.ruleStrong)).frame(width: 3)
                Text("A blockquote")
                    .foregroundStyle(Color(hexString: colors.muted))
                    .padding(.leading, 8)
            }
            VStack(spacing: 0) {
                Text("Code block")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(hexString: colors.foreground))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(hexString: colors.preBackground), in: RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hexString: colors.background))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

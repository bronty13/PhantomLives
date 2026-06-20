import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The **Themes** tab — the Modern-mode home: the toggle, the built-in gallery,
/// and the user's custom-theme library (create / duplicate / edit / delete /
/// import). All colour + font + flat editing happens in `ThemeBuilderView`.
struct ModernSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    /// The theme currently open in the editor sheet (nil = closed).
    @State private var editing: ModernTheme? = nil

    private var enabled: Bool { settingsStore.settings.modernModeEnabled }
    private var activeID: String { settingsStore.settings.modernThemeID }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Modern mode", isOn: $settingsStore.settings.modernModeEnabled)
                Text("Off keeps the classic Ircle look exactly as it is. On lets you pick a theme, customise fonts and colours, and unlocks future modern features.")
                    .font(.caption).foregroundColor(.secondary)
            }

            if enabled {
                builtInSection(title: "Dark themes", themes: ModernTheme.all.filter { $0.isDark })
                builtInSection(title: "Light themes", themes: ModernTheme.all.filter { !$0.isDark })
                myThemesSection
            } else {
                Section {
                    Text("Turn on Modern mode to browse \(ModernTheme.all.count) built-in themes and build your own.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { theme in
            ThemeBuilderView(draft: theme).environmentObject(settingsStore)
        }
    }

    // MARK: Built-in gallery

    private func builtInSection(title: String, themes: [ModernTheme]) -> some View {
        Section(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 152), spacing: 10)], spacing: 10) {
                ForEach(themes) { theme in
                    ThemePreviewCard(theme: theme, isActive: theme.id == activeID)
                        .onTapGesture { settingsStore.settings.modernThemeID = theme.id }
                        .contextMenu {
                            Button("Use") { settingsStore.settings.modernThemeID = theme.id }
                            Button("Duplicate & Edit…") { duplicateAndEdit(theme) }
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: My themes

    private var myThemesSection: some View {
        Section("My themes") {
            if settingsStore.settings.userThemes.isEmpty {
                Text("No custom themes yet. Duplicate a built-in, or start from the current theme.")
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach(settingsStore.settings.userThemes) { theme in
                HStack(spacing: 10) {
                    ThemeSwatch(theme: theme).frame(width: 40, height: 26)
                    Text(theme.name).lineLimit(1)
                    if theme.id == activeID {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    }
                    Spacer()
                    Button("Use") { settingsStore.settings.modernThemeID = theme.id }
                        .buttonStyle(.borderless)
                    Button("Edit…") { editing = theme }
                        .buttonStyle(.borderless)
                    Button("Duplicate") { duplicate(theme) }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) { delete(theme) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("New from current theme") { duplicateAndEdit(settingsStore.activeModernTheme) }
                Button("Import…") { importTheme() }
                Spacer()
            }
            Text("Themes export as a small .ircletheme file you can share with other Ircle users.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: Actions

    private func duplicateAndEdit(_ base: ModernTheme) {
        // Open the editor on a fresh copy; nothing is saved until the editor's
        // Save, so cancelling adds nothing.
        editing = ModernTheme.duplicate(of: base, name: uniqueName(base.name))
    }

    private func duplicate(_ theme: ModernTheme) {
        let copy = ModernTheme.duplicate(of: theme, name: uniqueName(theme.name))
        settingsStore.settings.userThemes.append(copy)
        settingsStore.settings.modernThemeID = copy.id
    }

    private func delete(_ theme: ModernTheme) {
        settingsStore.settings.userThemes.removeAll { $0.id == theme.id }
        if activeID == theme.id {
            settingsStore.settings.modernThemeID = theme.basedOn ?? ModernTheme.defaultID
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "ircletheme") ?? .json]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let imported = ThemeImporter.importTheme(from: url, into: settingsStore) {
            settingsStore.settings.modernThemeID = imported.id
        } else {
            NSSound.beep()
        }
    }

    /// Disambiguate a duplicated name against the existing library.
    private func uniqueName(_ base: String) -> String {
        let existing = Set(settingsStore.settings.userThemes.map(\.name))
        if !existing.contains(base) && ModernTheme.named(base) == nil { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

// MARK: - Cards

/// A gallery tile previewing a built-in theme with a mock chat snippet.
struct ThemePreviewCard: View {
    let theme: ModernTheme
    let isActive: Bool

    var body: some View {
        let p = theme.palette()
        VStack(alignment: .leading, spacing: 0) {
            // Mock channel header
            HStack {
                Text(theme.name).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.chromeText).lineLimit(1)
                Spacer()
                if !theme.flatChrome {
                    Text("3D").font(.system(size: 8, weight: .bold)).foregroundColor(p.timestamp)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(p.paneBG)
            // Mock messages
            VStack(alignment: .leading, spacing: 1) {
                line(p.ownNick, "<you> hi there", p)
                line(p.otherNick, "<friend> hello!", p)
                line(p.joinText, "*** sam joined", p)
                line(p.actionText, "* you waves", p)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(p.textBG)
        }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isActive ? Color.accentColor : p.hairline,
                          lineWidth: isActive ? 2.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func line(_ color: Color, _ text: String, _ p: PlatinumPalette) -> some View {
        Text(text).font(.custom(p.messageFontName == "system-mono" ? "Menlo" : p.messageFontName, size: 9))
            .foregroundColor(color).lineLimit(1)
    }
}

/// A tiny two-tone swatch for the "My themes" list rows.
struct ThemeSwatch: View {
    let theme: ModernTheme
    var body: some View {
        let p = theme.palette()
        HStack(spacing: 0) {
            p.paneBG
            VStack(spacing: 1) {
                p.ownNick.frame(height: 3)
                p.joinText.frame(height: 3)
                p.actionText.frame(height: 3)
            }
            .padding(2)
            .frame(maxWidth: .infinity)
            .background(p.textBG)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

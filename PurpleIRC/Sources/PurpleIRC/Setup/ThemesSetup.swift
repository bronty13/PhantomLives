import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Themes

/// Theme grid + WYSIWYG builder launchpad. The grid renders built-in
/// themes (grouped light / adaptive / dark) AND user themes (with
/// edit + delete affordances). New / Edit / Duplicate route to
/// ThemeBuilderView.
struct ThemesSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var builderDraft: UserTheme? = nil
    @State private var builderIsNew: Bool = false

    private static let adaptiveIDs: Set<String> = ["classic", "highContrast"]

    private var lightThemes: [Theme] {
        Theme.all.filter { !Self.adaptiveIDs.contains($0.id) && $0.isLightish }
    }
    private var darkThemes: [Theme] {
        Theme.all.filter { !Self.adaptiveIDs.contains($0.id) && !$0.isLightish }
    }
    private var adaptiveThemes: [Theme] {
        Theme.all.filter { Self.adaptiveIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section("Custom themes") {
                if settings.settings.userThemes.isEmpty {
                    Text("No custom themes yet. Click **+ New theme** to duplicate the currently-selected theme as a starting point, or **Import…** to load a `.purpletheme` file someone shared.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(settings.settings.userThemes) { user in
                        userThemeRow(user)
                    }
                }
                HStack {
                    Button {
                        startNewFromActive()
                    } label: {
                        Label("New theme", systemImage: "plus.square.on.square")
                    }
                    Button {
                        importThemeFile()
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            Section("Light themes")    { themeGrid(lightThemes) }
            Section("Adaptive (follows macOS appearance)") { themeGrid(adaptiveThemes) }
            Section("Dark themes")     { themeGrid(darkThemes) }
        }
        .formStyle(.grouped)
        .sheet(item: $builderDraft) { draft in
            ThemeBuilderView(
                settings: settings,
                draft: draft,
                isNew: builderIsNew
            )
        }
    }

    @ViewBuilder
    private func userThemeRow(_ user: UserTheme) -> some View {
        HStack(spacing: 10) {
            // Tiny preview swatch — chat background + foreground tile.
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: user.chatBackgroundHex) ?? .gray)
                Text("Aa")
                    .foregroundStyle(Color(hex: user.chatForegroundHex) ?? .white)
                    .font(.caption.bold())
            }
            .frame(width: 44, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(user.id.uuidString == settings.settings.themeID
                            ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: user.id.uuidString == settings.settings.themeID ? 2 : 1)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(.body)
                if let basedOn = user.basedOn {
                    Text("Based on \(basedOn)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Use") {
                settings.settings.themeID = user.id.uuidString
            }
            .disabled(user.id.uuidString == settings.settings.themeID)
            Button {
                builderDraft = user
                builderIsNew = false
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit in the Theme Builder")
            .buttonStyle(.borderless)
            Button {
                duplicateUserTheme(user)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Duplicate")
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                deleteUserTheme(user)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func startNewFromActive() {
        // Resolve whatever's currently selected (built-in OR existing
        // user theme) and snapshot it as the starting point. Materialising
        // a user theme back through duplicate(of:) round-trips its
        // colors via Color, which can drift slightly on the OS color
        // pipeline — acceptable here since the user's editing it.
        let active = Theme.resolve(id: settings.settings.themeID,
                                    userThemes: settings.settings.userThemes)
        builderDraft = UserTheme.duplicate(of: active, name: "")
        builderIsNew = true
    }

    private func duplicateUserTheme(_ user: UserTheme) {
        var copy = user
        copy.id = UUID()
        copy.name = "\(user.name) copy"
        copy.createdAt = Date()
        settings.settings.userThemes.append(copy)
    }

    private func deleteUserTheme(_ user: UserTheme) {
        settings.settings.userThemes.removeAll { $0.id == user.id }
        if settings.settings.themeID == user.id.uuidString {
            settings.settings.themeID = user.basedOn ?? "classic"
        }
    }

    private func importThemeFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if let imported = ThemeImporter.importTheme(from: url, into: settings) {
                    settings.settings.themeID = imported.id.uuidString
                }
            }
        }
    }

    @ViewBuilder
    private func themeGrid(_ themes: [Theme]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10),
                      GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(themes) { theme in
                ThemePreviewCard(
                    theme: theme,
                    isSelected: theme.id == settings.settings.themeID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    settings.settings.themeID = theme.id
                }
            }
        }
    }
}


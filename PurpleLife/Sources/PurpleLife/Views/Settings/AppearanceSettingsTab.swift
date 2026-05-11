import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Appearance. Three controls: an appearance segment
/// (Auto / Light / Dark), a grid of theme cards, and the custom-themes
/// section (New / Import). Picking a theme or appearance rewrites
/// `appState.settings`, which fans out via `SettingsStore.save` and the
/// Combine bridge in `AppState` — the rest of the app re-renders to the
/// new palette without a relaunch.
///
/// The accessibility framing matters here: `PurpleTheme.highContrast`
/// is the entry point for users who need stronger separation between
/// surfaces and text, and the appearance segment guarantees Auto stays
/// available regardless of theme choice.
struct AppearanceSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    /// Theme builder sheet state. `nil` = closed; a non-nil value carries
    /// the draft to edit (either a fresh duplicate or an existing user
    /// theme). `isNew` controls Delete-button visibility in the sheet.
    @State private var builderTarget: BuilderTarget?

    /// Most-recent import error, shown inline below the Import button so
    /// it lands next to the action that produced it.
    @State private var importError: String?

    private struct BuilderTarget: Identifiable {
        let id = UUID()
        let draft: UserTheme
        let isNew: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appearanceSection
                themeSection
                customThemesSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $builderTarget) { target in
            ThemeBuilderView(draft: target.draft, isNew: target.isNew)
                .environmentObject(appState)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.headline)
            Picker("Appearance", selection: Binding(
                get: { appState.settings.appearance },
                set: { newValue in
                    var s = appState.settings
                    s.appearance = newValue
                    appState.settings = s
                }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Auto follows the macOS appearance setting. Light and Dark override it for PurpleLife only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Theme grid

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Theme")
                    .font(.headline)
                Spacer()
                Text("\(PurpleTheme.allBuiltIns.count) built-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12)], spacing: 12) {
                ForEach(PurpleTheme.allBuiltIns) { theme in
                    ThemeCard(
                        theme: theme,
                        isSelected: appState.settings.themeID == theme.id,
                        onExport: {
                            // Built-ins aren't UserThemes — synthesize a snapshot
                            // first so the receiver gets something they can edit.
                            // `basedOn` retained as metadata.
                            exportTheme(UserTheme.duplicate(of: theme, name: theme.displayName))
                        }
                    ) {
                        var s = appState.settings
                        s.themeID = theme.id
                        appState.settings = s
                    }
                }
                ForEach(appState.settings.userThemes) { user in
                    let theme = user.materialised
                    ThemeCard(
                        theme: theme,
                        isSelected: appState.settings.themeID == user.id.uuidString,
                        custom: true,
                        onEdit: { builderTarget = BuilderTarget(draft: user, isNew: false) },
                        onExport: { exportTheme(user) }
                    ) {
                        var s = appState.settings
                        s.themeID = user.id.uuidString
                        appState.settings = s
                    }
                }
            }
        }
    }

    // MARK: - Custom themes

    private var customThemesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Custom themes")
                    .font(.headline)
                Spacer()
                Button {
                    importTheme()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                Button {
                    let starting = activeThemeForDuplication
                    let draft = UserTheme.duplicate(of: starting, name: "Custom from \(starting.displayName)")
                    builderTarget = BuilderTarget(draft: draft, isNew: true)
                } label: {
                    Label("New theme", systemImage: "plus")
                }
            }
            Text("Start a new theme from the currently selected one, or import a `.purplelifetheme.json` file shared from another Mac. Right-click any theme above to export it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Pick a sane starting point for "+ New theme": the currently selected
    /// theme, materialised if it's a user theme. Falls back to Royal Purple
    /// when the active id doesn't resolve (e.g. a deleted user theme that's
    /// still selected — though `commitDelete` handles that case at delete
    /// time).
    private var activeThemeForDuplication: PurpleTheme {
        PurpleTheme.resolve(id: appState.settings.themeID, userThemes: appState.settings.userThemes)
    }

    // MARK: - Export / Import

    private func exportTheme(_ theme: UserTheme) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ThemeIO.defaultFilename(for: theme)
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.canCreateDirectories = true
        // `.purplelifetheme.json` ends in `.json`; the system content type
        // is the right anchor. We don't register a custom UTType yet —
        // doing so means a CFBundleDocumentTypes entry plus icon work that
        // isn't justified for a single-file export format.
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ThemeIO.write(theme, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("PurpleLife: theme export failed — \(error.localizedDescription)")
            }
        }
    }

    private func importTheme() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let theme = try ThemeIO.read(from: url)
                var s = appState.settings
                s.userThemes.append(theme)
                s.themeID = theme.id.uuidString
                appState.settings = s
            } catch {
                importError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - ThemeCard

/// Single tappable card showing a theme's surfaces + accent. Right-click
/// surfaces an Export action; user-theme cards additionally show an
/// inline pencil button that opens the builder.
private struct ThemeCard: View {
    let theme: PurpleTheme
    let isSelected: Bool
    var custom: Bool = false
    /// Edit affordance for user themes — passed in by the parent so the
    /// pencil button can open the builder sheet. `nil` means the row is
    /// not editable (built-ins).
    var onEdit: (() -> Void)? = nil
    /// Export action. Built-in cards pass a closure that synthesizes a
    /// UserTheme via `duplicate(of:)`; user-theme cards pass their
    /// underlying UserTheme directly. Always non-nil — every theme can
    /// be exported.
    var onExport: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Text(theme.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if custom {
                        Text("Custom")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.18), in: Capsule())
                    }
                    Spacer()
                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit theme")
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent.color)
                    }
                }
                .padding(.top, 8)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.accent.color : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onExport {
                Button {
                    onExport()
                } label: {
                    Label("Export theme…", systemImage: "square.and.arrow.up")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit theme…", systemImage: "pencil")
                }
            }
        }
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    /// Schematic of the theme's chrome — sidebar strip on the left,
    /// background + a card-on-bg on the right, accent dot. Renders the
    /// theme's slots directly (each `.color` resolves through the
    /// current OS appearance), so a card in a Light user-pref window
    /// shows the light variant and dark shows the dark.
    private var preview: some View {
        HStack(spacing: 0) {
            // Sidebar strip
            theme.sidebarOpaque.color
                .frame(width: 44)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(theme.accent.color.opacity(i == 0 ? 1 : 0.35))
                                    .frame(width: 6, height: 6)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.textFaint.color.opacity(0.55))
                                    .frame(width: 26, height: 4)
                            }
                        }
                    }
                    .padding(8)
                }

            // Main area
            theme.bg.color
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.text.color)
                            .frame(width: 64, height: 6)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.card.color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(theme.cardBorder.color, lineWidth: 0.5)
                            )
                            .frame(height: 36)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.textDim.color)
                                        .frame(width: 50, height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.textFaint.color)
                                        .frame(width: 36, height: 3)
                                }
                                .padding(7)
                            }
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(theme.accent.color)
                                    .frame(width: 8, height: 8)
                                    .padding(6)
                            }
                    }
                    .padding(10)
                }
        }
    }
}

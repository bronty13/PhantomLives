import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// WYSIWYG palette editor for `UserTheme`. The sheet binds to a local
/// `@State draft` so Cancel can dismiss without committing; Save / Save As
/// commit through `AppState.settings.userThemes` (which flows through
/// `SettingsStore.save` and the AppState Combine bridge — the rest of the
/// app re-renders to the new palette on commit).
///
/// Layout matches the prototype reference in `PurpleIRC/ThemeBuilderView`
/// in spirit: split sheet with form on the left and a live preview pane on
/// the right. The shape differs because PurpleLife's themes carry a paired
/// light/dark slot per token rather than a single color — each row exposes
/// **both** ColorPickers so the user tunes a slot for both modes in one
/// place. The preview pane has a Light/Dark toggle so either side of the
/// pair can be evaluated without leaving the sheet.
struct ThemeBuilderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// The theme being edited. Local state — committed back into
    /// `settings.userThemes` only on Save / Save As.
    @State var draft: UserTheme

    /// True when this draft is brand-new (not yet in `userThemes`). Drives
    /// the header title and hides the Delete button (nothing to delete).
    let isNew: Bool

    @State private var saveAsName: String = ""
    @State private var showingSaveAs: Bool = false
    @State private var showingDeleteConfirm: Bool = false

    /// Which appearance the preview pane is rendering. Independent of
    /// the user's actual appearance setting so they can audit both
    /// halves of every slot before saving.
    @State private var previewMode: ColorScheme = .light

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                editor
                    .frame(minWidth: 460, idealWidth: 500)
                preview
                    .frame(minWidth: 380, idealWidth: 440)
            }
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 660)
        .alert("Save as new theme", isPresented: $showingSaveAs) {
            TextField("Name", text: $saveAsName)
            Button("Save") { commitSaveAs() }
                .disabled(saveAsName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the current draft as a new theme. The original is not modified.")
        }
        .confirmationDialog(
            "Delete '\(draft.name)'?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If this theme is currently active, the app falls back to the built-in it was based on.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.title2)
                .foregroundStyle(Color.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "New theme" : "Edit theme")
                    .font(.title3.weight(.semibold))
                if let basedOn = draft.basedOn,
                   let built = PurpleTheme.allBuiltIns.first(where: { $0.id == basedOn }) {
                    Text("Based on \(built.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Editor (left pane)

    private var editor: some View {
        Form {
            Section("Theme") {
                TextField("Name", text: $draft.name)
            }
            Section("Surfaces") {
                slotRow("Window background", \.bg)
                slotRow("Sidebar",            \.sidebarOpaque)
                slotRow("Card",               \.card)
            }
            Section("Text") {
                slotRow("Primary",   \.text)
                slotRow("Secondary", \.textDim)
                slotRow("Faint",     \.textFaint)
            }
            Section("Lines") {
                slotRow("Card border", \.cardBorder)
                slotRow("Hairline",    \.hairline)
                slotRow("Row hover",   \.rowHover)
            }
            Section("Accent") {
                slotRow("Primary", \.accent)
                slotRow("Soft",    \.accentSoft)
            }
        }
        .formStyle(.grouped)
    }

    /// A single editor row: label on the left, two ColorPickers (Light
    /// then Dark) on the right. Bound through a key path on `UserTheme`
    /// so each slot stays a one-line declaration.
    @ViewBuilder
    private func slotRow(_ label: String, _ kp: WritableKeyPath<UserTheme, UserTheme.HexPair>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            ColorPicker("", selection: lightBinding(kp), supportsOpacity: true)
                .labelsHidden()
                .help("Light mode")
            ColorPicker("", selection: darkBinding(kp), supportsOpacity: true)
                .labelsHidden()
                .help("Dark mode")
        }
    }

    private func lightBinding(_ kp: WritableKeyPath<UserTheme, UserTheme.HexPair>) -> Binding<Color> {
        Binding(
            get: { Color(hex: draft[keyPath: kp].light) ?? .gray },
            set: { draft[keyPath: kp].light = $0.hexARGB }
        )
    }

    private func darkBinding(_ kp: WritableKeyPath<UserTheme, UserTheme.HexPair>) -> Binding<Color> {
        Binding(
            get: { Color(hex: draft[keyPath: kp].dark) ?? .gray },
            set: { draft[keyPath: kp].dark = $0.hexARGB }
        )
    }

    // MARK: - Preview (right pane)

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live preview")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $previewMode) {
                    Image(systemName: "sun.max").tag(ColorScheme.light)
                    Image(systemName: "moon").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ChromePreview(draft: draft, mode: previewMode)
                .padding(16)
        }
        .background(previewMode == .light ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if !isNew {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                exportDraft()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Save this theme as a .purplelifetheme.json file")
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save as…") {
                saveAsName = draft.name + " copy"
                showingSaveAs = true
            }
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Save") { commitSave() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Save the current draft to disk via NSSavePanel. Doesn't commit
    /// the draft into `userThemes` — the user can export while still
    /// iterating; they pick Save / Save As separately to persist.
    private func exportDraft() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ThemeIO.defaultFilename(for: draft)
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ThemeIO.write(draft, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("PurpleLife: theme export failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Commits

    private func commitSave() {
        var s = appState.settings
        UserTheme.upsert(draft, in: &s.userThemes)
        s.themeID = draft.id.uuidString
        appState.settings = s
        dismiss()
    }

    private func commitSaveAs() {
        let trimmed = saveAsName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var clone = draft
        clone.id = UUID()
        clone.name = trimmed
        clone.createdAt = Date()
        var s = appState.settings
        s.userThemes.append(clone)
        s.themeID = clone.id.uuidString
        appState.settings = s
        dismiss()
    }

    private func commitDelete() {
        var s = appState.settings
        s.themeID = PurpleTheme.resolveAfterDelete(
            currentID: s.themeID,
            removedID: draft.id.uuidString,
            basedOn: draft.basedOn
        )
        s.userThemes.removeAll(where: { $0.id == draft.id })
        appState.settings = s
        dismiss()
    }
}

// MARK: - ChromePreview

/// Schematic of PurpleLife's actual chrome shape — sidebar with mock
/// type rows, main area with a header, two list rows, and a card.
/// Reads slot hex strings directly off the draft (rather than going
/// through `PurpleTheme.Slot.color` / `Color(light:dark:)`) so the
/// preview honors the toggle without depending on the SwiftUI
/// colorScheme environment.
private struct ChromePreview: View {
    let draft: UserTheme
    let mode: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 130)
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Text(mode == .light ? "Light mode preview" : "Dark mode preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            color(\.sidebarOpaque)
            VStack(alignment: .leading, spacing: 8) {
                rowMock("Today", iconTint: color(\.accent), selected: true)
                rowMock("People", iconTint: color(\.accent).opacity(0.55))
                rowMock("Books",  iconTint: color(\.accent).opacity(0.55))
                rowMock("Weight", iconTint: color(\.accent).opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private var main: some View {
        ZStack(alignment: .topLeading) {
            color(\.bg)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(\.text))
                        .frame(width: 90, height: 9)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(\.accent))
                        .frame(width: 36, height: 14)
                }
                listRow()
                listRow(hovered: true)
                cardMock()
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func rowMock(_ label: String, iconTint: Color, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle().fill(iconTint).frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 2)
                .fill(color(\.text).opacity(selected ? 1 : 0.75))
                .frame(width: 60, height: 6)
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? color(\.accentSoft) : .clear)
        )
    }

    @ViewBuilder
    private func listRow(hovered: Bool = false) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(\.textDim))
                .frame(width: 110, height: 6)
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(color(\.textFaint))
                .frame(width: 40, height: 5)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovered ? color(\.rowHover) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(color(\.hairline)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func cardMock() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(\.text))
                    .frame(width: 72, height: 7)
                Spacer()
                Circle().fill(color(\.accent)).frame(width: 10, height: 10)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(color(\.textDim))
                .frame(width: 140, height: 5)
            RoundedRectangle(cornerRadius: 2)
                .fill(color(\.textFaint))
                .frame(width: 100, height: 5)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color(\.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(color(\.cardBorder), lineWidth: 0.5)
        )
    }

    /// Resolve a slot key path against the draft for the preview's
    /// current `mode`. Falls back to gray on bad hex — same defensive
    /// posture as `UserTheme.materialised`.
    private func color(_ kp: KeyPath<UserTheme, UserTheme.HexPair>) -> Color {
        let pair = draft[keyPath: kp]
        let hex = mode == .light ? pair.light : pair.dark
        return Color(hex: hex) ?? .gray
    }
}

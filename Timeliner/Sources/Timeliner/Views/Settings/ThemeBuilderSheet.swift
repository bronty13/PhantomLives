import SwiftUI

/// Hex-and-color-picker editor for a single `UserTheme` with a live
/// preview pane on the right showing the theme as the user would
/// experience it in a case-detail view.
struct ThemeBuilderSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Working copy. Committed only on Save.
    @State var draft: UserTheme
    /// True if the draft already exists in `AppSettings.userThemes`. Drives
    /// the title (Edit vs New) and whether Delete is shown.
    let isExisting: Bool

    @State private var pendingDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                editor
                    .frame(width: 320)
                    .padding(20)
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 920, maxWidth: 1100,
               minHeight: 540, idealHeight: 600, maxHeight: 760)
        .alert("Delete this theme?", isPresented: $pendingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAndClose() }
        } message: {
            Text("If this is the active theme, the app will fall back to Default.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "swatchpalette.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(isExisting ? "Edit Theme" : "New Theme")
                    .font(.title3.weight(.semibold))
                if !draft.basedOn.isEmpty {
                    Text("Based on \(draft.basedOn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Editor (left column)

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Section {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }

                colorRow(label: "Gradient — top",        hex: $draft.gradientTopHex)
                colorRow(label: "Gradient — bottom",     hex: $draft.gradientBottomHex)
                colorRow(label: "Accent",                hex: $draft.accentHex)
                colorRow(label: "Card background",       hex: $draft.cardBgHex)
                colorRow(label: "Sidebar background",    hex: $draft.sidebarBgHex)
                colorRow(label: "Timeline track",        hex: $draft.trackColorHex)

                Divider().padding(.vertical, 4)

                Text("Quick swatches")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                quickSwatches
            }
        }
    }

    private func colorRow(label: String, hex: Binding<String>) -> some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex.wrappedValue) ?? .gray },
                set: { hex.wrappedValue = $0.toHex() ?? hex.wrappedValue }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption)
                TextField("", text: hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 110)
            }
            Spacer()
        }
    }

    /// Buttons that overwrite all six color slots from a chosen built-in
    /// theme — useful when the user wants to start over from a different base.
    private var quickSwatches: some View {
        FlowLayout(spacing: 6) {
            ForEach(Theme.all) { t in
                Button {
                    rebase(on: t)
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(t.accentColor).frame(width: 6, height: 6)
                        Text(t.name).font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.background.opacity(0.7)))
                    .overlay(Capsule().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rebase(on t: Theme) {
        draft.basedOn = t.name
        draft.gradientTopHex = t.gradientColors.first?.toHex() ?? draft.gradientTopHex
        draft.gradientBottomHex = t.gradientColors.last?.toHex() ?? draft.gradientBottomHex
        draft.accentHex = t.accentColor.toHex() ?? draft.accentHex
        draft.cardBgHex = t.cardBackground.toHex() ?? draft.cardBgHex
        draft.sidebarBgHex = t.sidebarBackground.toHex() ?? draft.sidebarBgHex
        draft.trackColorHex = t.timelineTrackColor.toHex() ?? draft.trackColorHex
    }

    // MARK: - Preview (right column)

    private var preview: some View {
        let theme = draft.asTheme()
        return ZStack {
            LinearGradient(
                colors: theme.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Mock toolbar
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(theme.accentColor)
                    Text("Sample Case")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }
                .padding(12)
                .background(theme.sidebarBackground)
                Divider()

                // Mock timeline
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1994")
                            .font(.system(.title2, design: .rounded, weight: .heavy))
                            .padding(.horizontal, 16).padding(.top, 12)

                        previewEvent(
                            day: "12", monthShort: "Jun",
                            title: "Sample event",
                            body: "Body text shown in the *card*. Tag chips render with their hex color.",
                            tagColor: theme.accentColor,
                            tagName: "evidence",
                            theme: theme
                        )
                        previewEvent(
                            day: "17", monthShort: "Jun",
                            title: "Another event",
                            body: "Importance pip indicator on the left.",
                            tagColor: .pink,
                            tagName: "scene",
                            theme: theme
                        )
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(20)
    }

    private func previewEvent(
        day: String, monthShort: String,
        title: String, body: String,
        tagColor: Color, tagName: String,
        theme: Theme
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(day).font(.system(.body, design: .rounded, weight: .semibold))
                Text(monthShort).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i < 2 ? Color.blue : Color.blue.opacity(0.2))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(title).font(.body.weight(.semibold))
                }
                Text(body).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(tagColor).frame(width: 6, height: 6)
                        Text(tagName).font(.caption2)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(tagColor.opacity(0.18)))
                    .overlay(Capsule().stroke(tagColor.opacity(0.4), lineWidth: 0.5))
                }
            }
        }
        .padding(12)
        .background(theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.18), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isExisting {
                Button("Delete", role: .destructive) {
                    pendingDeleteConfirm = true
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isExisting ? "Save" : "Create") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Actions

    private func save() {
        var s = appState.settings
        var d = draft
        d.updatedAt = Date()
        if let idx = s.userThemes.firstIndex(where: { $0.id == d.id }) {
            s.userThemes[idx] = d
        } else {
            s.userThemes.append(d)
        }
        appState.settings = s
        dismiss()
    }

    private func deleteAndClose() {
        var s = appState.settings
        s.userThemes.removeAll { $0.id == draft.id }
        // If this was the active theme, fall back to Default.
        if s.themeName == "user:\(draft.id.uuidString)" || s.themeName == draft.name {
            s.themeName = "Default"
        }
        appState.settings = s
        dismiss()
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// WYSIWYG theme builder. Edits a `UserTheme` with live preview — every
/// ColorPicker change reflects in a sample message pane immediately, so
/// users tune by visual feedback rather than guessing hex values.
///
/// Flow:
///   1. ThemesSetup tab opens this sheet via "+ New Theme" (duplicates
///      the currently-selected theme as a starting point) or
///      "Edit Theme…" on an existing user theme.
///   2. The sheet binds to a local `@State draft: UserTheme` so changes
///      can be discarded with Cancel without mutating settings.
///   3. Save commits the draft into `settings.userThemes` (insert or
///      update by id) and switches the active `themeID` to the draft's
///      uuid so the user sees their work apply immediately.
///   4. Save As clones the draft with a fresh UUID + new name.
///   5. Delete removes the user theme; if it was active, falls back
///      to the closest built-in (its `basedOn`, or `.classic`).
struct ThemeBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: SettingsStore

    /// The theme being edited. Local state — committed back into
    /// settings only on Save / Save As.
    @State var draft: UserTheme

    /// True when this draft is brand-new (not yet in settings.userThemes).
    /// Drives the title and the Delete button's enabled state.
    let isNew: Bool

    @State private var saveAsName: String = ""
    @State private var showingSaveAs: Bool = false
    @State private var showingDeleteConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                editor
                    .frame(minWidth: 380, idealWidth: 420)
                preview
                    .frame(minWidth: 360, idealWidth: 440)
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 620)
        .alert("Save as new theme", isPresented: $showingSaveAs) {
            TextField("Name", text: $saveAsName)
            Button("Save") { commitSaveAs() }
                .disabled(saveAsName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the current draft as a new theme. The original theme is not modified.")
        }
        .confirmationDialog(
            "Delete '\(draft.name)'?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If this theme is currently active, the previously selected built-in theme takes over.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.title2)
                .foregroundStyle(Color.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "New theme" : "Edit theme")
                    .font(.title3.weight(.semibold))
                if let basedOn = draft.basedOn {
                    Text("Based on \(basedOn)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { commitSave() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Editor (left pane)

    private var editor: some View {
        Form {
            Section("Theme") {
                TextField("Name", text: $draft.name)
            }
            Section("Surface") {
                colorRow("Chat background", hex: $draft.chatBackgroundHex)
                colorRow("Chat foreground", hex: $draft.chatForegroundHex)
            }
            Section("Per-event base palette") {
                colorRow("Your nick",        hex: $draft.ownNickColorHex)
                colorRow("Info / system",    hex: $draft.infoColorHex)
                colorRow("Error",            hex: $draft.errorColorHex)
                colorRow("MOTD / numerics",  hex: $draft.motdColorHex)
                colorRow("NOTICE",           hex: $draft.noticeColorHex)
                colorRow("Action (/me)",     hex: $draft.actionColorHex)
                colorRow("Join",             hex: $draft.joinColorHex)
                colorRow("Part / Quit",      hex: $draft.partColorHex)
                colorRow("Nick change / Topic", hex: $draft.nickNickColorHex)
            }
            Section("Backgrounds") {
                colorRow("Mention background",  hex: $draft.mentionBackgroundHex)
                colorRow("Watch-hit background", hex: $draft.watchlistBackgroundHex)
                colorRow("Find-match background", hex: $draft.findBackgroundHex)
            }
            Section("Nick palette") {
                Text("Eight colors hashed by nick for consistent per-user coloring. Edit any slot.")
                    .font(.caption).foregroundStyle(.tertiary)
                ForEach(0..<8) { i in
                    if i < draft.nickPaletteHex.count {
                        colorRow("Slot \(i + 1)", hex: paletteBinding(at: i))
                    }
                }
            }
            Section("Per-event color overrides") {
                Text("Override the base palette for a specific event kind. Click ▽ to add an override; click ↺ to drop it (the base palette wins).")
                    .font(.caption).foregroundStyle(.tertiary)
                ForEach(ChatLineKindTag.allCases, id: \.self) { tag in
                    overrideRow(tag: tag)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func colorRow(_ label: String, hex: Binding<String>) -> some View {
        let binding = colorBinding(hex: hex)
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: binding, supportsOpacity: true)
                .labelsHidden()
            Text(hex.wrappedValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func overrideRow(tag: ChatLineKindTag) -> some View {
        HStack {
            Text(tag.displayName)
            Spacer()
            if draft.kindOverrideHex[tag.rawValue] != nil {
                ColorPicker("", selection: overrideBinding(tag: tag), supportsOpacity: true)
                    .labelsHidden()
                Text(draft.kindOverrideHex[tag.rawValue] ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                Button {
                    draft.kindOverrideHex.removeValue(forKey: tag.rawValue)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle")
                }
                .help("Drop the override and inherit from the base palette")
                .buttonStyle(.borderless)
            } else {
                Text("inherit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button {
                    // Seed with the slot the override would replace, so the
                    // first reveal is sane rather than #000000.
                    draft.kindOverrideHex[tag.rawValue] = seedHex(for: tag)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Add an override for this event kind")
                .buttonStyle(.borderless)
            }
        }
    }

    private func seedHex(for tag: ChatLineKindTag) -> String {
        switch tag {
        case .info, .raw:        return draft.infoColorHex
        case .error:             return draft.errorColorHex
        case .privmsg:           return draft.chatForegroundHex
        case .privmsgSelf:       return draft.ownNickColorHex
        case .action:            return draft.actionColorHex
        case .notice:            return draft.noticeColorHex
        case .join:              return draft.joinColorHex
        case .part, .quit:       return draft.partColorHex
        case .nick, .topic:      return draft.nickNickColorHex
        case .mention:           return draft.mentionBackgroundHex
        case .watchlist:         return draft.watchlistBackgroundHex
        }
    }

    // MARK: - Preview (right pane)

    private var preview: some View {
        let theme = draft.materialised
        let overrides = draft.kindOverridesMaterialised
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live preview")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("#\(draft.id.uuidString.prefix(8))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    sampleRow("12:00:01", "— Connected to irc.libera.chat",
                              color: overrides[.info] ?? theme.infoColor)
                    sampleRow("12:00:02", "← purple-user joined",
                              color: overrides[.join] ?? theme.joinColor,
                              isCaption: true)
                    sampleRow("12:00:03", "alice → alice_",
                              color: overrides[.nick] ?? theme.nickNickColor,
                              isCaption: true)
                    sampleRow("12:00:04", "Topic: Welcome to #swift",
                              color: overrides[.topic] ?? theme.nickNickColor)
                    samplePrivmsg("12:00:05", nick: "alice",
                                  text: "Hey, did you see the new build?",
                                  color: overrides[.privmsg] ?? theme.nickPalette[0])
                    samplePrivmsg("12:00:06", nick: "purple-user",
                                  text: "Yep — testing it now.",
                                  color: overrides[.privmsgSelf] ?? theme.ownNickColor,
                                  isSelf: true)
                    sampleAction("12:00:07", nick: "bob",
                                 text: "raises a glass",
                                 color: overrides[.action] ?? theme.nickPalette[1])
                    sampleNotice("12:00:08", from: "NickServ",
                                 text: "You are now identified.",
                                 color: overrides[.notice] ?? theme.noticeColor)
                    sampleRow("12:00:09", "→ carol joined",
                              color: overrides[.join] ?? theme.joinColor,
                              isCaption: true)
                    sampleRow("12:00:10", "← dave left (Connection reset)",
                              color: overrides[.part] ?? theme.partColor,
                              isCaption: true)
                    sampleRow("12:00:11", "← eve quit (Ping timeout)",
                              color: overrides[.quit] ?? theme.partColor,
                              isCaption: true)
                    sampleMention("12:00:12", nick: "frank",
                                  text: "ping purple-user — you around?",
                                  fg: theme.chatForeground,
                                  bg: overrides[.mention] ?? theme.mentionBackground)
                    sampleRow("12:00:13", "★★★ alice is online (via MONITOR)",
                              color: overrides[.info] ?? theme.infoColor,
                              bg: overrides[.watchlist] ?? theme.watchlistBackground)
                    sampleRow("12:00:14", "! Connection failed: TLS handshake",
                              color: overrides[.error] ?? theme.errorColor)
                    sampleRow("12:00:15", ">> NICK purple-user",
                              color: overrides[.raw] ?? theme.infoColor,
                              isCaption: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.chatBackground)
            .foregroundStyle(theme.chatForeground)
        }
    }

    @ViewBuilder
    private func sampleRow(_ ts: String, _ text: String,
                           color: Color, isCaption: Bool = false,
                           bg: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(color)
                .font(isCaption ? .caption : .body)
        }
        .padding(4)
        .background(bg ?? Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func samplePrivmsg(_ ts: String, nick: String, text: String,
                               color: Color, isSelf: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("<\(nick)>")
                .foregroundStyle(color)
                .fontWeight(isSelf ? .semibold : .regular)
            Text(text)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sampleAction(_ ts: String, nick: String, text: String,
                              color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts).font(.caption.monospaced()).foregroundStyle(.secondary)
            (Text("* \(nick) ").foregroundStyle(color) + Text(text))
                .italic()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sampleNotice(_ ts: String, from: String, text: String,
                              color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts).font(.caption.monospaced()).foregroundStyle(.secondary)
            (Text("-\(from)- ").foregroundStyle(color) + Text(text).foregroundStyle(color))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sampleMention(_ ts: String, nick: String, text: String,
                               fg: Color, bg: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ts).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("@").foregroundStyle(.orange).font(.caption.bold())
                Text("<\(nick)>").foregroundStyle(fg).fontWeight(.medium)
                Text(text).foregroundStyle(fg)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Footer (Save As / Delete / Export)

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                saveAsName = "\(draft.name) copy"
                showingSaveAs = true
            } label: {
                Label("Save As…", systemImage: "doc.on.doc")
            }
            Button {
                exportToFile()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            Spacer()
            if !isNew {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding()
    }

    // MARK: - Color binding bridges

    /// A SwiftUI `Color` binding backed by a hex `String` binding. Reads
    /// parse the hex; writes serialise back. Falls back to `.gray` on a
    /// parse failure so the picker has a sane current value to start
    /// from rather than crashing or going invisible.
    private func colorBinding(hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue) ?? .gray },
            set: { hex.wrappedValue = $0.hexRGB }
        )
    }

    private func overrideBinding(tag: ChatLineKindTag) -> Binding<Color> {
        Binding(
            get: { Color(hex: draft.kindOverrideHex[tag.rawValue] ?? "") ?? .gray },
            set: { draft.kindOverrideHex[tag.rawValue] = $0.hexRGB }
        )
    }

    private func paletteBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { index < draft.nickPaletteHex.count ? draft.nickPaletteHex[index] : "#888888" },
            set: { newValue in
                if index < draft.nickPaletteHex.count {
                    draft.nickPaletteHex[index] = newValue
                }
            }
        )
    }

    // MARK: - Commit / Save / Delete / Export

    private func commitSave() {
        if let i = settings.settings.userThemes.firstIndex(where: { $0.id == draft.id }) {
            settings.settings.userThemes[i] = draft
        } else {
            settings.settings.userThemes.append(draft)
        }
        // Switch to the just-saved theme so the user sees their work.
        settings.settings.themeID = draft.id.uuidString
        dismiss()
    }

    private func commitSaveAs() {
        var copy = draft
        copy.id = UUID()
        copy.name = saveAsName.trimmingCharacters(in: .whitespaces)
        copy.createdAt = Date()
        settings.settings.userThemes.append(copy)
        settings.settings.themeID = copy.id.uuidString
        dismiss()
    }

    private func commitDelete() {
        settings.settings.userThemes.removeAll { $0.id == draft.id }
        // If the deleted theme was active, fall back to its base or classic.
        if settings.settings.themeID == draft.id.uuidString {
            settings.settings.themeID = draft.basedOn ?? "classic"
        }
        dismiss()
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(safeFilename(draft.name)).purpletheme"
        panel.canCreateDirectories = true
        panel.title = "Export theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(draft)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("PurpleIRC: export theme failed: \(error)")
            }
        }
    }

    private func safeFilename(_ s: String) -> String {
        let bad: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\0"]
        let cleaned = String(s.map { bad.contains($0) ? "_" : $0 })
        return cleaned.isEmpty ? "theme" : cleaned
    }
}

/// Helper used by `/theme import` and the Themes-tab Import button.
/// Reads a `.purpletheme` JSON, decodes a `UserTheme`, fresh-stamps
/// its UUID + creation date so multiple imports of the same file
/// don't collide, and inserts into settings.
enum ThemeImporter {
    @MainActor
    static func importTheme(from url: URL, into settings: SettingsStore) -> UserTheme? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var theme = try? JSONDecoder().decode(UserTheme.self, from: data) else {
            return nil
        }
        theme.id = UUID()
        theme.createdAt = Date()
        settings.settings.userThemes.append(theme)
        return theme
    }
}

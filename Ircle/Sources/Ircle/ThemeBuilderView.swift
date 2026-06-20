import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// WYSIWYG editor for a Modern theme: colour wells, the flat/beveled toggle, and
/// per-element fonts on the left; a live mock-chat preview on the right. Saves
/// into `SettingsStore.userThemes` and can export a shareable `.ircletheme`.
struct ThemeBuilderView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: ModernTheme
    @State private var fontPickerSlot: FontSlot? = nil

    private var isExisting: Bool { settingsStore.settings.userThemes.contains { $0.id == draft.id } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                editor.frame(minWidth: 340, idealWidth: 380)
                preview.frame(minWidth: 260, idealWidth: 300)
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 540)
        .sheet(item: $fontPickerSlot) { slot in
            FontFamilyPickerSheet(current: styleBinding(slot).wrappedValue.family) { family in
                var st = styleBinding(slot).wrappedValue
                st.family = family
                styleBinding(slot).wrappedValue = st
            }
        }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            TextField("Theme name", text: $draft.name).textFieldStyle(.roundedBorder).frame(width: 240)
            Spacer()
            Button("Save") { commitSave() }.keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private var footer: some View {
        HStack {
            Button("Save as Copy…") { commitSaveAs() }
            Button("Export…") { exportToFile() }
            if isExisting {
                Button(role: .destructive) { commitDelete() } label: { Text("Delete") }
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    // MARK: Editor

    private let surfaceRows: [(String, WritableKeyPath<ModernTheme, String>)] = [
        ("Window", \.windowBG), ("Panels", \.paneBG), ("Message area", \.textBG),
        ("Hairline / border", \.hairline), ("Chrome text", \.chromeText), ("Selection", \.selection),
    ]
    private let bevelRows: [(String, WritableKeyPath<ModernTheme, String>)] = [
        ("Bevel light edge", \.bevelLight), ("Bevel dark edge", \.bevelDark),
    ]
    private let messageRows: [(String, WritableKeyPath<ModernTheme, String>)] = [
        ("Normal text", \.normalText), ("Timestamp", \.timestamp), ("Server / MOTD", \.serverText),
        ("Topic / status", \.topicText), ("Joins", \.joinText), ("Parts / quits", \.partText),
        ("Notices", \.noticeText), ("Actions", \.actionText), ("Errors", \.errorText),
        ("Your nick", \.ownNick), ("Other nicks", \.otherNick), ("Mention highlight", \.mentionBG),
    ]

    private var editor: some View {
        Form {
            Section("Chrome") {
                Toggle("Flat panels (no 3D bevels)", isOn: $draft.flatChrome)
                ForEach(surfaceRows, id: \.0) { row in colorRow(row.0, row.1) }
                if !draft.flatChrome {
                    ForEach(bevelRows, id: \.0) { row in colorRow(row.0, row.1) }
                }
            }
            Section("Message colours") {
                ForEach(messageRows, id: \.0) { row in colorRow(row.0, row.1) }
            }
            Section("Fonts") {
                ForEach(FontSlot.allCases) { slot in fontRow(slot) }
                Text("Empty family / size means inherit — root slots fall back to Monaco (body) and the system UI font (chrome); the others inherit the message body.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func colorRow(_ label: String, _ kp: WritableKeyPath<ModernTheme, String>) -> some View {
        ColorPicker(label, selection: colorBinding(kp), supportsOpacity: false)
    }

    private func fontRow(_ slot: FontSlot) -> some View {
        let st = styleBinding(slot)
        return DisclosureGroup(slot.displayName) {
            HStack {
                Text("Family").frame(width: 70, alignment: .leading)
                Button(st.wrappedValue.family.isEmpty ? "Inherit / default"
                       : displayFamily(st.wrappedValue.family)) { fontPickerSlot = slot }
                if !st.wrappedValue.family.isEmpty {
                    Button { st.wrappedValue.family = "" } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).help("Reset to inherit")
                }
            }
            HStack {
                Text("Size").frame(width: 70, alignment: .leading)
                Slider(value: st.size, in: 0...28, step: 1)
                Text(st.wrappedValue.size == 0 ? "—" : "\(Int(st.wrappedValue.size))")
                    .frame(width: 28, alignment: .trailing).foregroundColor(.secondary)
            }
            Picker("Weight", selection: st.weight) {
                ForEach(FontStyle.Weight.allCases) { w in Text(w.displayName).tag(w) }
            }
            Toggle("Italic", isOn: Binding(get: { st.wrappedValue.italic ?? false },
                                           set: { st.wrappedValue.italic = $0 }))
            Toggle("Ligatures", isOn: Binding(get: { st.wrappedValue.ligatures ?? false },
                                              set: { st.wrappedValue.ligatures = $0 }))
            HStack {
                Text("Tracking").frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { st.wrappedValue.tracking ?? 0 },
                                      set: { st.wrappedValue.tracking = $0 == 0 ? nil : $0 }),
                       in: -1...4, step: 0.25)
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ModernThemePreview(palette: draft.palette(baseFontSize: settingsStore.settings.fontSize))
            .padding(8)
    }

    // MARK: Bindings

    private func colorBinding(_ kp: WritableKeyPath<ModernTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(ircleHex: draft[keyPath: kp]) ?? .gray },
            set: { draft[keyPath: kp] = $0.ircleHexString ?? draft[keyPath: kp] }
        )
    }

    private func styleBinding(_ slot: FontSlot) -> Binding<FontStyle> {
        Binding(
            get: { draft.fonts[slot.rawValue] ?? .inherit },
            set: { newValue in
                if newValue == .inherit { draft.fonts[slot.rawValue] = nil }
                else { draft.fonts[slot.rawValue] = newValue }
            }
        )
    }

    private func displayFamily(_ f: String) -> String {
        switch f {
        case "system-mono": return "System Mono"
        case "system-proportional": return "System (UI)"
        default: return f
        }
    }

    // MARK: Commit / share

    private func commitSave() {
        var t = draft
        t.isBuiltIn = false
        if let idx = settingsStore.settings.userThemes.firstIndex(where: { $0.id == t.id }) {
            settingsStore.settings.userThemes[idx] = t
        } else {
            settingsStore.settings.userThemes.append(t)
        }
        settingsStore.settings.modernModeEnabled = true
        settingsStore.settings.modernThemeID = t.id
        dismiss()
    }

    private func commitSaveAs() {
        var t = ModernTheme.duplicate(of: draft, name: draft.name + " Copy")
        t.basedOn = draft.basedOn ?? draft.id
        settingsStore.settings.userThemes.append(t)
        settingsStore.settings.modernModeEnabled = true
        settingsStore.settings.modernThemeID = t.id
        dismiss()
    }

    private func commitDelete() {
        settingsStore.settings.userThemes.removeAll { $0.id == draft.id }
        if settingsStore.settings.modernThemeID == draft.id {
            settingsStore.settings.modernThemeID = draft.basedOn ?? ModernTheme.defaultID
        }
        dismiss()
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ircletheme") ?? .json]
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "\(safeFilename(draft.name)).ircletheme"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(draft) {
            try? data.write(to: url, options: .atomic)
        } else { NSSound.beep() }
    }

    private func safeFilename(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Ircle Theme" : cleaned
    }
}

// MARK: - Theme import

/// Decode a `.ircletheme` (a JSON `ModernTheme`) into the user's library. Stamps
/// a fresh id so re-imports never collide with an existing or built-in theme.
enum ThemeImporter {
    @MainActor
    @discardableResult
    static func importTheme(from url: URL, into settings: SettingsStore) -> ModernTheme? {
        guard let data = try? Data(contentsOf: url),
              var theme = try? JSONDecoder().decode(ModernTheme.self, from: data) else { return nil }
        theme.id = UUID().uuidString
        theme.isBuiltIn = false
        settings.settings.userThemes.append(theme)
        return theme
    }
}

// MARK: - Live preview

/// A compact mock of the main window in a given palette — channelbar, message
/// area, and nick list — so the editor reflects colours, fonts, and the
/// flat/beveled chrome live.
struct ModernThemePreview: View {
    let palette: PlatinumPalette

    var body: some View {
        VStack(spacing: 0) {
            // Channel header
            HStack {
                Text("#ircle").font(palette.chromeFontBold()).foregroundColor(palette.chromeText)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .platinumBevel(palette, raised: true)

            HStack(spacing: 0) {
                // Messages
                VStack(alignment: .leading, spacing: 2) {
                    msg("12:00", "<you>", " welcome to the channel", palette.ownNick, palette.normalText)
                    msg("12:01", "<friend>", " hey, nice theme!", palette.otherNick, palette.normalText)
                    sys("12:01", "*** sam (sam@host) has joined", palette.joinText)
                    msg("12:02", "* you", " waves hello", palette.actionText, palette.actionText)
                    sys("12:03", "-NickServ- you are now identified", palette.noticeText)
                    sys("12:03", "*** Topic: a modern look for Ircle", palette.topicText)
                    HStack(spacing: 4) {
                        Text("12:04").ircleFont(palette.font(.timestamp, fallbackSize: 12)).foregroundColor(palette.timestamp)
                        Text("<you> did you see this?")
                            .ircleFont(palette.font(.messageBody, fallbackSize: 12))
                            .foregroundColor(palette.normalText)
                            .padding(.horizontal, 2).background(palette.mentionBG)
                    }
                    sys("12:05", "!!! cannot join #secret: +k", palette.errorText)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.textBG)

                // Nick list
                VStack(alignment: .leading, spacing: 3) {
                    Text("Names").font(palette.chromeFontBold()).foregroundColor(palette.chromeText)
                    ForEach(["@you", "+friend", "sam"], id: \.self) { n in
                        Text(n).font(palette.chromeFont()).foregroundColor(palette.chromeText)
                    }
                    Spacer()
                }
                .padding(6)
                .frame(width: 96, alignment: .topLeading)
                .platinumBevel(palette, raised: false)
            }
        }
        .background(palette.windowBG)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.hairline, lineWidth: 1))
    }

    private func msg(_ time: String, _ nick: String, _ text: String,
                     _ nickColor: Color, _ textColor: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(time).ircleFont(palette.font(.timestamp, fallbackSize: 12)).foregroundColor(palette.timestamp)
            (Text(nick).foregroundColor(nickColor) + Text(text).foregroundColor(textColor))
                .ircleFont(palette.font(.messageBody, fallbackSize: 12))
        }
    }

    private func sys(_ time: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(time).ircleFont(palette.font(.timestamp, fallbackSize: 12)).foregroundColor(palette.timestamp)
            Text(text).ircleFont(palette.font(.systemLine, fallbackSize: 12)).foregroundColor(color)
        }
    }
}

// MARK: - Font family picker

/// A searchable installed-font picker with a "monospaced only" filter and an
/// "Inherit / default" reset. Each row previews itself.
struct FontFamilyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var monoOnly = false

    private var families: [String] {
        let base = monoOnly ? InstalledFonts.monospacedFamilyNames : InstalledFonts.allFamilyNames
        guard !query.isEmpty else { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search fonts…", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Monospaced", isOn: $monoOnly).toggleStyle(.checkbox)
            }
            .padding(10)
            Divider()
            List {
                Button("Inherit / default") { onPick(""); dismiss() }
                Button("System Mono") { onPick("system-mono"); dismiss() }
                Button("System (UI)") { onPick("system-proportional"); dismiss() }
                Divider()
                ForEach(families, id: \.self) { name in
                    Button {
                        onPick(name); dismiss()
                    } label: {
                        HStack {
                            Text(name).font(.custom(name, size: 13))
                            Spacer()
                            if name == current { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(10)
        }
        .frame(width: 360, height: 460)
    }
}

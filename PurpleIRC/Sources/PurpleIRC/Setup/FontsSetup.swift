import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Fonts

/// Font controls — Chat (root font), Per-element overrides, Zoom, plus
/// a built-in installed-font browser. Per-element overrides walk the
/// inheritance chain via `FontStyle.resolved(parent:)`, so leaving any
/// field at its sentinel inherits from the chat body.
struct FontsSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var browseTarget: BrowseTarget? = nil
    @State private var showCustomFont: Bool = false

    enum BrowseTarget: Identifiable {
        case chatBody, nick, timestamp, systemLine
        var id: Int {
            switch self {
            case .chatBody: return 0
            case .nick: return 1
            case .timestamp: return 2
            case .systemLine: return 3
            }
        }
        var label: String {
            switch self {
            case .chatBody:    return "chat body"
            case .nick:        return "nick column"
            case .timestamp:   return "timestamp column"
            case .systemLine:  return "system / info lines"
            }
        }
    }

    var body: some View {
        Form {
            Section("Chat font (root)") {
                Picker("Family", selection: $settings.settings.chatFontFamily) {
                    ForEach(ChatFontFamily.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                HStack {
                    if !settings.settings.chatBodyFont.family.isEmpty {
                        Label("Custom: \(settings.settings.chatBodyFont.family)",
                              systemImage: "textformat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            settings.settings.chatBodyFont.family = ""
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    } else {
                        Button {
                            browseTarget = .chatBody
                        } label: {
                            Label("Pick installed font…", systemImage: "magnifyingglass")
                        }
                    }
                    Spacer()
                }
                HStack {
                    Text("Size")
                    Slider(value: $settings.settings.chatFontSize, in: 10...24, step: 1)
                    Text(verbatim: "\(Int(settings.settings.chatFontSize)) pt")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Toggle("Bold chat text", isOn: $settings.settings.boldChatText)
                Text("/font + - reset | <pt> | family <name> works as a slash command. ⌘= / ⌘- / ⌘0 in the View menu adjust size live. Picking a custom installed font overrides the family above.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section("Chat body — advanced") {
                ligaturesToggle(for: $settings.settings.chatBodyFont,
                                fallback: false)
                trackingSlider(for: $settings.settings.chatBodyFont)
                lineHeightSlider(for: $settings.settings.chatBodyFont)
                weightPicker(for: $settings.settings.chatBodyFont)
                italicToggle(for: $settings.settings.chatBodyFont)
            }

            Section("Per-element overrides") {
                Text("Each slot inherits from the chat body unless you override it. Use the **Inherit** weight or leave the family blank to fall back.")
                    .font(.caption).foregroundStyle(.tertiary)
                slotEditor(title: "Nick column",
                           target: .nick,
                           binding: $settings.settings.nickFont)
                slotEditor(title: "Timestamp column",
                           target: .timestamp,
                           binding: $settings.settings.timestampFont)
                slotEditor(title: "System / info lines",
                           target: .systemLine,
                           binding: $settings.settings.systemLineFont)
            }

            Section("Zoom") {
                HStack {
                    Text("View zoom")
                    Slider(value: $settings.settings.viewZoom, in: 0.5...2.0, step: 0.05)
                    Text(verbatim: String(format: "%.2f×", settings.settings.viewZoom))
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text("Multiplies chat font size on top of the slider above. /zoom + - reset.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $browseTarget) { target in
            FontFamilyPickerSheet(monoOnly: target == .chatBody) { picked in
                applyPickedFamily(picked, to: target)
                browseTarget = nil
            } onCancel: {
                browseTarget = nil
            }
        }
    }

    // MARK: Slot editor

    @ViewBuilder
    private func slotEditor(title: String,
                            target: BrowseTarget,
                            binding: Binding<FontStyle>) -> some View {
        DisclosureGroup(title) {
            HStack {
                if !binding.wrappedValue.family.isEmpty {
                    Text(binding.wrappedValue.family)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Clear") { binding.wrappedValue.family = "" }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                } else {
                    Text("(inherits chat body family)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    browseTarget = target
                } label: {
                    Label("Pick…", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }
            HStack {
                Text("Size")
                Slider(
                    value: Binding(
                        get: { binding.wrappedValue.size > 0 ? binding.wrappedValue.size : 0 },
                        set: { binding.wrappedValue.size = $0 }
                    ),
                    in: 0...24, step: 1
                )
                Text(binding.wrappedValue.size > 0
                     ? "\(Int(binding.wrappedValue.size)) pt"
                     : "inherit")
                    .frame(width: 60, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            weightPicker(for: binding)
            italicToggle(for: binding)
            ligaturesToggle(for: binding, fallback: nil)
            trackingSlider(for: binding)
            lineHeightSlider(for: binding)
        }
    }

    // MARK: Field editors

    @ViewBuilder
    private func weightPicker(for binding: Binding<FontStyle>) -> some View {
        Picker("Weight", selection: binding.weight) {
            ForEach(FontStyle.Weight.allCases, id: \.self) { w in
                Text(w.displayName).tag(w)
            }
        }
    }

    @ViewBuilder
    private func italicToggle(for binding: Binding<FontStyle>) -> some View {
        Toggle("Italic", isOn: Binding(
            get: { binding.wrappedValue.italic ?? false },
            set: { binding.wrappedValue.italic = $0 }
        ))
    }

    @ViewBuilder
    private func ligaturesToggle(for binding: Binding<FontStyle>,
                                 fallback: Bool?) -> some View {
        Toggle("Ligatures", isOn: Binding(
            get: { binding.wrappedValue.ligatures ?? (fallback ?? false) },
            set: { binding.wrappedValue.ligatures = $0 }
        ))
    }

    @ViewBuilder
    private func trackingSlider(for binding: Binding<FontStyle>) -> some View {
        HStack {
            Text("Tracking")
            Slider(
                value: Binding(
                    get: { binding.wrappedValue.tracking ?? 0 },
                    set: { binding.wrappedValue.tracking = $0 }
                ),
                in: -2...4, step: 0.1
            )
            Text(verbatim: String(format: "%+.1f", binding.wrappedValue.tracking ?? 0))
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func lineHeightSlider(for binding: Binding<FontStyle>) -> some View {
        HStack {
            Text("Line height")
            Slider(
                value: Binding(
                    get: { binding.wrappedValue.lineHeightMultiple ?? 1.0 },
                    set: { binding.wrappedValue.lineHeightMultiple = $0 }
                ),
                in: 0.8...2.0, step: 0.05
            )
            Text(verbatim: String(format: "%.2f×", binding.wrappedValue.lineHeightMultiple ?? 1.0))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: Picker callback

    private func applyPickedFamily(_ family: String, to target: BrowseTarget) {
        switch target {
        case .chatBody:    settings.settings.chatBodyFont.family = family
        case .nick:        settings.settings.nickFont.family = family
        case .timestamp:   settings.settings.timestampFont.family = family
        case .systemLine:  settings.settings.systemLineFont.family = family
        }
    }
}

/// Searchable installed-font picker. Lists every family
/// `NSFontManager.shared.availableFontFamilies` returns. The chat-body
/// picker can be filtered to monospaced fonts via the `monoOnly` flag
/// (the chat body really wants a fixed-pitch font; nick / timestamp
/// might not).
struct FontFamilyPickerSheet: View {
    let monoOnly: Bool
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query: String = ""
    @State private var monoFilter: Bool

    init(monoOnly: Bool, onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.monoOnly = monoOnly
        self.onPick = onPick
        self.onCancel = onCancel
        self._monoFilter = State(initialValue: monoOnly)
    }

    private var families: [String] {
        let source = monoFilter
            ? InstalledFonts.monospacedFamilyNames
            : InstalledFonts.allFamilyNames
        guard !query.isEmpty else { return source }
        let q = query.lowercased()
        return source.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick a font")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("Monospaced only", isOn: $monoFilter)
                    .toggleStyle(.checkbox)
            }
            .padding()
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search families", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            List(families, id: \.self) { name in
                HStack {
                    Text(name)
                        .font(.custom(name, size: 13))
                    Spacer()
                    Text("AaBb 123")
                        .font(.custom(name, size: 13))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onPick(name) }
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 480)
    }
}


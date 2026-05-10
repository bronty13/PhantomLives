import AppKit
import SwiftUI

/// Content view for the menu-bar quick-capture popover. A small typed
/// input that drops a new record into PurpleLife without the user
/// having to bring the main window forward — picks the type, enters
/// a title, hits ⌘↩ (or clicks Save), done.
///
/// Default flow:
/// - Type defaults to whichever the user picked last via this popover
///   (UserDefaults `PurpleLife.quickCapture.lastTypeId`); falls back to
///   the first visible type.
/// - The captured text is written into the type's `primaryFieldKey`
///   (every built-in type has one). For types without a primary, the
///   text is written into the first text-bearing field.
struct QuickCaptureMenu: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedTypeId: String = ""
    @State private var titleText: String = ""
    @State private var statusMessage: String?
    @FocusState private var titleFieldFocused: Bool

    private static let lastTypeKey = "PurpleLife.quickCapture.lastTypeId"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wand.and.sparkles")
                    .foregroundStyle(Theme.accent)
                Text("Quick capture").font(.headline)
                Spacer()
            }
            .padding(.bottom, 2)

            Picker("Type", selection: $selectedTypeId) {
                ForEach(visibleTypes, id: \.id) { t in
                    Label(t.name, systemImage: t.systemImage).tag(t.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            TextField(placeholder, text: $titleText)
                .textFieldStyle(.roundedBorder)
                .focused($titleFieldFocused)
                .onSubmit { save() }

            HStack {
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            if selectedTypeId.isEmpty {
                selectedTypeId = defaultTypeId()
            }
            // Slight delay so the popover finishes laying out before we
            // grab focus — without this the field-focus binding can
            // miss its window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                titleFieldFocused = true
            }
        }
    }

    // MARK: - Derived

    private var visibleTypes: [ObjectType] {
        appState.schema.visibleTypes
    }

    private var selectedType: ObjectType? {
        appState.schema.type(id: selectedTypeId) ?? visibleTypes.first
    }

    private var placeholder: String {
        guard let t = selectedType else { return "Title" }
        if let key = t.primaryFieldKey,
           let field = t.field(forKey: key) {
            return field.name
        }
        return "Title"
    }

    // MARK: - Actions

    private func defaultTypeId() -> String {
        if let last = UserDefaults.standard.string(forKey: Self.lastTypeKey),
           appState.schema.type(id: last) != nil {
            return last
        }
        return visibleTypes.first?.id ?? ""
    }

    private func save() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let type = selectedType else { return }

        let key = type.primaryFieldKey
            ?? type.fields.first(where: { $0.kind == .text || $0.kind == .longText })?.key
            ?? type.fields.first?.key
        guard let key else { return }

        do {
            _ = try ObjectEngine.create(typeId: type.id, fields: [key: trimmed])
            UserDefaults.standard.set(type.id, forKey: Self.lastTypeKey)
            appState.reloadAll()
            statusMessage = "Saved to \(type.pluralName)"
            titleText = ""
            // Status fades after a beat so subsequent saves get fresh
            // visual feedback rather than the last message lingering.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if statusMessage?.hasPrefix("Saved") == true {
                    statusMessage = nil
                }
            }
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func close() {
        titleText = ""
        statusMessage = nil
        // MenuBarExtra dismisses the popover automatically when its
        // status item is clicked again; explicit dismissal from inside
        // the view requires asking the system status item to toggle.
        // Send a key event for Esc — the native MenuBarExtra
        // .window-style popover treats Esc as dismiss.
        NSApp.keyWindow?.performClose(nil)
    }
}

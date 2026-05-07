import SwiftUI

struct FontsSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Customize fonts for each part of the timeline. Reset reverts to the slot's default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(FontSlot.allCases, id: \.self) { slot in
                Section(slot.label) {
                    FontSlotEditor(slot: slot)
                        .environmentObject(appState)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FontSlotEditor: View {
    @EnvironmentObject private var appState: AppState
    let slot: FontSlot

    private var current: FontStyle {
        appState.settings.fontSlots[slot.rawValue] ?? slot.defaultStyle
    }

    private static let familyOptions: [(token: String, label: String)] = [
        ("system",          "System"),
        ("system-rounded",  "System Rounded"),
        ("system-mono",     "System Mono"),
        ("system-serif",    "System Serif"),
        ("Menlo",           "Menlo"),
        ("Monaco",          "Monaco"),
        ("SF Mono",         "SF Mono"),
        ("Courier New",     "Courier New"),
        ("Helvetica Neue",  "Helvetica Neue"),
        ("Georgia",         "Georgia"),
    ]

    private static let weightOptions: [(String, String)] = [
        ("regular",  "Regular"),
        ("medium",   "Medium"),
        ("semibold", "Semibold"),
        ("bold",     "Bold"),
        ("heavy",    "Heavy"),
    ]

    var body: some View {
        Picker("Family", selection: bind(\.family)) {
            ForEach(Self.familyOptions, id: \.token) { opt in
                Text(opt.label).tag(opt.token)
            }
        }

        Picker("Weight", selection: bind(\.weight)) {
            ForEach(Self.weightOptions, id: \.0) { opt in
                Text(opt.1).tag(opt.0)
            }
        }

        Slider(value: bind(\.size), in: 9...22, step: 1) {
            Text("Size: \(Int(current.size)) pt")
        } minimumValueLabel: { Text("9") } maximumValueLabel: { Text("22") }

        // Live sample at the chosen size/weight/family
        HStack(spacing: 12) {
            Text("Sample —")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(slot == .eventDate ? "12 Jun 1994 · 10:32 AM" : "Sample event title")
                .font(current.swiftUIFont())
        }

        HStack {
            Spacer()
            Button("Reset to default") {
                var s = appState.settings
                s.fontSlots.removeValue(forKey: slot.rawValue)
                appState.settings = s
            }
            .controlSize(.small)
        }
    }

    private func bind<T: Equatable>(_ keyPath: WritableKeyPath<FontStyle, T>) -> Binding<T> {
        Binding(
            get: { current[keyPath: keyPath] },
            set: { newValue in
                var s = appState.settings
                var slotStyle = current
                slotStyle[keyPath: keyPath] = newValue
                s.fontSlots[slot.rawValue] = slotStyle
                appState.settings = s
            }
        )
    }
}

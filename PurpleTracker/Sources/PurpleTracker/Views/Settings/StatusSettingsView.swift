import SwiftUI

struct StatusSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var draft: [String] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status Lifecycle").font(.headline)
            Text("First value is the start state for new Matters. The second value is the auto-bump target the first time a timer runs. The last value is the terminal state that closes a Matter (and spawns the next instance for cadenced types).")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(draft.enumerated()), id: \.offset) { idx, name in
                    HStack {
                        Text("\(idx + 1).").foregroundStyle(.secondary).frame(width: 24)
                        TextField("", text: Binding(
                            get: { draft[idx] },
                            set: { draft[idx] = $0 }
                        )).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { draft.remove(at: idx) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.plain)
                    }
                }
                .onMove { src, dst in draft.move(fromOffsets: src, toOffset: dst) }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Add Status") { draft.append("New Status") }
                Spacer()
                Button("Reset to Default") {
                    draft = MatterStatus.defaultLifecycle.map(\.rawValue)
                }
                Button("Save") {
                    let values = draft.enumerated().map { ($0.offset, $0.element) }
                        .map { (name: $0.1, sortOrder: $0.0) }
                    try? app.saveStatusValues(values)
                }
                .keyboardShortcut(.return)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = app.statusValues.map(\.name)
            loaded = true
        }
    }
}

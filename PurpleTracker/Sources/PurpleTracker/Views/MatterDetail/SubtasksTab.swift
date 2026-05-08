import SwiftUI

/// Lightweight checklist attached to a Matter. Useful for breaking down work
/// without spinning up a full child Matter. Counts roll up to the row badge.
struct SubtasksTab: View {
    let matter: Matter
    @EnvironmentObject var app: AppState
    @State private var newBody: String = ""

    private var items: [Subtask] {
        app.subtasksByMatter[matter.id] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Add a subtask…", text: $newBody, onCommit: add)
                    .textFieldStyle(.roundedBorder)
                Button("Add", action: add)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(newBody.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if items.isEmpty {
                ContentUnavailableView("No subtasks yet", systemImage: "checklist",
                    description: Text("Use these to break a Matter into a checklist."))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical)
            } else {
                ForEach(items) { s in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { s.done },
                            set: { _ in try? app.toggleSubtask(s) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        TextField("", text: Binding(
                            get: { s.body },
                            set: { newVal in
                                var x = s; x.body = newVal
                                try? app.updateSubtask(x)
                            }
                        ))
                        .textFieldStyle(.plain)
                        .strikethrough(s.done, color: .secondary)
                        .foregroundStyle(s.done ? .secondary : .primary)

                        Button(role: .destructive) {
                            try? app.deleteSubtask(s)
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                let counts = app.subtaskCounts[matter.id] ?? (done: 0, total: 0)
                Text("\(counts.done) / \(counts.total) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        let trimmed = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? app.addSubtask(matterId: matter.id, body: trimmed)
        newBody = ""
    }
}

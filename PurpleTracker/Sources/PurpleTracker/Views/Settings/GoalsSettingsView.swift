import SwiftUI

/// Configurable list of team/business Goals a Matter can be tagged with.
struct GoalsSettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Goals").font(.headline)
                Spacer()
                Button {
                    let new = Goal(
                        id: UUID().uuidString,
                        name: "New Goal",
                        sortOrder: (app.goals.map(\.sortOrder).max() ?? 0) + 1
                    )
                    try? app.saveGoal(new)
                } label: { Label("Add", systemImage: "plus") }
            }
            Text("Tag Matters with one or more goals. Manage on the Matter's Overview tab.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                ForEach(app.goals) { g in
                    GoalRow(goal: g)
                    Divider()
                }
            }
        }
    }
}

private struct GoalRow: View {
    let goal: Goal
    @EnvironmentObject var app: AppState
    @State private var name: String = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Image(systemName: "target")
                .foregroundStyle(.purple)
                .frame(width: 20)
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    var g = goal; g.name = name; try? app.saveGoal(g)
                }
            Button(role: .destructive) {
                try? app.deleteGoal(id: goal.id)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Remove this goal. Existing tags on Matters are also removed.")
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !loaded else { return }
            name = goal.name
            loaded = true
        }
    }
}

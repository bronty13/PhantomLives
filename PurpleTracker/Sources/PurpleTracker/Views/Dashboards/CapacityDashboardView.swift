import SwiftUI
import Charts

/// Open-Matter capacity per person — counts how many active Matters each
/// Requestor has so you can spot bottlenecks across the team.
struct CapacityDashboardView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Open Matters per Requestor")
                    .font(.headline)

                if rows.isEmpty {
                    ContentUnavailableView("No open Matters with a Requestor yet",
                                           systemImage: "person.3",
                                           description: Text("Assign a Requestor on a Matter's Overview tab to populate this view."))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Chart(rows, id: \.name) { row in
                        BarMark(x: .value("Count", row.count),
                                y: .value("Person", row.name))
                            .foregroundStyle(.purple)
                    }
                    .frame(height: max(220, CGFloat(rows.count) * 26))
                }
            }
            .padding()
        }
        .navigationTitle("Capacity")
    }

    private struct Row { let name: String; let count: Int }
    private var rows: [Row] {
        let terminal = app.statusValues.last?.name ?? "Closed"
        let people = app.peopleById
        var bucket: [String: Int] = [:]
        for m in app.matters where m.status != terminal {
            guard !m.requestorAssociateId.isEmpty,
                  let p = people[m.requestorAssociateId] else { continue }
            bucket[p.displayName, default: 0] += 1
        }
        return bucket.map { Row(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

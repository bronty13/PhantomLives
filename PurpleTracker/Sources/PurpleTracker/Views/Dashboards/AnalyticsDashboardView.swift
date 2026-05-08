import SwiftUI
import Charts

/// Matter-level analytics: open vs closed counts, by type, by priority,
/// and by initiative. Pure in-memory aggregation over `app.matters`.
struct AnalyticsDashboardView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("\(app.matters.count) total Matters · \(open.count) open · \(closed.count) closed",
                      systemImage: "chart.pie.fill")
                    .font(.title3.weight(.semibold))

                Text("Open Matters by Type").font(.headline)
                Chart(byType, id: \.name) { row in
                    BarMark(x: .value("Count", row.count),
                            y: .value("Type", row.name))
                    .foregroundStyle(by: .value("Type", row.name))
                }
                .frame(height: max(180, CGFloat(byType.count) * 28))

                Text("Open Matters by Priority").font(.headline)
                Chart(byPriority, id: \.name) { row in
                    BarMark(x: .value("Priority", row.name),
                            y: .value("Count", row.count))
                    .foregroundStyle(by: .value("Priority", row.name))
                }
                .frame(height: 220)

                if !byInitiative.isEmpty {
                    Text("Open Matters by Initiative").font(.headline)
                    Chart(byInitiative, id: \.name) { row in
                        BarMark(x: .value("Count", row.count),
                                y: .value("Initiative", row.name))
                        .foregroundStyle(.purple)
                    }
                    .frame(height: max(180, CGFloat(byInitiative.count) * 28))
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
    }

    private var open: [Matter] {
        let terminal = app.statusValues.last?.name ?? "Closed"
        return app.matters.filter { $0.status != terminal }
    }
    private var closed: [Matter] {
        let terminal = app.statusValues.last?.name ?? "Closed"
        return app.matters.filter { $0.status == terminal }
    }

    private struct Row { let name: String; let count: Int }

    private var byType: [Row] {
        let typesById = app.typesById
        var b: [String: Int] = [:]
        for m in open { b[typesById[m.typeId]?.name ?? "—", default: 0] += 1 }
        return b.map { Row(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
    private var byPriority: [Row] {
        var b: [String: Int] = [:]
        for m in open { b[MatterPriority.parse(m.priority).shortTag, default: 0] += 1 }
        return MatterPriority.allCases.map { Row(name: $0.shortTag, count: b[$0.shortTag] ?? 0) }
    }
    private var byInitiative: [Row] {
        let names = Dictionary(uniqueKeysWithValues: app.initiatives.map { ($0.id, $0.name) })
        var b: [String: Int] = [:]
        for m in open {
            let ids = app.matterInitiativeIds[m.id] ?? []
            for id in ids { b[names[id] ?? id, default: 0] += 1 }
        }
        return b.map { Row(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}

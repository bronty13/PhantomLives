import SwiftUI

/// Today / Planner — Phase 3 starter.
///
/// Acceptance gate per `PLAN.md`: the Today view assembles its content
/// by querying the object engine, with **no hard-coded modules**. The
/// implementation here is one generic `QueryPanel` repeated over the
/// user's `SavedQuery` list — adding a new panel is data, not code.
struct TodayScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var openingRecordId: String?
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(appState.settingsStore.settings.todayQueries) { query in
                    QueryPanel(query: query, onOpen: { openingRecordId = $0 })
                }
                if appState.settingsStore.settings.todayQueries.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit panels", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SavedQueriesEditor()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { openingRecordId != nil },
            set: { if !$0 { openingRecordId = nil } }
        )) {
            if let id = openingRecordId {
                ObjectDetailSheet(recordId: id, onChange: { appState.reloadAll() })
                    .environmentObject(appState)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title2.weight(.semibold))
            Text("\(appState.objectCount) object\(appState.objectCount == 1 ? "" : "s") across \(appState.schema.visibleTypes.count) type\(appState.schema.visibleTypes.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No saved queries yet.")
                .font(.headline).foregroundStyle(.secondary)
            Text("Today panels are driven by saved queries. Customization UI is queued.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }
}

/// One panel = one `SavedQuery`. The Today view repeats this without
/// branching on query content; that's what keeps the screen "no
/// hard-coded modules".
private struct QueryPanel: View {
    @EnvironmentObject private var appState: AppState
    let query: SavedQuery
    var onOpen: (String) -> Void

    var body: some View {
        let results = QueryRunner.run(query, schema: appState.schema)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: query.systemImage)
                    .foregroundStyle(.tint)
                Text(query.name)
                    .font(.headline)
                Text("\(results.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let typeId = query.typeId {
                    Button {
                        appState.selectedTypeId = typeId
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            if results.isEmpty {
                Text("Nothing matches yet.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                cardGrid(results: results)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cardGrid(results: [(record: ObjectRecord, type: ObjectType)]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(results, id: \.record.id) { item in
                resultCard(record: item.record, type: item.type)
                    .onTapGesture(count: 2) { onOpen(item.record.id) }
            }
        }
    }

    private func resultCard(record: ObjectRecord, type: ObjectType) -> some View {
        let supporting = type.fields
            .filter { $0.key != type.primaryFieldKey && $0.kind != .longText && $0.kind != .attachment }
            .prefix(2)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
                    .imageScale(.small)
                Text(type.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            Text(FieldDisplay.title(of: record, in: type))
                .font(.body.weight(.semibold))
                .lineLimit(2)
            ForEach(Array(supporting), id: \.id) { field in
                HStack(spacing: 4) {
                    Text(field.name)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    FieldDisplay.cell(field: field, value: record.fields()[field.key])
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

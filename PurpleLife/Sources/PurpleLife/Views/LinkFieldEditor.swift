import SwiftUI

/// Cross-type link picker. Replaces the plain TextField that the Phase 2
/// starter used for `.link` fields in `Detail.swift`. Stores the linked
/// record's id (UUID string) as the field value; the read views resolve
/// the id back to a title via `ObjectEngine.resolveLinkedTitle(_:)`.
struct LinkFieldEditor: View {
    @EnvironmentObject private var appState: AppState
    @Binding var value: String

    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                if value.isEmpty {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Link a record…").foregroundStyle(.secondary)
                } else if let title = ObjectEngine.resolveLinkedTitle(recordId: value) {
                    Image(systemName: "link").foregroundStyle(.tint)
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                } else {
                    Image(systemName: "link.badge.questionmark")
                        .foregroundStyle(.orange)
                    Text(value).font(.body.italic()).foregroundStyle(.orange).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !value.isEmpty {
                    Button {
                        value = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the link")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .top) {
            LinkPicker(currentValue: value) { picked in
                value = picked ?? ""
                showingPicker = false
            }
            .environmentObject(appState)
        }
    }
}

private struct LinkPicker: View {
    @EnvironmentObject private var appState: AppState
    let currentValue: String
    /// Called with the picked record id, or `nil` when the user clears.
    var onPick: (String?) -> Void

    @State private var query: String = ""
    @State private var allRecords: [(ObjectRecord, ObjectType)] = []
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search every type…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                resultList
            }

            if !currentValue.isEmpty {
                Divider()
                Button {
                    onPick(nil)
                } label: {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Clear link").bold()
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 360, height: 360)
        .onAppear {
            queryFocused = true
            do {
                allRecords = try ObjectEngine.allWithTypes(schema: appState.schema)
            } catch {
                NSLog("PurpleLife: link picker load failed — \(error.localizedDescription)")
            }
        }
    }

    private var filtered: [(ObjectRecord, ObjectType)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return allRecords }
        return allRecords.filter { (record, type) in
            let title = FieldDisplay.title(of: record, in: type).lowercased()
            return title.contains(trimmed) || type.name.lowercased().contains(trimmed)
        }
    }

    private var grouped: [(type: ObjectType, items: [ObjectRecord])] {
        var byType: [String: (ObjectType, [ObjectRecord])] = [:]
        for (r, t) in filtered {
            byType[t.id, default: (t, [])].1.append(r)
        }
        // Stable order: alphabetical by type name.
        return byType.values.sorted { $0.0.name < $1.0.name }.map { (type: $0.0, items: $0.1) }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Text(allRecords.isEmpty ? "No records yet." : "No matches for \"\(query)\".")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.type.id) { group in
                    Section {
                        ForEach(group.items) { record in
                            row(record: record, type: group.type)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: group.type.systemImage)
                                .foregroundStyle(Color(hex: group.type.colorHex) ?? .accentColor)
                                .imageScale(.small)
                            Text(group.type.pluralName.uppercased())
                                .font(.caption.weight(.semibold))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.regularMaterial)
                    }
                }
            }
        }
    }

    private func row(record: ObjectRecord, type: ObjectType) -> some View {
        Button {
            onPick(record.id)
        } label: {
            HStack(spacing: 8) {
                Text(FieldDisplay.title(of: record, in: type))
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if record.id == currentValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(record.id == currentValue ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}

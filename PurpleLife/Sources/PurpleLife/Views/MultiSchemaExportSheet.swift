import SwiftUI

/// Multi-select sheet for exporting a subset of schema types into a
/// single `.purplelifeschema.json` bundle. Presented from the Schema
/// Editor's "Export multiple…" menu item. The single-item "Export
/// <Type>…" path and the "Export all…" path don't need this surface —
/// they call `exportTypes(ids:)` directly with the relevant ids.
struct MultiSchemaExportSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: Set<String>
    var onExport: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Export schemas").font(.title3.weight(.semibold))
                    Text("Pick the types to include in a single export file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider()

            HStack {
                Button("Select all") {
                    selection = Set(appState.schema.types.map(\.id))
                }
                Button("None") {
                    selection.removeAll()
                }
                Spacer()
                Text("\(selection.count) of \(appState.schema.types.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.schema.types) { type in
                        row(for: type)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 300)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onExport(Array(selection))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 480)
    }

    private func row(for type: ObjectType) -> some View {
        let isOn = selection.contains(type.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { selection.insert(type.id) }
                    else { selection.remove(type.id) }
                }
            ))
            .labelsHidden()
            Image(systemName: type.systemImage)
                .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(type.pluralName).font(.body)
                HStack(spacing: 6) {
                    Text(type.builtIn ? "built-in" : "custom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(type.fields.count) field\(type.fields.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOn { selection.remove(type.id) }
            else { selection.insert(type.id) }
        }
    }
}

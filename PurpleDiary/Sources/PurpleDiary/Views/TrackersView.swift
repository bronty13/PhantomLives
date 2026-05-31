import SwiftUI

/// Define the quantified metrics you want to track per entry (water, sleep,
/// steps, "did I exercise?"). Each tracker has a name, a kind (number /
/// duration / yes-no), an optional unit (for numbers), and a color used in the
/// Insights graphs. Deleting a tracker cascades its logged values but leaves
/// your entries untouched. Mirrors `TagsView`'s management pattern.
struct TrackersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var newName: String = ""
    @State private var newUnit: String = ""
    @State private var newKind: TrackerKind = .number
    @State private var newColor: Color = .purple

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addRow
            Divider()
            if appState.trackerTags.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(appState.trackerTags) { tracker in
                        TrackerRow(tracker: tracker)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Trackers")
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ColorPicker("", selection: $newColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36)
                TextField("Add a tracker… (e.g. Water, Sleep, Exercise)", text: $newName)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
            }
            HStack(spacing: 10) {
                Picker("Kind", selection: $newKind) {
                    ForEach(TrackerKind.allCases, id: \.self) { k in
                        Label(k.label, systemImage: k.systemImage).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)

                if newKind == .number {
                    TextField("unit (optional)", text: $newUnit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                Spacer()
                Button("Add", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No trackers yet. Define a metric — like cups of water or hours of sleep — then log it on each entry and watch the trend in Insights.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let hex = newColor.toHex() ?? "#7C5CFF"
        let unit = newKind == .number ? newUnit.trimmingCharacters(in: .whitespaces) : ""
        try? appState.saveTrackerTag(
            TrackerTag(rowId: nil, name: name, unit: unit, kind: newKind, colorHex: hex)
        )
        newName = ""
        newUnit = ""
    }
}

private struct TrackerRow: View {
    @EnvironmentObject private var appState: AppState
    let tracker: TrackerTag
    @State private var color: Color = .gray
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36)
                .onChange(of: color) { _, newValue in
                    guard loaded else { return }
                    var t = tracker
                    t.colorHex = newValue.toHex() ?? tracker.colorHex
                    try? appState.saveTrackerTag(t)
                }
            Image(systemName: tracker.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(tracker.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                if let rid = tracker.rowId { try? appState.deleteTrackerTag(id: rid) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            color = Color(hex: tracker.colorHex) ?? .gray
            loaded = true
        }
    }

    private var subtitle: String {
        switch tracker.kind {
        case .number:   return tracker.unit.isEmpty ? "Number" : "Number · \(tracker.unit)"
        case .duration: return "Duration"
        case .boolean:  return "Yes / No"
        }
    }
}

import SwiftUI

struct MarkersListView: View {
    @EnvironmentObject var appState: AppState
    let fps: Double
    let onJumpTo: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Markers").font(.headline)
                Spacer()
                Text("\(appState.markers.count)")
                    .foregroundStyle(.secondary).font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if appState.markers.isEmpty {
                Text("No markers yet. Press M during playback.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(8)
            } else {
                List(appState.markers) { marker in
                    HStack(spacing: 8) {
                        Text(Timecode.format(seconds: marker.timecodeIn, fps: fps))
                            .font(.system(.caption, design: .monospaced))
                            .onTapGesture { onJumpTo(marker.timecodeIn) }
                            .help("Jump to \(Timecode.format(seconds: marker.timecodeIn, fps: fps))")
                        TextField("Note", text: binding(for: marker))
                            .textFieldStyle(.plain)
                            .font(.caption)
                        Button {
                            appState.deleteMarker(marker)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func binding(for marker: Marker) -> Binding<String> {
        Binding<String>(
            get: { marker.note ?? "" },
            set: { newValue in appState.updateMarkerNote(marker, note: newValue) }
        )
    }
}

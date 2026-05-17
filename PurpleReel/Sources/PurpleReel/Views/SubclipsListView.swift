import SwiftUI

struct SubclipsListView: View {
    @EnvironmentObject var appState: AppState
    let fps: Double
    let onJumpTo: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Subclips").font(.headline)
                Spacer()
                Text("\(appState.subclips.count)")
                    .foregroundStyle(.secondary).font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if appState.subclips.isEmpty {
                Text("Mark in/out (I/O) then press S to save a subclip.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(8)
            } else {
                List(appState.subclips) { clip in
                    HStack(spacing: 8) {
                        Text(clip.name).font(.caption)
                        Spacer()
                        Text(Timecode.format(seconds: clip.timecodeIn, fps: fps))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .onTapGesture { onJumpTo(clip.timecodeIn) }
                        Text("→")
                            .foregroundStyle(.secondary).font(.caption2)
                        Text(Timecode.format(seconds: clip.timecodeOut, fps: fps))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .onTapGesture { onJumpTo(clip.timecodeOut) }
                        Button {
                            appState.deleteSubclip(clip)
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
}

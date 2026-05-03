import SwiftUI

/// Right-hand pane that displays the editable form for the selected clip.
/// Loads fresh from `appState.clips` on selection change so external edits
/// (rename / posting toggle) don't get clobbered.
struct ClipDetailView: View {
    @EnvironmentObject private var appState: AppState
    let clipId: Clip.ID?

    var body: some View {
        Group {
            if let id = clipId, let clip = appState.clips.first(where: { $0.id == id }) {
                ClipEditView(clip: clip)
                    .id(id)   // force a fresh edit state per clip
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            Text("No clip selected")
                .font(.headline)
            Text("Pick a clip on the left, or use ⌘N to create a new one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

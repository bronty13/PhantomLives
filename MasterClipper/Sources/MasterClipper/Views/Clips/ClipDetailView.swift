import SwiftUI
import MasterClipperCore

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
        VStack(spacing: 14) {
            EdEyebrow(text: "Editor", withRule: false)
            Text("Pick a clip.")
                .font(EdFont.serif(28, weight: .bold))
            Text("Select a clip on the left or press ⌘N to create a new one.")
                .font(EdFont.serif(15, weight: .light, italic: true))
                .foregroundStyle(EdColor.ink(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EdColor.bone)
    }
}

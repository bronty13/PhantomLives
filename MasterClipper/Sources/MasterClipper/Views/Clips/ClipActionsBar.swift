import SwiftUI
import MasterClipperCore

/// Standard top-right action bar for any view that shows a selectable clip
/// (Clips, Editing queue, Posting queue): New / Workflow / Export / Delete.
/// Owns its sheets and confirm-alert so a host view only has to supply the
/// current selection and a callback for selection changes after create/delete.
struct ClipActionsBar: View {
    @EnvironmentObject private var appState: AppState

    let selectedClip: Clip?
    let onSelectionChanged: (String?) -> Void

    @State private var showingNewSheet: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var workflowClip: Clip? = nil
    @State private var exportingClip: Clip? = nil
    @State private var postingClip: Clip? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { showingNewSheet = true } label: { Text("⌘ N · NEW") }
                .buttonStyle(EdInkPillButtonStyle())
            Button {
                if let clip = selectedClip { workflowClip = clip }
            } label: { Text("WORKFLOW") }
                .buttonStyle(EdGhostButtonStyle())
                .disabled(selectedClip == nil)
                .help("Run the file audit and capture editing notes (appended to clip notes)")
            Button {
                if let clip = selectedClip { postingClip = clip }
            } label: { Text("POST") }
                .buttonStyle(EdGhostButtonStyle())
                .disabled(selectedClip == nil)
                .help("Post this clip to one of its scoped sites — pick a site, then run the focused posting window.")
            Button {
                if let clip = selectedClip { exportingClip = clip }
            } label: { Text("EXPORT") }
                .buttonStyle(EdGhostButtonStyle())
                .disabled(selectedClip == nil)
            Button(role: .destructive) { showingDeleteConfirm = true } label: { Text("DELETE") }
                .buttonStyle(EdGhostButtonStyle())
                .disabled(selectedClip == nil)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Delete the selected clip (⌘⌫)")
        }
        .alert("Delete this clip?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let clip = selectedClip { deleteClip(clip) }
            }
        } message: {
            if let clip = selectedClip {
                let titleText = clip.title.isEmpty ? clip.id : "\"\(clip.title)\""
                Text("\(titleText) and all its postings, category links, and history will be permanently deleted. This cannot be undone — restore from a backup if you change your mind.")
            } else {
                Text("This clip and all its associated data will be permanently deleted. This cannot be undone.")
            }
        }
        .sheet(item: $exportingClip) { clip in
            ClipExportSheet(clip: clip) { exportingClip = nil }
                .environmentObject(appState)
        }
        .sheet(item: $postingClip) { clip in
            SingleClipPostingFlow(clip: clip) { postingClip = nil }
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingNewSheet) {
            ClipWorkflowView(
                onCompleted: { newClip in
                    onSelectionChanged(newClip.id)
                    showingNewSheet = false
                },
                onContinueToEditing: { newClip in
                    onSelectionChanged(newClip.id)
                    showingNewSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        workflowClip = newClip
                    }
                },
                onCancel: { showingNewSheet = false }
            )
            .environmentObject(appState)
        }
        .sheet(item: $workflowClip) { clip in
            EditingWorkflowView(clipId: clip.id) {
                workflowClip = nil
            }
            .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newClipRequested)) { _ in
            showingNewSheet = true
        }
    }

    private func deleteClip(_ clip: Clip) {
        do {
            try appState.deleteClip(id: clip.id)
            onSelectionChanged(nil)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

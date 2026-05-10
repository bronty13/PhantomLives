import SwiftUI
import PurpleDedupCore

/// Auth-banner shown beneath the Sources list when at least one Apple
/// Photos library is in the scan sources. Adapts its content to the
/// current auth state — granted (success copy + scan reminder), denied
/// (recovery flow with `tccutil reset` + Open Settings buttons), or
/// not-yet-determined (Grant Photos access prompt).
///
/// State + actions flow from `ContentView` via closures; this view
/// stays a pure renderer so it can be reused in the inline filter
/// editor's "needs auth" state too if needed later.
struct PhotosLibraryHint: View {
    let anyUnlocked: Bool
    let authStatus: PhotoKitDeletionService.Authorization
    let onRequestAccess: () async -> Void
    let onResetPermission: () async -> Void
    let onOpenPrivacySettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                if anyUnlocked {
                    Text("Photos library: action queued in Photos.app.")
                        .font(.caption.bold())
                    Text("Files you mark DELETE will land in the \"Marked for Deletion in PurpleDedup\" album. Open Photos.app and delete from that album to finalise.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("PurpleDedup needs Photos access.")
                        .font(.caption.bold())
                    Text(authHintMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            Task { await onRequestAccess() }
                        } label: {
                            Label("Grant Photos access", systemImage: "checkmark.shield")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.purple)
                        if authStatus == .denied || authStatus == .restricted {
                            Button {
                                Task { await onResetPermission() }
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Run tccutil reset Photos to clear any stale denial — needed when the app doesn't appear in Privacy Settings.")
                            Button {
                                onOpenPrivacySettings()
                            } label: {
                                Label("Settings", systemImage: "gear")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(8)
        // Vibrancy material + a subtle purple-tinted stroke. Plain
        // Color.purple.opacity(0.08) was nearly invisible in dark mode and
        // pure-flat in light mode; .thinMaterial picks up the desktop and
        // the accent overlay tints it without going saturated.
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.top, 4)
    }

    /// Body copy for the auth banner. Computed instead of inline so the
    /// SwiftUI body stays small — the bigger inline switch was making
    /// layout misbehave on Tahoe.
    private var authHintMessage: String {
        switch authStatus {
        case .notDetermined:
            return "Click Grant Photos access — macOS will show its prompt. Without it, your Photos library is treated as read-only."
        case .denied, .restricted:
            return "Photos access was denied — and PurpleDedup may not even appear in System Settings → Privacy → Photos yet (the OS records a deny before the entry is created). Click Reset below to clear the stale record, then Grant to get the system prompt."
        case .authorized, .limited:
            return "Granted — re-scan to populate clusters with Photos library data."
        }
    }
}

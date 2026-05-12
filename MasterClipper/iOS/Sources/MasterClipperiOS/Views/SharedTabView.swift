import SwiftUI
import MasterClipperCore

/// Top-level tab visible when the user has accepted at least one CKShare
/// from someone else's MasterClipper Mac. Shows each accepted share as a
/// section, with the clips inside.
struct SharedTabView: View {
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Shared with me")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if appState.sharedReader.isWorking {
                            ProgressView()
                        } else {
                            Button {
                                Task { await appState.sharedReader.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh shares")
                        }
                    }
                }
                .navigationDestination(for: SharedClipNavTarget.self) { target in
                    SharedClipDetailView(target: target)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.sharedReader.sessions.isEmpty {
            emptyState
        } else {
            List {
                ForEach(appState.sharedReader.sessions) { session in
                    Section {
                        ForEach(session.clips) { clip in
                            NavigationLink(value: SharedClipNavTarget(sessionId: session.id, clipId: clip.id)) {
                                SharedClipRowView(clip: clip)
                            }
                        }
                        if session.clips.isEmpty {
                            Text("(no clips in this share)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        sessionHeader(session)
                    }
                }

                if let err = appState.sharedReader.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No shares accepted")
                .font(.headline)
            Text("When someone shares clips from their Mac, the link opens this app and the share appears here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionHeader(_ session: SharedShareSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.metadata.label ?? "Untitled share")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 8) {
                    Label(session.metadata.permission.label,
                          systemImage: session.metadata.permission == .readOnly ? "eye" : "pencil")
                    Text("•")
                    Text(timeRemaining(session.metadata.expiresAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(session.clips.count)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func timeRemaining(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "expired" }
        let hours = Int(interval / 3600)
        if hours > 48 { return "\(hours / 24)d left" }
        if hours > 1  { return "\(hours)h left" }
        return "<1h left"
    }
}

/// Navigation token so the destination view can look up the session + clip
/// without holding view-binding references.
struct SharedClipNavTarget: Hashable {
    let sessionId: UUID
    let clipId: String
}

struct SharedClipRowView: View {
    let clip: SharedClipRow

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title.isEmpty ? clip.id : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(clip.personaCode)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.gray.opacity(0.2), in: Capsule())

                    Label(clip.statusEnum.label, systemImage: clip.statusEnum.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(clip.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = clip.thumbnailLocalURL,
           FileManager.default.fileExists(atPath: url.path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.gray.opacity(0.12)
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
    }
}

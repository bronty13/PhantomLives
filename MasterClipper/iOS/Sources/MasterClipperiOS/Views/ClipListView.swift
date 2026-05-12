import SwiftUI
import MasterClipperCore

struct ClipListView: View {
    @EnvironmentObject private var appState: iOSAppState
    @State private var showingFilters = false

    var body: some View {
        let _ = print("[ClipListView] render — manifest=\(appState.snapshotReader.manifest != nil ? "present" : "nil") clips=\(appState.clips.count) filtered=\(appState.filteredClips.count) loading=\(appState.snapshotReader.isLoading) error=\(appState.snapshotReader.lastError ?? "—")")
        List {
            if appState.snapshotReader.manifest == nil {
                emptyState
            } else if appState.filteredClips.isEmpty {
                noResults
            } else {
                ForEach(appState.filteredClips) { clip in
                    NavigationLink(value: clip.id) {
                        ClipRow(clip: clip)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $appState.searchText, prompt: "Search clips")
        .navigationTitle("Clips")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
            ToolbarItem(placement: .topBarLeading) {
                if appState.snapshotReader.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await appState.snapshotReader.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload snapshot")
                }
            }
        }
        .navigationDestination(for: String.self) { clipId in
            ClipDetailView(clipId: clipId)
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet()
        }
        .overlay(alignment: .bottom) {
            if let err = appState.snapshotReader.lastError ?? appState.loadError {
                errorBanner(err)
            }
        }
    }

    private var hasActiveFilter: Bool {
        appState.personaFilter != nil || appState.statusFilter != nil
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No snapshot yet")
                .font(.headline)
            Text("Open MasterClipper on your Mac and tap **Publish now** in Settings → Sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowSeparator(.hidden)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No matching clips")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.9))
            .padding(.horizontal)
            .padding(.bottom, 8)
    }
}

private struct ClipRow: View {
    let clip: Clip
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(clipId: clip.id)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title.isEmpty ? clip.id : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let p = appState.persona(code: clip.personaCode) {
                        PersonaBadge(persona: p)
                    } else {
                        Text(clip.personaCode)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.gray.opacity(0.2), in: Capsule())
                    }

                    StatusBadge(status: clip.statusEnum)

                    if appState.outbox.hasPending(forClip: clip.id) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Has pending sync")
                    }

                    Spacer()

                    Text(clip.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ThumbnailView: View {
    let clipId: String
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        if let url = appState.snapshotReader.thumbnailURL(for: clipId),
           FileManager.default.fileExists(atPath: url.path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.gray.opacity(0.12)
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PersonaBadge: View {
    let persona: Persona

    var body: some View {
        Text(persona.code)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(personaColor.opacity(0.2), in: Capsule())
            .foregroundStyle(personaColor)
    }

    private var personaColor: Color {
        Color(hex: persona.colorHex) ?? .accentColor
    }
}

struct StatusBadge: View {
    let status: ClipStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption2)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Color hex parsing (mirrors macOS Shared/EditorialTheme helper)

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >>  8) & 0xFF) / 255.0
        let b = Double( value        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

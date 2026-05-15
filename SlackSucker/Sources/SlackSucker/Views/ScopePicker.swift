import SwiftUI

/// Lets the user pick what to archive: the whole workspace, a single
/// channel / DM (chosen via the cached entity list), or a thread URL.
struct ScopePicker: View {
    @EnvironmentObject var channels: ChannelService
    @EnvironmentObject var settings: SettingsStore
    @Binding var scope: ArchiveScope

    @State private var mode: Mode = .entire
    @State private var entityQuery: String = ""
    @State private var threadURL: String = ""

    enum Mode: String, CaseIterable, Identifiable {
        case entire, conversation, thread
        var id: String { rawValue }
        var label: String {
            switch self {
            case .entire:       return "Entire workspace"
            case .conversation: return "Channel / DM"
            case .thread:       return "Thread URL"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT TO ARCHIVE")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, newMode in
                syncScope()
                // First-time switch into the conversation picker should
                // auto-fetch if we have nothing cached yet — otherwise
                // the user sees an empty dropdown with no indication
                // that they need to click Refresh.
                if newMode == .conversation, channels.entities.isEmpty, !channels.isLoading {
                    Task { await channels.refresh(for: settings.selectedWorkspace) }
                }
            }
            switch mode {
            case .entire:
                Text("Slackdump will pull every conversation your token can access.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(.secondary)
            case .conversation:
                ChannelCombobox(query: $entityQuery,
                                onPick: { entity in
                                    let label = entity.subtitle.map { "\(entity.name) — \($0)" } ?? entity.name
                                    if entity.kind == .user {
                                        scope = .dm(idOrURL: entity.id, displayName: entity.name)
                                    } else if entity.kind == .dm || entity.kind == .mpdm {
                                        scope = .dm(idOrURL: entity.id, displayName: entity.name)
                                    } else {
                                        scope = .channel(idOrURL: entity.id, displayName: entity.name)
                                    }
                                    entityQuery = label
                                })
                    .environmentObject(channels)
                HStack {
                    Button {
                        Task { await channels.refresh(for: settings.selectedWorkspace) }
                    } label: {
                        if channels.isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Loading…")
                                    .font(AppFont.sans(11))
                            }
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(channels.isLoading)
                    if channels.isLoading {
                        // Surface what's happening since `list channels` /
                        // `list users` can take a few seconds on first
                        // run against a large workspace.
                        Text("Fetching channels + users from Slack")
                            .font(AppFont.sans(11))
                            .foregroundStyle(.secondary)
                    } else if let ts = channels.cacheTimestamp {
                        Text("\(channels.entities.count) entries · cached \(RelativeTime.short(ts))")
                            .font(AppFont.sans(11))
                            .foregroundStyle(.tertiary)
                    } else if channels.entities.isEmpty {
                        Text("No cache yet — click Refresh to load")
                            .font(AppFont.sans(11))
                            .foregroundStyle(.tertiary)
                    }
                    if let err = channels.lastError {
                        Spacer()
                        Text(err)
                            .font(AppFont.sans(11))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            case .thread:
                TextField("https://your.slack.com/archives/CXXXXX/p1700000000123456",
                          text: $threadURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: threadURL) { _, _ in syncScope() }
            }
        }
    }

    private func syncScope() {
        switch mode {
        case .entire:
            scope = .entireWorkspace
        case .conversation:
            // Leave as whatever the user picked; if nothing picked yet,
            // collapse to entireWorkspace so a hasty Run doesn't blow up.
            if case .entireWorkspace = scope {} else { /* keep */ }
        case .thread:
            scope = threadURL.isEmpty
                ? .entireWorkspace
                : .threadURL(threadURL)
        }
    }
}

import SwiftUI

/// Channels currently in common with the selected contact, broken down
/// by network. Walks every live `IRCConnection`'s channel buffers and
/// checks whether any of the contact's linked nicks appears in the
/// user list.
struct ContactSharedChannelsSection: View {
    let entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    /// Cached result of the per-connection × per-buffer × per-user scan.
    /// Computing this inside `body` meant every keystroke in the contact
    /// editor walked every user list of every joined channel on every
    /// network. Refreshes on selection / nick-binding changes instead;
    /// channel membership churn between refreshes is invisible at the
    /// cadence this section is read.
    @State private var groups: [ChannelGroup] = []
    @State private var refreshDebounce: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if groups.isEmpty {
                Text("Not currently sharing any channels with this contact across the connected networks. Channels populate the moment they show up in a NAMES reply or speak.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(groups, id: \.networkName) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.networkName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(group.channels, id: \.self) { chan in
                                Button {
                                    model.activeConnectionID = group.connectionID
                                    model.sendInput("/goto \(chan)")
                                } label: {
                                    Text(chan)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .help("Jump to \(chan) on \(group.networkName)")
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear { refreshNow() }
        .onChange(of: entry.id) { _, _ in refreshNow() }
        .onChange(of: entry.nick) { _, _ in scheduleRefresh() }
        .onChange(of: entry.linkedNicks) { _, _ in scheduleRefresh() }
        .onDisappear { refreshDebounce?.cancel() }
    }

    private func refreshNow() {
        refreshDebounce?.cancel()
        groups = sharedChannels()
    }

    private func scheduleRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            refreshNow()
        }
    }

    private struct ChannelGroup {
        let networkName: String
        let connectionID: UUID
        let channels: [String]
    }

    private func sharedChannels() -> [ChannelGroup] {
        let nicks = Set(entry.allLinkedNicksLowercased())
        var out: [ChannelGroup] = []
        for conn in model.connections {
            let chans = conn.buffers
                .filter { $0.isChannel }
                .filter { buf in
                    buf.users.contains { nicks.contains($0.lowercased()) }
                }
                .map { $0.name }
                .sorted()
            if !chans.isEmpty {
                out.append(ChannelGroup(
                    networkName: conn.displayName,
                    connectionID: conn.id,
                    channels: chans))
            }
        }
        return out
    }
}

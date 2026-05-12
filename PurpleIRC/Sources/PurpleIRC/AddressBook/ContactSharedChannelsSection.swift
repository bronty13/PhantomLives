import SwiftUI

/// Channels currently in common with the selected contact, broken down
/// by network. Walks every live `IRCConnection`'s channel buffers and
/// checks whether any of the contact's linked nicks appears in the
/// user list.
struct ContactSharedChannelsSection: View {
    let entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    var body: some View {
        let groups = sharedChannels()
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

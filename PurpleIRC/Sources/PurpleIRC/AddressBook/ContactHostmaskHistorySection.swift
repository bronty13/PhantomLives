import SwiftUI

/// Distinct user@host strings ever seen for this contact, across every
/// linked-nick on every connected network's SeenStore. Useful for
/// spotting when a familiar nick reconnects from a new ISP / VPN, or
/// for noticing two known nicks sharing a host (a manual same-person
/// signal that backs the auto-link suggestions).
struct ContactHostmaskHistorySection: View {
    let entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    var body: some View {
        let hostmasks = entry.allCurrentHostmasks(
            across: model.connections,
            store: model.botEngine.seenStore
        )
        VStack(alignment: .leading, spacing: 4) {
            if hostmasks.isEmpty {
                Text("No hostmasks recorded yet — the seen tracker only captures user@host alongside live IRC events.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(hostmasks) { hm in
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(hm.host)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("last \(relative(hm.lastSeen))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if hm.firstSeen != hm.lastSeen {
                                Text("first \(relative(hm.firstSeen))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func relative(_ d: Date) -> String {
        RelativeTime.string(d)
    }
}

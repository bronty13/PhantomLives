import SwiftUI

/// Merged sightings timeline for the selected contact. Folds every
/// linked-nick's history across every connected network's SeenStore,
/// sorted newest-first. Renders compact rows with kind icon + network
/// + channel + host + relative time. Caps at the most recent 100 for
/// rendering responsiveness; the full history lives in SeenStore.
struct ContactActivityTimelineSection: View {
    let entry: AddressEntry
    @EnvironmentObject var model: ChatModel
    private static let maxRows = 100

    var body: some View {
        let sightings = entry.allSightings(
            across: model.connections,
            store: model.botEngine.seenStore
        )
        let shown = Array(sightings.prefix(Self.maxRows))
        VStack(alignment: .leading, spacing: 4) {
            if shown.isEmpty {
                Text("No sightings yet. The seen tracker (Setup → Bot) needs to be on for activity to land here.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(shown) { cs in
                    sightingRow(cs)
                }
                if sightings.count > Self.maxRows {
                    Text("Showing the \(Self.maxRows) most recent of \(sightings.count) total sightings.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func sightingRow(_ cs: ContactSighting) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: cs.sighting.kind))
                .foregroundStyle(color(for: cs.sighting.kind))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(cs.nick).font(.callout)
                    Text(actionLabel(cs)).foregroundStyle(.secondary).font(.caption)
                    if let chan = cs.sighting.channel, !chan.isEmpty {
                        Text(chan).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 6) {
                    Text(cs.networkName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let host = cs.sighting.userHost, !host.isEmpty {
                        Text("• \(host)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let detail = cs.sighting.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(relativeTimeString(cs.sighting.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "msg":  return "text.bubble"
        case "join": return "arrow.right.circle"
        case "part": return "arrow.left.circle"
        case "quit": return "power"
        case "nick": return "arrow.triangle.2.circlepath"
        default:     return "circle"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "msg":  return .blue
        case "join": return .green
        case "part": return .orange
        case "quit": return .red
        case "nick": return .purple
        default:     return .secondary
        }
    }

    private func actionLabel(_ cs: ContactSighting) -> String {
        switch cs.sighting.kind {
        case "msg":  return "said"
        case "join": return "joined"
        case "part": return "parted"
        case "quit": return "quit"
        case "nick": return "renamed"
        default:     return cs.sighting.kind
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        RelativeTime.string(date)
    }
}

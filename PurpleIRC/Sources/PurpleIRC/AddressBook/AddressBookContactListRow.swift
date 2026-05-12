import SwiftUI

/// One row in the workspace's master contact list. Shows the avatar
/// with presence dot, the contact's display nick, a coverage badge
/// (number of linked networks), inline tag chips, and the watch bell
/// when the watch flag is on.
struct AddressBookContactListRow: View {
    let entry: AddressEntry
    let presence: WatchPresence
    @EnvironmentObject var model: ChatModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ContactAvatar(entry: entry, size: 30)
                if presence != .unknown {
                    Circle()
                        .fill(presenceDotColor)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
                        )
                        .offset(x: 1, y: 1)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.nick.isEmpty ? "Unnamed contact" : entry.nick)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(entry.nick.isEmpty ? .secondary : .primary)
                    if entry.watch {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("Notify when online")
                    }
                    if coverage > 1 {
                        Text("\(coverage)")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .help("\(coverage) networks linked")
                    }
                }
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !entry.tagIDs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(entry.tagIDs.prefix(3), id: \.self) { tagID in
                            if let tag = model.settings.settings.contactTags
                                .first(where: { $0.id == tagID }) {
                                Circle()
                                    .fill(tagDotColor(tag))
                                    .frame(width: 7, height: 7)
                                    .help(tag.name)
                            }
                        }
                        if entry.tagIDs.count > 3 {
                            Text("+\(entry.tagIDs.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var coverage: Int {
        Set(entry.linkedNicks.map(\.networkSlug)).count
    }

    private var presenceDotColor: Color {
        switch presence {
        case .online:  return .green
        case .offline: return .gray
        case .unknown: return .yellow
        }
    }

    private func tagDotColor(_ tag: ContactTag) -> Color {
        if let hex = tag.colorHex, let c = Color(hex: hex) { return c }
        return .purple
    }
}

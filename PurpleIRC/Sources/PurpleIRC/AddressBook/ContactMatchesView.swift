import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Contact match result

/// Cross-network seen-store + log-store hits for an address-book contact's
/// nick. Computed in `AddressEntryEditor.loadMatches()` and rendered by
/// `ContactMatchesSection`.
struct ContactMatchResult: Equatable {
    var seen: [SeenHit] = []
    var logs: [LogHit] = []

    struct SeenHit: Identifiable, Equatable {
        var id: String { "\(connection.id.uuidString):\(seen.id)" }
        /// IRCConnection so the matches view can route the user to the
        /// right /seen sheet. Equatable comparisons only care about ids.
        var connection: IRCConnection
        var networkName: String
        var seen: SeenEntry
        var isExact: Bool

        static func == (lhs: SeenHit, rhs: SeenHit) -> Bool {
            lhs.connection.id == rhs.connection.id
            && lhs.networkName == rhs.networkName
            && lhs.seen == rhs.seen
            && lhs.isExact == rhs.isExact
        }
    }

    struct LogHit: Identifiable, Equatable, Hashable {
        var id: String { "\(network)::\(buffer)" }
        var network: String
        var buffer: String
        var isExact: Bool
    }

    /// Match check used by both seen and log lookups: exact (case-insensitive)
    /// or fuzzy (substring contains, case-insensitive). Empty needles never
    /// match — caller short-circuits on those anyway.
    static func matches(needle: String, candidate: String) -> Bool {
        let n = needle.lowercased()
        guard !n.isEmpty else { return false }
        let c = candidate.lowercased()
        if c == n { return true }   // exact (case-insensitive) always counts
        // Fuzzy (substring) matches require a needle of at least 3 chars, so
        // a 1–2 char nick like "al" doesn't spuriously match every contact
        // that merely contains those letters ("Walter", "balance", …).
        guard n.count >= 3 else { return false }
        if c.contains(n) { return true }
        if n.contains(c) && c.count >= 3 { return true }
        return false
    }
}

/// Render seen + log matches inside the AddressEntryEditor. Empty matches
/// surface a friendly "no hits" message so the user knows the search ran.
struct ContactMatchesSection: View {
    let nick: String
    let matches: ContactMatchResult
    let onOpenSeenList: (IRCConnection) -> Void
    let onOpenChatLogs: () -> Void
    let onOpenQuery: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("\(matches.seen.count) seen-bot match\(matches.seen.count == 1 ? "" : "es") • \(matches.logs.count) log file\(matches.logs.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if nick.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Set a nickname above to see matches in the seen log and chat logs.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if matches.seen.isEmpty && matches.logs.isEmpty {
                Text("No exact or fuzzy matches in any connected network's seen log or in the chat-log archive.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !matches.seen.isEmpty {
                Text("Seen-bot matches")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(matches.seen) { hit in
                    HStack(spacing: 8) {
                        Image(systemName: hit.isExact ? "person.fill.checkmark" : "person.fill.questionmark")
                            .foregroundStyle(hit.isExact ? Color.purple : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(hit.seen.nick)
                                    .font(.system(.body, design: .monospaced))
                                Text("on \(hit.networkName)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !hit.isExact {
                                    Text("(fuzzy)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            HStack(spacing: 6) {
                                Text(Self.relativeDate(hit.seen.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let ch = hit.seen.channel, !ch.isEmpty {
                                    Text("• \(ch)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("• \(hit.seen.kind)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            onOpenSeenList(hit.connection)
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .help("Open the seen log for \(hit.networkName)")
                        .buttonStyle(.borderless)
                        Button {
                            onOpenQuery(hit.seen.nick)
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .help("Open a /query buffer with \(hit.seen.nick)")
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !matches.logs.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Chat-log matches")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(matches.logs) { hit in
                    HStack(spacing: 8) {
                        Image(systemName: hit.isExact ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(hit.isExact ? Color.purple : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(hit.buffer)
                                    .font(.system(.body, design: .monospaced))
                                Text("on \(hit.network)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !hit.isExact {
                                    Text("(fuzzy)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            onOpenChatLogs()
                        } label: {
                            Image(systemName: "tray.full")
                        }
                        .help("Open the chat-log viewer (pick \(hit.buffer) from the list)")
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

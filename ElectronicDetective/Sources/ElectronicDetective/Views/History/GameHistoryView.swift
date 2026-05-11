import SwiftUI

/// Sheet showing every finished game from `session_history`, newest first.
/// Refreshes itself when shown — the table is append-only so we don't have
/// to observe it.
struct GameHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DatabaseService.HistoryEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            Text("Game History").font(.title3).bold()
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36)).foregroundStyle(.orange)
                Text("Couldn't read history")
                Text(err).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No finished games yet")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(entries) {
                TableColumn("Finished") { e in
                    Text(formatter.string(from: e.finishedAt))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 140)
                TableColumn("Outcome") { e in
                    Text(e.outcome.rawValue)
                        .foregroundStyle(color(for: e.outcome))
                        .font(.caption.weight(.semibold))
                }
                .width(min: 80)
                TableColumn("Difficulty") { e in
                    Text(e.difficulty.displayName).font(.caption)
                }
                .width(min: 120)
                TableColumn("Players") { e in
                    Text("\(e.playerCount)").font(.caption.monospacedDigit())
                }
                .width(min: 60)
                TableColumn("Murderer") { e in
                    let s = SuspectRoster.suspect(id: e.murdererId)
                    Text("#\(s.id) — \(s.name)").font(.caption)
                }
            }
        }
    }

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func color(for outcome: GameSession.Outcome) -> Color {
        switch outcome {
        case .solved: return .green
        case .allWrong, .abandoned: return .red
        case .inProgress: return .secondary
        }
    }

    private func reload() {
        do {
            entries = try DatabaseService.shared.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

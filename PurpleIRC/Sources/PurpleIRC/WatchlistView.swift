import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var watchlist: WatchlistService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(Color.purple)
                Text("Recent watchlist hits").font(.headline)
                Spacer()
                Button("Open Address Book…") {
                    // Watchlist + Address Book used to live in two places;
                    // they're unified now, but this sheet stays as a
                    // live "what just happened" feed. Hand off to the
                    // Address Book tab where contacts + alerts live.
                    model.showWatchlist = false
                    model.pendingSetupTab = .addressBook
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.showSetup = true
                    }
                }
                Button("Done") { model.showWatchlist = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            recentHitsSection

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched contacts and alert options live in Setup → Address Book.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(watchlist.notificationsAuthorized
                     ? "macOS notifications: authorized ✓"
                     : "macOS notifications: not authorized — check System Settings → Notifications → PurpleIRC.")
                    .font(.caption2)
                    .foregroundStyle(watchlist.notificationsAuthorized ? Color.secondary : Color.orange)
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private var recentHitsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Recent hits", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Test notification") { watchlist.fireTestAlert() }
                    .buttonStyle(.bordered)
                if !watchlist.recentHits.isEmpty {
                    Button("Clear") { watchlist.clearHits() }
                }
            }
            if watchlist.recentHits.isEmpty {
                Text("No sightings yet. Alerts will appear here as well as a macOS banner.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(watchlist.recentHits) { hit in
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(Color.purple)
                        VStack(alignment: .leading) {
                            Text(hit.nick).font(.system(.body, design: .monospaced)).bold()
                            Text("via \(hit.source) • \(Self.timeFmt.string(from: hit.timestamp))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            watchlist.dismissHit(hit.id)
                        } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

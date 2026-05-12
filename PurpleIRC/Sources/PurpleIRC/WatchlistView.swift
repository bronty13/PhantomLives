import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var watchlist: WatchlistService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(Color.purple)
                Text("Recent watchlist hits").font(.headline)
                Spacer()
                Button("Open Address Book…") {
                    // Bounce to the dedicated workspace window — the
                    // address-book features live in their own Scene
                    // (⇧⌘B) starting in 1.0.242.
                    model.showWatchlist = false
                    openWindow(id: "address-book")
                }
                Button("Done") { model.showWatchlist = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            recentHitsSection

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched contacts, linked nicks, and per-contact alert overrides live in the Address Book workspace (⇧⌘B).")
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

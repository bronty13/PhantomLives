import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var watchlist: WatchlistService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bell.badge").foregroundStyle(Color.purple)
                Text("Watchlist").font(.headline)
                Spacer()
                Button("Manage in Setup…") { model.showSetup = true }
                Button("Done") { model.showWatchlist = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            recentHitsSection
            Divider()
            alertOptionsSection
            Divider()
            watchedListSection

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Tip: add or edit watched users in Setup → Address Book.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(watchlist.notificationsAuthorized
                     ? "macOS notifications: authorized ✓"
                     : "macOS notifications: not authorized — check System Settings → Notifications → PurpleIRC.")
                    .font(.caption2)
                    .foregroundStyle(watchlist.notificationsAuthorized ? Color.secondary : Color.orange)
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 520)
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

    private var alertOptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Alert options", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
            Toggle("System notification (banner + Notification Center)",
                   isOn: Binding(
                    get: { model.settings.settings.systemNotificationsOnWatchHit },
                    set: { model.settings.settings.systemNotificationsOnWatchHit = $0 }))
            Toggle("Play sound",
                   isOn: Binding(
                    get: { model.settings.settings.playSoundOnWatchHit },
                    set: { model.settings.settings.playSoundOnWatchHit = $0 }))
            Toggle("Bounce Dock icon (critical)",
                   isOn: Binding(
                    get: { model.settings.settings.bounceDockOnWatchHit },
                    set: { model.settings.settings.bounceDockOnWatchHit = $0 }))
            Divider().padding(.vertical, 2)
            Toggle("Alert when my nick is mentioned",
                   isOn: Binding(
                    get: { model.settings.settings.highlightOnOwnNick },
                    set: { model.settings.settings.highlightOnOwnNick = $0 }))
            Text("Uses the same sound / banner / dock-bounce toggles above.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var watchedListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Watched users", systemImage: "person.2.badge.gearshape")
                .font(.subheadline.weight(.semibold))
            if watchlist.watched.isEmpty {
                Text("No one on the list yet. Open Setup → Address Book to add entries.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                List(watchlist.watched, id: \.self) { nick in
                    HStack {
                        Circle().fill(color(for: nick)).frame(width: 10, height: 10)
                        Text(nick).font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(label(for: nick)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 100)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private func color(for nick: String) -> Color {
        switch watchlist.presence[nick.lowercased()] ?? .unknown {
        case .online: return .green
        case .offline: return .gray
        case .unknown: return .yellow
        }
    }

    private func label(for nick: String) -> String {
        switch watchlist.presence[nick.lowercased()] ?? .unknown {
        case .online: return "online"
        case .offline: return "offline"
        case .unknown: return model.connectionState == .connected ? "checking…" : "no connection"
        }
    }
}

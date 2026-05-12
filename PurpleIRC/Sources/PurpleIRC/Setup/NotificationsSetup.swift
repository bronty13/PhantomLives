import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Notifications

/// All the channels through which an event can grab the user's attention,
/// surfaced as a single tab so they're easy to tune as a group rather
/// than scattered across Behavior + Appearance + Highlights.
struct NotificationsSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Watchlist hits") {
                Toggle("Play sound", isOn: $settings.settings.playSoundOnWatchHit)
                Toggle("Bounce Dock icon", isOn: $settings.settings.bounceDockOnWatchHit)
                Toggle("Show macOS notification banner",
                       isOn: $settings.settings.systemNotificationsOnWatchHit)
                Toggle("Open query when a watched contact first messages me",
                       isOn: $settings.settings.popQueryBufferOnWatch)
                Text("A watch hit fires when a watched address-book contact comes online (via MONITOR or ISON polling) or speaks while you're connected. *Open query* additionally switches the active network and selects the new query buffer when a watched contact's PRIVMSG creates a fresh conversation — off by default so it doesn't yank you out of what you're doing.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Own-nick mention") {
                Toggle("Highlight when someone says my nick",
                       isOn: $settings.settings.highlightOnOwnNick)
                Text("Mentions tint the row, mark it with @, and fire the same sound + banner + dock-bounce alerts as watchlist hits. Per-rule alerts on the **Highlights** tab override these defaults.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Highlight rules") {
                Text("Per-rule sound / dock / banner toggles live alongside the rule editor on the **Highlights** tab.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("System") {
                Text("PurpleIRC requests notification permission the first time the app launches. If you denied it, grant access in **System Settings → Notifications → PurpleIRC**.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}


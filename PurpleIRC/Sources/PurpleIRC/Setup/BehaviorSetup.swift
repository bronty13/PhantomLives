import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Behavior (Logs + CTCP + Away)

struct BehaviorSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Quit") {
                Toggle("Confirm before /quit or /exit closes the app",
                       isOn: $settings.settings.quitConfirmationEnabled)
                Text("/quit and /exit close PurpleIRC entirely (after sending a QUIT to each connected network). Use /disconnect to leave one network without quitting.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Session restore") {
                Toggle("Restore open channels and queries on launch",
                       isOn: $settings.settings.restoreOpenBuffersOnLaunch)
                Text("When you reconnect, PurpleIRC re-joins the channels you had open and re-creates query buffers from your last session. Channel JOINs go through the normal CAP / auto-join path, so server-side ACLs still apply. Off = fresh slate every connect.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("CTCP") {
                Toggle("Reply to CTCP requests", isOn: $settings.settings.ctcpRepliesEnabled)
                TextField("VERSION reply", text: $settings.settings.ctcpVersionString)
                Text("Replies to VERSION, PING, TIME, FINGER, SOURCE, USERINFO, CLIENTINFO. Disabled requests still fire events for PurpleBot to handle.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Away") {
                Toggle("Auto-reply to direct PMs while away",
                       isOn: $settings.settings.autoReplyWhenAway)
                TextField("Default away reason",
                          text: $settings.settings.awayReasonDefault)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-reply message").font(.caption).foregroundStyle(.secondary)
                    SpellCheckedTextEditor(
                        text: $settings.settings.awayAutoReply,
                        font: .systemFont(ofSize: 13))
                        .frame(minHeight: 60)
                }
                Text("Use /away [reason] to mark yourself away and /back to return. Auto-replies are throttled per-sender.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            messageFilterDefaultsSection
            Section("Where to find moved settings") {
                Text("• Alerts and sounds (banner / dock / per-event sounds) → **Notifications & Sounds** tab")
                Text("• Persistent logs and retention → **Logging** tab")
                Text("• DCC file transfers → **DCC Transfers** tab (per-server proxy lives on each profile under **Servers**)")
                Text("• Backups → **Backup** tab")
            }
            .font(.caption)
        }
        .formStyle(.grouped)
    }

    /// App-wide defaults for which `ChatLine.Kind` cases render in a
    /// channel buffer. New buffers inherit these; the funnel popover in
    /// the buffer header lets the user override per-buffer.
    @ViewBuilder
    private var messageFilterDefaultsSection: some View {
        Section("Default message filter") {
            ForEach(MessageKindToggle.allCases) { toggle in
                Toggle(toggle.label, isOn: Binding(
                    get: { toggle.get(from: settings.settings.messageFilterDefaults) },
                    set: { newValue in
                        var next = settings.settings.messageFilterDefaults
                        toggle.set(newValue, on: &next)
                        settings.settings.messageFilterDefaults = next
                    }
                ))
                .help(toggle.help)
            }
            HStack {
                Button("Reset to show everything") {
                    settings.settings.messageFilterDefaults = MessageKindFilter()
                }
                Spacer()
                Button("Clear every per-buffer override") {
                    settings.settings.messageFiltersByBuffer.removeAll()
                }
                .help("Drops every per-buffer customization so all channels follow these defaults.")
            }
            Text("These toggles apply to all channels by default. The funnel button in any channel's header can override them per buffer; PRIVMSG and ACTION lines always render.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Proxy & DCC

/// Network plumbing that used to live at the bottom of Behavior. Splitting
/// it out keeps the per-network proxy + DCC settings together so a user
/// configuring a corporate proxy doesn't have to scroll past quit / away
/// toggles to find them.
struct ProxyDccSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("DCC (file transfers + chat)") {
                TextField("External IP (for outgoing offers)",
                          text: $settings.settings.dccExternalIP)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Stepper(value: $settings.settings.dccPortRangeStart, in: 1024...65535) {
                        TextField("Port range start",
                                  value: $settings.settings.dccPortRangeStart,
                                  format: .number)
                    }
                    Stepper(value: $settings.settings.dccPortRangeEnd, in: 1024...65535) {
                        TextField("Port range end",
                                  value: $settings.settings.dccPortRangeEnd,
                                  format: .number)
                    }
                }
                Text("Outgoing DCC SEND / CHAT listens on this port range and advertises the address above. Behind NAT you'll need to port-forward and set the public IP — auto-detection only picks up LAN addresses. Passive/reverse DCC and RESUME aren't implemented yet.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Proxy") {
                Text("Per-server proxy settings (SOCKS5 / HTTP CONNECT) live on each server profile under **Servers**. Defaults are direct connection.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}


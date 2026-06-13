import SwiftUI

/// The popover panel shown when the menu-bar icon is clicked.
struct MenuView: View {
    @ObservedObject var controller: SyncController
    @ObservedObject var updater: UpdaterViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusGrid
            if let msg = controller.lastActionMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 320)
        .task { await controller.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.health.symbol)
                .font(.title2)
                .foregroundStyle(healthColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("PurpleMirror").font(.headline)
                Text(controller.health.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isSyncing { ProgressView().controlSize(.small) }
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            row("Last sync", controller.lastSyncRelative)
            if let n = controller.lastLog.fileCount {
                row("Files mirrored", "\(n)")
            }
            row("Auto-sync", controller.agentLoaded ? "On · every \(controller.intervalHuman)" : "Off")
            if let code = controller.lastExitCode {
                row("Last result", code == 0 ? "OK" : "Error (exit \(code))")
            }
            row("Vault", vaultName)
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).gridColumnAlignment(.leading).lineLimit(1).truncationMode(.middle)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                controller.syncNow()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(controller.isSyncing)

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "log")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("View Log", systemImage: "doc.plaintext").frame(maxWidth: .infinity)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .disabled(!updater.canCheckForUpdates)

            HStack {
                Text("v\(updater.appVersion)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: { Text("Quit") }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 2)
        }
    }

    private var healthColor: Color {
        switch controller.health {
        case .healthy: return .green
        case .running: return .accentColor
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private var vaultName: String {
        let p = controller.vaultPath
        if p.isEmpty { return "—" }
        return (p as NSString).lastPathComponent
    }
}

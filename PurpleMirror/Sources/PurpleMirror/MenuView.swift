import SwiftUI
import AppKit

/// The popover panel shown when the menu-bar icon is clicked: a row per managed
/// background job, plus app-wide actions.
struct MenuView: View {
    @ObservedObject var model: JobsModel
    @ObservedObject var updater: UpdaterViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var ejecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.hasRemoteHosts {
                ClusterSection(model: model)
                Divider()
            } else if !model.offlineHosts.isEmpty {
                offlineBanner
                Divider()
            } else {
                Divider()
            }
            if model.jobs.isEmpty {
                Text("No managed jobs found.\nPurpleMirror watches PhantomLives launchd agents in ~/Library/LaunchAgents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.groups, id: \.name) { grp in
                            GroupSection(name: grp.name, jobs: grp.jobs,
                                         health: model.groupHealth(grp.jobs),
                                         openLog: { openLog(for: $0) })
                        }
                    }
                }
                // A `.window` MenuBarExtra sizes to content's *ideal* height, but a
                // bare ScrollView reports ~0 there and collapses to an empty strip.
                // Give it a DEFINITE height sized to the rows (capped) so it renders
                // and only scrolls once the list is genuinely tall.
                .frame(height: listHeight)
            }
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 360)
        .task { await model.refreshAll() }
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.offlineHosts, id: \.host.id) { entry in
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.orange)
                    Text("\(entry.host.displayName) offline — last seen \(entry.lastSeen)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.aggregateHealth.symbol)
                .font(.title2)
                .foregroundStyle(model.aggregateHealth.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("PurpleMirror").font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.jobs.contains(where: { $0.isRunning }) { ProgressView().controlSize(.small) }
        }
    }

    private var subtitle: String {
        let n = model.jobs.count
        guard n > 0 else { return "No jobs" }
        var s = "\(n) job\(n == 1 ? "" : "s") · \(model.aggregateHealth.label)"
        let t = model.totalItemsLast24h
        if t > 0 { s += " · \(SyncStatusParser.grouped(t)) new in 24h" }
        return s
    }

    /// Estimated natural height of the grouped job list, capped so very long lists
    /// scroll instead of growing the window past ~460pt.
    private var listHeight: CGFloat {
        let rows = CGFloat(model.jobs.count) * 44      // each JobRow ≈ 44pt
        let headers = CGFloat(model.groups.count) * 34 // each group header ≈ 34pt
        return min(rows + headers + 12, 460)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    openLog(for: model.selectedJobID ?? model.jobs.first?.id)
                } label: {
                    Label("Open Logs…", systemImage: "doc.plaintext").frame(maxWidth: .infinity)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity)
                }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .disabled(!updater.canCheckForUpdates)

            Divider()

            // Reboot-safe shortcut: macOS Tahoe 26 hangs shutdown when an external
            // drive is still mounted (diskarbitrationd wedges in unmount()); these
            // unmount everything external first. See docs/reboot-hangs.md.
            HStack(spacing: 8) {
                Button { Task { await ejectExternals() } } label: {
                    Label("Eject Drives", systemImage: "eject").frame(maxWidth: .infinity)
                }
                .help("Unmount all external drives — do this before unplugging one, or before restarting")

                Button { Task { await restartSafely() } } label: {
                    Label("Restart Safely…", systemImage: "restart").frame(maxWidth: .infinity)
                }
                .help("Unmount all external drives, then restart — avoids the macOS Tahoe shutdown hang")
            }
            .disabled(ejecting)

            HStack {
                Text("v\(updater.appVersion)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: { Text("Quit") }
                    .buttonStyle(.borderless).font(.caption)
            }
            .padding(.top, 2)
        }
    }

    private func openLog(for id: String?) {
        if let id { model.selectedJobID = id }
        openWindow(id: "log")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Unmount every external drive (graceful only — never forced, to protect
    /// client media), then report the result.
    @MainActor private func ejectExternals() async {
        NSApp.activate(ignoringOtherApps: true)
        ejecting = true
        let outcome = await RebootSafeService.ejectAll()
        ejecting = false

        let a = NSAlert()
        if outcome.ok {
            a.messageText = "External drives unmounted"
            a.informativeText = "It's now safe to restart, or to physically disconnect them."
            a.alertStyle = .informational
        } else {
            a.messageText = "Some drives are still in use"
            a.informativeText = "Couldn't unmount:\n\n• "
                + outcome.stillMounted.joined(separator: "\n• ")
                + "\n\nClose any app using them (e.g. a copy in progress) and try again."
            a.alertStyle = .warning
        }
        a.runModal()
    }

    /// Confirm, unmount all externals, then restart — the GUI `reboot-safe`.
    @MainActor private func restartSafely() async {
        NSApp.activate(ignoringOtherApps: true)

        let intro = NSAlert()
        intro.messageText = "Restart safely?"
        intro.informativeText = "PurpleMirror will unmount all external drives first — so the restart can't hang on macOS Tahoe — then restart your Mac."
        intro.addButton(withTitle: "Unmount & Restart")
        intro.addButton(withTitle: "Cancel")
        intro.alertStyle = .informational
        guard intro.runModal() == .alertFirstButtonReturn else { return }

        ejecting = true
        let outcome = await RebootSafeService.ejectAll()
        ejecting = false

        guard outcome.ok else {
            let busy = NSAlert()
            busy.messageText = "Restart cancelled — a drive is busy"
            busy.informativeText = "These external drives wouldn't unmount:\n\n• "
                + outcome.stillMounted.joined(separator: "\n• ")
                + "\n\nClose whatever is using them, then try again."
            busy.alertStyle = .warning
            busy.runModal()
            return
        }

        if await RebootSafeService.restart() == false {
            let fallback = NSAlert()
            fallback.messageText = "Drives unmounted — restart manually"
            fallback.informativeText = "All external drives are unmounted, so it's now safe to restart from the Apple menu.\n\n(PurpleMirror couldn't trigger the restart itself — grant it Automation access in System Settings → Privacy & Security → Automation for one-click restart.)"
            fallback.alertStyle = .informational
            fallback.runModal()
        }
    }
}

/// The **Cluster** panel: one row per node (local + every fleet/remote host) with a live status
/// dot, quick-connect shortcuts, and an IP/host tooltip on hover.
private struct ClusterSection: View {
    @ObservedObject var model: JobsModel
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "rectangle.3.group").font(.caption).foregroundStyle(.secondary)
                    Text("Cluster").font(.subheadline.weight(.semibold))
                    Text("\(model.monitoredHosts.count)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 5) {
                    ForEach(model.hostContexts, id: \.host.id) { ctx in NodeRow(ctx: ctx) }
                }
                .padding(.leading, 4)
            }
        }
    }
}

/// One cluster node: status dot · name · SSH/SMB/Screen-Sharing shortcuts. Hover shows IP + host.
private struct NodeRow: View {
    @ObservedObject var ctx: HostContext
    @Environment(\.openURL) private var openURL
    private var host: MonitoredHost { ctx.host }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
                .help(statusText)
            Text(host.displayName).font(.callout.weight(.medium))
            if host.fromFleet {
                Text("FLEET").font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(.tint.opacity(0.18), in: Capsule()).foregroundStyle(.tint)
            }
            Spacer(minLength: 6)
            if !host.isLocal {
                connectButton("terminal", host.sshURLString, "SSH to \(host.displayName) (Terminal)")
                connectButton("folder", host.smbURLString, "File sharing (SMB) on \(host.displayName)")
                connectButton("display", host.vncURLString, "Screen Sharing (VNC) to \(host.displayName)")
            } else {
                Text("this Mac").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .help(tooltip)   // hover → IP + host info
    }

    private var statusColor: Color {
        if host.isLocal { return .green }
        return ctx.reachable ? .green : .orange
    }
    private var statusText: String {
        host.isLocal ? "this machine" : (ctx.reachable ? "online" : "offline — last seen \(ctx.lastSeenRelative)")
    }
    /// Hover tooltip: connection target, live IP, and online/offline + last-seen.
    private var tooltip: String {
        if host.isLocal {
            return "This Mac" + (ctx.resolvedIP.map { "\nIP: \($0)" } ?? "")
        }
        var lines = [host.sshTarget]
        if let ip = ctx.resolvedIP { lines.append("IP: \(ip)") }
        lines.append(ctx.reachable ? "online" : "offline — last seen \(ctx.lastSeenRelative)")
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func connectButton(_ symbol: String, _ urlString: String?, _ help: String) -> some View {
        Button {
            if let s = urlString, let url = URL(string: s) { openURL(url) }
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .disabled(urlString == nil)
    }
}

/// A collapsible section grouping one source's jobs (e.g. all of "Rachel").
private struct GroupSection: View {
    let name: String
    let jobs: [JobController]
    let health: SyncStatusParser.Health
    var openLog: (String) -> Void
    @State private var expanded = true

    private var groupTally: Int { jobs.compactMap(\.itemsLast24h).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: health.symbol).foregroundStyle(health.color).font(.caption)
                    Text(name).font(.subheadline.weight(.semibold))
                    Text("\(jobs.count)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if groupTally > 0 {
                        Text("\(SyncStatusParser.grouped(groupTally)) new / 24h")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 6) {
                    ForEach(jobs) { job in JobRow(job: job) { openLog(job.id) } }
                }
                .padding(.leading, 4)
            }
        }
    }
}

/// One job's row: status glyph, name, last-activity digest, and a Run-Now / View-Log pair.
private struct JobRow: View {
    @ObservedObject var job: JobController
    var onViewLog: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.health.symbol)
                .foregroundStyle(job.health.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.shortName).font(.callout.weight(.medium))
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if job.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button { job.runNow() } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless)
                    .help("Run \(job.displayName) now")
            }
            Button(action: onViewLog) { Image(systemName: "doc.plaintext") }
                .buttonStyle(.borderless)
                .help("View \(job.displayName) log")
        }
    }

    private var secondary: String {
        var parts: [String] = [job.lastActivityRelative]
        if let h = job.summary?.headline { parts.append(h) }
        else { parts.append(job.agentLoaded ? "Auto every \(job.intervalHuman)" : "Auto-run off") }
        if let n = job.itemsLast24h { parts.append("\(SyncStatusParser.grouped(n)) in 24h") }
        return parts.joined(separator: " · ")
    }
}

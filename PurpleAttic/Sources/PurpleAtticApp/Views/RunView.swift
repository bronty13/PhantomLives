import SwiftUI
import PurpleAtticCore

/// The archive dashboard: run buttons, a live log, and the last run summary.
struct RunView: View {
    @EnvironmentObject var appState: AppState
    @State private var showIncompleteConfirm = false

    private var issues: [String] {
        appState.store.profile.validationIssues().filter { !$0.contains("Purge is enabled") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !appState.permissions.allGranted { permissionsBanner }
            if !issues.isEmpty { issuesBanner }
            if appState.readiness.osxphotos == nil { osxphotosBanner }
            if !spaceWarnings.isEmpty { spaceBanner }
            if let progress = appState.progress { progressPanel(progress); Divider() }
            logPane
        }
        .onAppear {
            appState.refreshVaultStatus()
            appState.refreshPermissions()
            if appState.libraryInspection == nil { appState.checkLibrary() }
        }
        .alert("This library looks incomplete", isPresented: $showIncompleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Run Anyway", role: .destructive) { appState.runArchive(dryRun: false) }
        } message: {
            Text((appState.libraryInspection?.summary ?? "")
                 + "\n\nArchiving now captures only the originals currently on this Mac. Run on the Mac set to “Download Originals,” or enable download-missing in Settings.")
        }
    }

    @ViewBuilder
    private var libraryStatusLine: some View {
        if appState.isCheckingLibrary {
            Label("Checking library…", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
        } else if let insp = appState.libraryInspection {
            HStack(spacing: 5) {
                Image(systemName: insp.optimizeStorageLikely ? "exclamationmark.triangle.fill"
                      : (insp.readable ? "checkmark.circle" : "questionmark.circle"))
                    .foregroundStyle(insp.optimizeStorageLikely ? .orange : .secondary)
                Text(insp.summary).foregroundStyle(insp.optimizeStorageLikely ? .orange : .secondary)
                Button("Recheck") { appState.checkLibrary() }.buttonStyle(.link).font(.caption)
            }
            .font(.caption)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.store.profile.name).font(.title3.weight(.semibold))
                Text(appState.store.profile.primaryDestination.isEmpty
                     ? "No destination set — see Settings"
                     : appState.store.profile.primaryDestination)
                    .font(.caption).foregroundStyle(.secondary)
                libraryStatusLine
            }
            Spacer()
            if appState.isRunning {
                ProgressView().controlSize(.small)
                Text("Running…").foregroundStyle(.secondary)
            }
            Button {
                appState.runArchive(dryRun: true)
            } label: { Label("Dry Run", systemImage: "eye") }
                .disabled(appState.isRunning || !issues.isEmpty || !appState.permissions.allGranted)
            Button {
                if appState.libraryInspection?.optimizeStorageLikely == true {
                    showIncompleteConfirm = true
                } else {
                    appState.runArchive(dryRun: false)
                }
            } label: { Label("Run Archive", systemImage: "play.fill") }
                .keyboardShortcut("r", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(appState.isRunning || !issues.isEmpty || appState.readiness.osxphotos == nil
                          || !appState.permissions.allGranted)
        }
        .padding(16)
    }

    // MARK: Progress dashboard (phase stepper)

    @ViewBuilder
    private func progressPanel(_ p: RunProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(p.steps) { step in
                    phaseChip(step)
                    if step.id != p.steps.last?.id {
                        Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary).font(.caption2)
                    }
                }
                Spacer()
                Text(fmtElapsed(p.totalSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let active = p.activeStep {
                    Label("\(active.kind.rawValue): \(active.detail.isEmpty ? "working…" : active.detail)",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if p.finished {
                    Label("Run finished", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                }
                if p.embedSkips > 0 {
                    Label("\(p.embedSkips) sidecar-only", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                        .help("Photos archived with metadata in the .xmp sidecar only (in-file embed skipped — damaged EXIF). Not errors.")
                }
                Spacer()
            }
            if !p.currentFile.isEmpty {
                Text(p.currentFile)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(12)
        .background(.background.secondary)
    }

    @ViewBuilder
    private func phaseChip(_ step: RunProgress.Step) -> some View {
        let (icon, tint): (String, Color) = {
            switch step.state {
            case .pending:  return ("circle", .secondary)
            case .running:  return ("circle.dotted", .accentColor)
            case .done:     return ("checkmark.circle.fill", .green)
            case .failed:   return ("xmark.circle.fill", .red)
            case .skipped:  return ("minus.circle", .orange)
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.kind.rawValue).font(.caption.weight(step.state == .running ? .semibold : .regular))
                if step.state == .running || step.state == .done || step.state == .failed {
                    Text(step.seconds >= 1 ? fmtElapsed(step.seconds) : "")
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(step.state == .running ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func fmtElapsed(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \((s%3600)/60)m"
    }

    // MARK: Permissions preflight

    private var permissionsBanner: some View {
        banner(color: .red, icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grant macOS permissions before running")
                    .font(.callout.weight(.semibold))
                Text("PurpleAttic needs all three to archive cleanly. The run buttons stay disabled until they’re granted.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(PermissionKind.allCases) { kind in
                    permissionRow(kind)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(_ kind: PermissionKind) -> some View {
        let state = grantState(kind)
        HStack(spacing: 8) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(state == .granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.callout.weight(.medium))
                Text(kind.why).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if state != .granted {
                switch kind {
                case .photosAutomation:
                    Button("Grant…") { appState.requestPhotosAutomation() }
                case .photosLibrary:
                    Button("Grant…") { appState.requestPhotosLibrary() }
                case .fullDiskAccess:
                    EmptyView()
                }
                Button("Settings…") { appState.openPermissionSettings(kind) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private func grantState(_ kind: PermissionKind) -> GrantState {
        switch kind {
        case .fullDiskAccess:   return appState.permissions.fullDiskAccess
        case .photosAutomation: return appState.permissions.photosAutomation
        case .photosLibrary:    return appState.permissions.photosLibrary
        }
    }

    // MARK: Free-space sanity check (warning only)

    private var spaceWarnings: [FreeSpaceCheck.DestinationSpace] {
        appState.spaceChecks.filter { !$0.sufficient && $0.requiredBytes > 0 }
    }

    private var spaceBanner: some View {
        banner(color: .orange, icon: "externaldrive.badge.exclamationmark") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Possible low free space (estimate)").font(.callout.weight(.medium))
                ForEach(spaceWarnings) { d in
                    Text(d.unmeasured
                         ? "• \(d.label): \(d.base) — not mounted / can’t measure free space."
                         : "• \(d.label): ~\(FreeSpaceCheck.humanBytes(d.requiredBytes)) needed, "
                           + "\(FreeSpaceCheck.humanBytes(d.freeBytes ?? 0)) free on \(d.base).")
                        .font(.caption)
                }
                Text("Rough estimate from your library’s originals; the archive may still fit. Not blocking the run.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var issuesBanner: some View {
        banner(color: .orange, icon: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(issues, id: \.self) { Text($0).font(.callout) }
            }
        }
    }

    private var osxphotosBanner: some View {
        banner(color: .red, icon: "xmark.octagon.fill") {
            VStack(alignment: .leading, spacing: 2) {
                Text("osxphotos isn't installed.").font(.callout.weight(.medium))
                Text("Run: pipx install osxphotos  (then reopen this app)")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    private func banner<C: View>(color: Color, icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            content()
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = appState.runError {
                Text(err).font(.callout).foregroundStyle(.red)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(appState.logLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        if appState.logLines.isEmpty && !appState.isRunning {
                            Text("No run yet. “Dry Run” previews the osxphotos pass without writing anything; “Run Archive” performs export → mirror → verify → cloud.")
                                .font(.callout).foregroundStyle(.secondary).padding()
                        }
                    }
                    .padding(10)
                }
                .onChange(of: appState.logLines.count) { _, _ in
                    if let last = appState.logLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if let summary = appState.lastSummaryText {
                Divider()
                ScrollView {
                    Text(summary)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(.background.secondary)
            }
        }
    }

    private func color(for level: AtticLogger.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
}

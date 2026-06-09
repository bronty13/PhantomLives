import SwiftUI
import PurpleAtticCore

/// The archive dashboard: run buttons, a live log, and the last run summary.
struct RunView: View {
    @EnvironmentObject var appState: AppState

    private var issues: [String] {
        appState.store.profile.validationIssues().filter { !$0.contains("Purge is enabled") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !issues.isEmpty { issuesBanner }
            if appState.readiness.osxphotos == nil { osxphotosBanner }
            logPane
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
            }
            Spacer()
            if appState.isRunning {
                ProgressView().controlSize(.small)
                Text("Running…").foregroundStyle(.secondary)
            }
            Button {
                appState.runArchive(dryRun: true)
            } label: { Label("Dry Run", systemImage: "eye") }
                .disabled(appState.isRunning || !issues.isEmpty)
            Button {
                appState.runArchive(dryRun: false)
            } label: { Label("Run Archive", systemImage: "play.fill") }
                .keyboardShortcut("r", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(appState.isRunning || !issues.isEmpty || appState.readiness.osxphotos == nil)
        }
        .padding(16)
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

import SwiftUI
import AppKit
import PurpleAtticCore

/// Schedules the automated archive (export → mirror → verify → cloud) via a launchd agent.
/// Deliberately archive-only: purge is never automated.
struct ScheduleView: View {
    @EnvironmentObject var appState: AppState
    private var store: SettingsStore { appState.store }

    private var schedule: Binding<ArchiveSchedule> {
        Binding(get: { store.settings.schedule }, set: { store.settings.schedule = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Schedule").font(.title3.weight(.semibold))
                Text("Runs the archive automatically on this Mac. It only ever archives — purge is never automated and stays a manual step in the Purge pane.")
                    .font(.callout).foregroundStyle(.secondary)

                scheduleCard
                statusCard
                if let msg = appState.schedulerMessage { messageBanner(msg) }
                notesCard
            }
            .padding(20)
        }
        .onAppear { appState.refreshSchedulerStatus() }
    }

    private var scheduleCard: some View {
        Card(title: "When") {
            Toggle("Run the archive automatically", isOn: schedule.enabled)

            Picker("Frequency", selection: schedule.cadence) {
                Text("Hourly").tag(ArchiveSchedule.Cadence.hourly)
                Text("Daily").tag(ArchiveSchedule.Cadence.daily)
                Text("Weekly").tag(ArchiveSchedule.Cadence.weekly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .disabled(!store.settings.schedule.enabled)

            if store.settings.schedule.cadence == .hourly {
                Text("Runs every hour. If the archive drives aren't attached, the run does nothing and tries again next hour; the mirror and cloud copies catch up whenever their drive/vault is back.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if store.settings.schedule.cadence == .weekly {
                Picker("Day", selection: schedule.weekday) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(ArchiveSchedule.weekdayNames[i]).tag(i)
                    }
                }
                .frame(maxWidth: 240)
                .disabled(!store.settings.schedule.enabled)
            }

            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .frame(maxWidth: 240)
                .disabled(!store.settings.schedule.enabled)

            HStack {
                Spacer()
                Button("Apply") { appState.applySchedule() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusCard: some View {
        Card(title: "Status") {
            HStack(spacing: 6) {
                Image(systemName: appState.schedulerLoaded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(appState.schedulerLoaded ? .green : .secondary)
                Text(appState.schedulerLoaded ? "Loaded in launchd" : "Not scheduled")
            }
            if appState.schedulerLoaded {
                if let next = store.settings.schedule.nextRun(after: Date()) {
                    labeled("Next run", short(next))
                }
            }
            if let last = SchedulerService.lastRunDate() {
                labeled("Last run (log)", short(last))
            }
            HStack {
                Button("Run Now") { appState.runScheduledNow() }
                    .disabled(!store.settings.schedule.enabled && !appState.schedulerLoaded)
                Button("Reveal Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: SchedulerService.stdoutPath)])
                }
                Spacer()
            }
        }
    }

    private var notesCard: some View {
        Card(title: "Before you rely on it") {
            note("This runs only on this Mac, and only while it's awake — schedule it on the Mac that holds your originals (set to “Download Originals”).")
            note("Grant Full Disk Access to the bundled pattic tool so the background run can read Photos — the app's own grant does NOT cover it. Reveal it below, then drag it into System Settings → Privacy & Security → Full Disk Access:")
            Text(SchedulerService.patticPath)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Reveal pattic in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: SchedulerService.patticPath)])
                }
                Button("Open Full Disk Access…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
            }
            .controlSize(.small)
            note("Purge is never run automatically — open the Purge pane monthly to review and delete.")
        }
    }

    // MARK: Helpers

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = store.settings.schedule.hour
                c.minute = store.settings.schedule.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.settings.schedule.hour = c.hour ?? 12   // noon fallback (see ArchiveSchedule default)
                store.settings.schedule.minute = c.minute ?? 0
            }
        )
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.callout)
    }
    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
            Text(text).font(.callout).foregroundStyle(.secondary); Spacer()
        }
    }
    private func messageBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(msg).font(.callout); Spacer()
        }
        .padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}

import SwiftUI

struct NotificationsSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var auth: NotificationsService.Authorization = .notDetermined
    @State private var pendingCount: Int = 0
    @State private var infoMessage: String?

    var body: some View {
        Form {
            Section("Anniversary reminders") {
                Toggle("Notify me on event anniversaries", isOn: Binding(
                    get: { appState.settings.anniversaryRemindersEnabled },
                    set: { newValue in
                        var s = appState.settings
                        s.anniversaryRemindersEnabled = newValue
                        appState.settings = s
                        if newValue { ensureAuthorized() }
                    }
                ))

                Stepper("Lookahead: \(appState.settings.anniversaryLookaheadDays) days",
                        value: Binding(
                    get: { appState.settings.anniversaryLookaheadDays },
                    set: { var s = appState.settings; s.anniversaryLookaheadDays = $0; appState.settings = s }
                ), in: 1...365, step: 1)

                Picker("Notification time", selection: Binding(
                    get: { appState.settings.anniversaryNotificationHour },
                    set: { var s = appState.settings; s.anniversaryNotificationHour = $0; appState.settings = s }
                )) {
                    ForEach(Array(stride(from: 0, through: 23, by: 1)), id: \.self) { hour in
                        Text(formattedHour(hour)).tag(hour)
                    }
                }

                Picker("Minimum importance", selection: Binding(
                    get: { appState.settings.anniversaryMinImportance },
                    set: { var s = appState.settings; s.anniversaryMinImportance = $0; appState.settings = s }
                )) {
                    ForEach(Importance.allCases, id: \.self) { imp in
                        HStack {
                            Circle().fill(imp.tint).frame(width: 8, height: 8)
                            Text(imp.label)
                        }.tag(imp.rawValue)
                    }
                }
            }

            Section("Status") {
                LabeledContent("Authorization", value: auth.label)
                LabeledContent("Scheduled reminders", value: "\(pendingCount)")

                HStack {
                    if auth == .notDetermined {
                        Button("Request permission") {
                            Task { await requestAuth() }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if auth == .denied {
                        Button("Open System Settings") {
                            NotificationsService.shared.openSystemSettings()
                        }
                    }
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }
                    Button("Send test notification") {
                        Task { await NotificationsService.shared.fireTestNotification() }
                    }
                    .disabled(auth != .authorized)
                }

                if let infoMessage {
                    Text(infoMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { Task { await refresh() } }
    }

    // MARK: - Side effects

    private func formattedHour(_ hour: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date()
        return f.string(from: date)
    }

    private func ensureAuthorized() {
        Task {
            let current = await NotificationsService.shared.currentAuthorization()
            if current == .notDetermined {
                _ = await NotificationsService.shared.requestAuthorization()
            }
            await refresh()
            // After permission is in hand, reschedule so the user sees the
            // count tick up immediately rather than after the next reload.
            appState.scheduleAnniversaryReminders()
        }
    }

    private func requestAuth() async {
        _ = await NotificationsService.shared.requestAuthorization()
        await refresh()
        appState.scheduleAnniversaryReminders()
    }

    private func refresh() async {
        let a = await NotificationsService.shared.currentAuthorization()
        let c = await NotificationsService.shared.pendingCount()
        await MainActor.run {
            self.auth = a
            self.pendingCount = c
        }
    }
}

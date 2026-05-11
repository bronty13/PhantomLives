import SwiftUI

/// Single global setting that drives the year columns rendered on each
/// vendor's Budget & Actuals matrix. Inverted ranges are silently coerced.
struct ThirdPartiesSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Budget / Actuals Year Range") {
                Stepper(value: Binding(
                    get: { settingsStore.settings.thirdPartyYearStart },
                    set: { settingsStore.settings.thirdPartyYearStart = $0; settingsStore.save() }
                ), in: 1990...2100) {
                    Text("Start year: \(settingsStore.settings.thirdPartyYearStart)")
                }
                Stepper(value: Binding(
                    get: { settingsStore.settings.thirdPartyYearEnd },
                    set: { settingsStore.settings.thirdPartyYearEnd = $0; settingsStore.save() }
                ), in: 1990...2100) {
                    Text("End year: \(settingsStore.settings.thirdPartyYearEnd)")
                }
                Text("Years outside the range stay in the database — they're just hidden from the matrix.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

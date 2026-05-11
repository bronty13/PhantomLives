import AppKit
import SwiftUI

/// Settings → Weight. User profile values used by the Charts view
/// kind's Goal-line overlay (slice 3b) and the Statistics panel (BMI,
/// days-to-goal, forecast projection).
///
/// All four fields are optional — leaving any blank just means the
/// dependent feature won't show. Goal weight unset → no Goal line on
/// the chart and no days-to-goal in Statistics. Height unset → no BMI
/// section. Starting weight unset → defaults to the first Weight
/// record's value when computing total change.
struct WeightSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Profile") {
                Text("Used by the Weight type's Charts view (Goal line) and Statistics panel (BMI, forecast, days-to-goal). Leave any field blank to skip its dependent feature.")
                    .font(.caption).foregroundStyle(.secondary)

                LabeledContent {
                    TextField(
                        "(none)",
                        value: doubleBinding(\.goalWeightPounds),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    Text("lb").foregroundStyle(.tertiary)
                } label: {
                    Text("Goal weight")
                }

                LabeledContent {
                    TextField(
                        "(first record)",
                        value: doubleBinding(\.startingWeightPounds),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    Text("lb").foregroundStyle(.tertiary)
                } label: {
                    Text("Starting weight")
                }

                LabeledContent {
                    TextField(
                        "(no BMI)",
                        value: doubleBinding(\.heightInches),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    Text("in").foregroundStyle(.tertiary)
                } label: {
                    Text("Height")
                }

                LabeledContent {
                    Stepper(
                        value: Binding(
                            get: { appState.settings.forecastDays },
                            set: { var s = appState.settings; s.forecastDays = $0; appState.settings = s }
                        ),
                        in: 1...365,
                        step: 1
                    ) {
                        Text("\(appState.settings.forecastDays) day\(appState.settings.forecastDays == 1 ? "" : "s")")
                            .monospacedDigit()
                    }
                } label: {
                    Text("Forecast horizon")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Binding helpers

    /// Two-way binding to an optional `Double` field on `AppSettings`,
    /// routed through `appState.settings` so each set persists
    /// (SettingsStore.save fires on the setter).
    private func doubleBinding(_ keyPath: WritableKeyPath<AppSettings, Double?>) -> Binding<Double?> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { newValue in
                var s = appState.settings
                s[keyPath: keyPath] = newValue
                appState.settings = s
            }
        )
    }
}

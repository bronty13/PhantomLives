import SwiftUI
import MasterClipperCore

struct CalendarRulesTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var lastResult: CalendarService.GenerationResult?
    @State private var error: String?

    private let weekdays = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar release rules")
                .font(.title3.weight(.semibold))
            Text("Each persona has a per-weekday checkbox. \"Generate Year\" creates blank `(date, persona)` events for every matching weekday in the year, skipping any that already exist.")
                .font(.callout).foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Persona").font(.caption.weight(.semibold))
                        ForEach(weekdays, id: \.0) { (_, label) in
                            Text(label).font(.caption.weight(.semibold))
                                .frame(width: 50)
                        }
                    }
                    Divider()
                    ForEach(appState.personas) { p in
                        GridRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.code).font(.body.monospaced())
                                Text(p.displayName).font(.caption2).foregroundStyle(.secondary)
                            }
                            ForEach(weekdays, id: \.0) { (weekday, _) in
                                Toggle("", isOn: ruleBinding(persona: p.code, weekday: weekday))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .frame(width: 50)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .background(.background.secondary)
            .border(.separator)

            Divider()

            HStack {
                Stepper(value: $year, in: 2020...2099, step: 1) {
                    Text("Year: \(year)").font(.headline)
                }
                .frame(width: 220)

                Button {
                    runGeneration()
                } label: {
                    Label("Generate \(year)", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if let r = lastResult {
                    Text("+\(r.inserted) created, \(r.skipped) already existed")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }

            Spacer()
        }
        .padding(20)
    }

    private func ruleBinding(persona: String, weekday: Int) -> Binding<Bool> {
        Binding(
            get: {
                appState.calendarRules
                    .first { $0.personaCode == persona && $0.weekday == weekday }
                    .map(\.enabled) ?? false
            },
            set: { newVal in
                let rule = CalendarRule(personaCode: persona, weekday: weekday, enabled: newVal)
                do {
                    try DatabaseService.shared.saveRule(rule)
                    appState.reloadCalendarRules()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        )
    }

    private func runGeneration() {
        do {
            lastResult = try CalendarService.generateYear(year, rules: appState.calendarRules)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

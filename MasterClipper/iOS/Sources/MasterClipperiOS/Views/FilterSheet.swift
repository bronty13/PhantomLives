import SwiftUI
import MasterClipperCore

struct FilterSheet: View {
    @EnvironmentObject private var appState: iOSAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Persona") {
                    Picker("Persona", selection: $appState.personaFilter) {
                        Text("All").tag(String?.none)
                        ForEach(appState.personas) { p in
                            Text("\(p.code) — \(p.displayName)").tag(String?.some(p.code))
                        }
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $appState.statusFilter) {
                        Text("All").tag(ClipStatus?.none)
                        ForEach(ClipStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage)
                                .tag(ClipStatus?.some(s))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Button(role: .destructive) {
                        appState.personaFilter = nil
                        appState.statusFilter = nil
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

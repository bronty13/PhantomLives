import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            PersonasSettingsTab()
                .tabItem { Label("Personas", systemImage: "person.2.fill") }

            CategoriesSettingsTab()
                .tabItem { Label("Categories", systemImage: "tag.fill") }

            SitesSettingsTab()
                .tabItem { Label("Sites", systemImage: "globe") }

            CalendarRulesTab()
                .tabItem { Label("Calendar Rules", systemImage: "calendar") }

            PostingSettingsTab()
                .tabItem { Label("Posting", systemImage: "paperplane.circle") }

            OllamaSettingsTab()
                .tabItem { Label("Ollama", systemImage: "brain") }

            ImportExportTab()
                .tabItem { Label("Import / Export", systemImage: "square.and.arrow.down.on.square") }

            FileLocationsTab()
                .tabItem { Label("File Locations", systemImage: "folder.badge.gearshape") }

            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive.fill.badge.timemachine") }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .editorialChrome()
    }
}

// Phase 2-3 stubs — populated in later phases.

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: Binding(
                    get: { appState.settings.colorScheme },
                    set: { var s = appState.settings; s.colorScheme = $0; appState.settings = s }
                )) {
                    Text("Match system").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Picker("Theme", selection: Binding(
                    get: { appState.settings.themeName },
                    set: { var s = appState.settings; s.themeName = $0; appState.settings = s }
                )) {
                    ForEach(Theme.all, id: \.id) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }

                ColorPicker("Accent color", selection: Binding(
                    get: { Color(hex: appState.settings.accentColorHex) ?? .accentColor },
                    set: { newVal in
                        var s = appState.settings
                        s.accentColorHex = newVal.toHex() ?? s.accentColorHex
                        appState.settings = s
                    }
                ), supportsOpacity: false)

                Slider(value: Binding(
                    get: { appState.settings.fontSize },
                    set: { var s = appState.settings; s.fontSize = $0; appState.settings = s }
                ), in: 11...18, step: 1) {
                    Text("Font size")
                } minimumValueLabel: { Text("11") } maximumValueLabel: { Text("18") }
                .frame(maxWidth: 360)
            }

            Section("Defaults") {
                TextField("Operator name", text: Binding(
                    get: { appState.settings.operatorName },
                    set: { var s = appState.settings; s.operatorName = $0; appState.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

                Picker("Default persona", selection: Binding(
                    get: { appState.settings.defaultPersonaCode },
                    set: { var s = appState.settings; s.defaultPersonaCode = $0; appState.settings = s }
                )) {
                    ForEach(appState.personas) { p in
                        Text("\(p.code) — \(p.displayName)").tag(p.code)
                    }
                }
            }

            Section("Advanced") {
                Toggle("Debug mode", isOn: Binding(
                    get: { appState.settings.debugMode },
                    set: { var s = appState.settings; s.debugMode = $0; appState.settings = s }
                ))
                Text("Reveals diagnostic columns and fields throughout the app — sort_order numbers, raw IDs, internal counters. Off by default to keep the UI clean.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// All Settings tabs (Personas, Categories, Sites, CalendarRules,
// Ollama, ImportExport, Backup) live in their own files.

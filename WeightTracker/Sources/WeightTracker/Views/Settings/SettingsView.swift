import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var goalWeightStr = ""
    @State private var startingWeightStr = ""
    @State private var heightStr = ""
    @State private var forecastDaysStr = ""
    @State private var customBackupPath = ""

    private var s: AppSettings { appState.settings }
    private var unit: WeightUnit { s.weightUnit }

    var body: some View {
        TabView {
            profileTab
                .tabItem { Label("Profile", systemImage: "person.fill") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush.fill") }
            chartsTab
                .tabItem { Label("Charts", systemImage: "chart.line.uptrend.xyaxis") }
            backupTab
                .tabItem { Label("Backup", systemImage: "externaldrive.fill") }
        }
        .frame(width: 520)
        .padding(20)
        .onAppear { populate() }
    }

    var profileTab: some View {
        Form {
            Section("Identity") {
                LabeledContent("Display Name") {
                    TextField("Your name", text: Binding(
                        get: { s.username },
                        set: { v in mutate { $0.username = v } }
                    ))
                }
            }

            Section("Weight Unit") {
                Picker("Unit", selection: Binding(
                    get: { s.weightUnit },
                    set: { v in mutate { $0.weightUnit = v } }
                )) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Goals") {
                LabeledContent("Goal Weight (\(unit.label))") {
                    TextField("e.g. 160", text: $goalWeightStr)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: goalWeightStr) { _, v in
                            mutate { $0.goalWeight = Double(v.replacingOccurrences(of: ",", with: ".")) }
                        }
                }
                LabeledContent("Starting Weight (\(unit.label))") {
                    TextField("Leave blank to use first entry", text: $startingWeightStr)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: startingWeightStr) { _, v in
                            mutate { $0.startingWeight = v.isEmpty ? nil : Double(v.replacingOccurrences(of: ",", with: ".")) }
                        }
                }
                LabeledContent("Height (inches)") {
                    TextField("e.g. 68 (optional, for BMI)", text: $heightStr)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: heightStr) { _, v in
                            mutate { $0.heightInches = v.isEmpty ? nil : Double(v) }
                        }
                }
            }

            Section("Forecast") {
                LabeledContent("Forecast Days") {
                    TextField("30", text: $forecastDaysStr)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: forecastDaysStr) { _, v in
                            if let d = Int(v), d > 0 { mutate { $0.forecastDays = d } }
                        }
                }
            }
        }
        .formStyle(.grouped)
    }

    var appearanceTab: some View {
        Form {
            Section("Theme") {
                let themeNames = Theme.all.map { $0.name }
                Picker("Theme", selection: Binding(
                    get: { s.themeName },
                    set: { v in mutate { $0.themeName = v } }
                )) {
                    ForEach(themeNames, id: \.self) { name in
                        HStack {
                            Circle()
                                .fill(Theme.named(name).accentColor)
                                .frame(width: 12, height: 12)
                            Text(name)
                        }
                        .tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Accent Color") {
                ColorPicker("Accent Color", selection: Binding(
                    get: { Color(hex: s.accentColorHex) ?? .blue },
                    set: { c in
                        if let hex = c.hexString { mutate { $0.accentColorHex = hex } }
                    }
                ))
            }

            Section("Font") {
                LabeledContent("Font Family") {
                    TextField("Leave blank for system font", text: Binding(
                        get: { s.fontName },
                        set: { v in mutate { $0.fontName = v } }
                    ))
                }
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: Binding(
                        get: { s.fontSize },
                        set: { v in mutate { $0.fontSize = v } }
                    ), in: 10...20, step: 0.5)
                    .frame(width: 140)
                    Text(String(format: "%.1f pt", s.fontSize))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    var chartsTab: some View {
        Form {
            Section("Default Chart") {
                Picker("Style", selection: Binding(
                    get: { s.chartStyle },
                    set: { v in mutate { $0.chartStyle = v } }
                )) {
                    ForEach(ChartStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Overlays") {
                Toggle("Show Trend Line by default", isOn: Binding(
                    get: { s.showTrendLine },
                    set: { v in mutate { $0.showTrendLine = v } }
                ))
                Toggle("Show Goal Line by default", isOn: Binding(
                    get: { s.showGoalLine },
                    set: { v in mutate { $0.showGoalLine = v } }
                ))
            }
        }
        .formStyle(.grouped)
    }

    var backupTab: some View {
        Form {
            Section("Automatic Backup") {
                Toggle("Enable automatic backup on launch", isOn: Binding(
                    get: { s.autoBackupEnabled },
                    set: { v in mutate { $0.autoBackupEnabled = v } }
                ))

                Stepper("Retention: \(s.backupRetentionDays) days", value: Binding(
                    get: { s.backupRetentionDays },
                    set: { v in mutate { $0.backupRetentionDays = v } }
                ), in: 1...365)
            }

            Section("Backup Location") {
                LabeledContent("Path") {
                    TextField("Default: ~/Downloads/WeightTracker/", text: $customBackupPath)
                        .onChange(of: customBackupPath) { _, v in
                            mutate { $0.backupPath = v }
                        }
                }
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        customBackupPath = url.path
                        mutate { $0.backupPath = url.path }
                    }
                }
                .buttonStyle(.bordered)
                Button("Backup Now") {
                    Task.detached(priority: .background) {
                        try? await BackupService.performBackup(to: appState.settingsStore.resolvedBackupPath)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
    }

    private func populate() {
        let unit = s.weightUnit
        if let gw = s.goalWeight {
            goalWeightStr = String(format: "%.1f", unit == .lbs ? gw : gw * 0.453592)
        }
        if let sw = s.startingWeight {
            startingWeightStr = String(format: "%.1f", unit == .lbs ? sw : sw * 0.453592)
        }
        if let h = s.heightInches { heightStr = String(format: "%.0f", h) }
        forecastDaysStr = "\(s.forecastDays)"
        customBackupPath = s.backupPath
    }

    private func mutate(_ block: (inout AppSettings) -> Void) {
        var copy = appState.settings
        block(&copy)
        appState.settings = copy
        appState.recomputeStats()
    }
}

extension Color {
    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

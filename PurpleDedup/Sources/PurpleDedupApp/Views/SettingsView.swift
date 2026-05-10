import SwiftUI
import PurpleDedupCore

/// Settings tab/pane. Phase 4 ships the Backup section (per PhantomLives convention)
/// and a developer toggle for the cached engine. EXIF prefs, smart-select rules, and
/// thumbnail-cache controls land in later phases.
struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var updaterController = UpdaterController.shared
    @State private var lastRunStatus: String?

    var body: some View {
        TabView {
            backupTab
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
            engineTab
                .tabItem { Label("Engine", systemImage: "gauge.with.dots.needle.bottom.50percent") }
            rulesTab
                .tabItem { Label("Rules", systemImage: "list.number") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        // Bumped from 600×460. The Rules tab has 11 rules + folder-priority
        // editor below; the previous size truncated descriptions and let the
        // folder editor disappear off the bottom. Tabs share a frame so we
        // pick the maximum the busiest tab needs.
        .frame(width: 720, height: 640)
    }

    /// Smart-select rule chain editor. Two halves: an ordered + togglable list
    /// of every available rule (move up/down to change priority), and the
    /// folder-priority list used by the `folderPriority` rule when it appears
    /// in the chain. Order matters everywhere — first rule that has an
    /// opinion wins.
    ///
    /// Wrapped in a ScrollView because the rule list (11 rules + descriptions)
    /// + folder editor reliably overflows even the bumped 640px tab height
    /// when several disabled rules are visible. Without the scroll wrapper
    /// the bottom rules and the folder-priority section dropped off-screen
    /// with no way to reach them.
    private var rulesTab: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart-select rule chain").font(.headline)
                    Text("When PurpleDedup picks the keeper from a duplicate group, it walks this list top-to-bottom. The first rule that has an opinion wins; ties fall through to the next rule. Use the arrows to reorder.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ruleChainEditor
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder priority").font(.headline)
                    Text("Used by the Folder priority rule. Earlier-listed folders beat later-listed ones; files outside every listed folder fall through to the next rule.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                folderPriorityEditor
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ruleChainEditor: some View {
        let names = settingsStore.settings.selectionRuleNames
        let known = Set(Rule.allCases.map(\.rawValue))
        let activeRules = names.compactMap { Rule(rawValue: $0) }
        let activeSet = Set(names).intersection(known)
        let inactiveRules = Rule.allCases.filter { !activeSet.contains($0.rawValue) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(activeRules.enumerated()), id: \.element) { idx, rule in
                ruleRow(rule: rule, position: idx, total: activeRules.count, active: true)
            }
            if !inactiveRules.isEmpty {
                Text("Disabled rules").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(inactiveRules, id: \.self) { rule in
                    ruleRow(rule: rule, position: -1, total: 0, active: false)
                }
            }
        }
    }

    private func ruleRow(rule: Rule, position: Int, total: Int, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if active {
                Text("\(position + 1).")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 1)
            } else {
                // The disabled-rule rows used a centered "·" character that
                // rendered as a faint smudge at the column edge. A muted
                // "off" icon is clearer at a glance.
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                Text(rule.helpText)
                    .font(.caption2).foregroundStyle(.secondary)
                    // `fixedSize(horizontal: false, vertical: true)` lets the
                    // text wrap naturally on its parent's width instead of
                    // truncating mid-word with an ellipsis. Combined with the
                    // ScrollView wrapping the whole tab, vertical growth is
                    // fine.
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if active {
                Button {
                    moveRule(rule: rule, direction: -1)
                } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(position == 0)

                Button {
                    moveRule(rule: rule, direction: 1)
                } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(position == total - 1)

                Button {
                    settingsStore.settings.selectionRuleNames.removeAll { $0 == rule.rawValue }
                } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove this rule from the chain")
            } else {
                Button {
                    settingsStore.settings.selectionRuleNames.append(rule.rawValue)
                } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("Add this rule to the end of the chain")
            }
        }
        .padding(.vertical, 4)
    }

    private func moveRule(rule: Rule, direction: Int) {
        var names = settingsStore.settings.selectionRuleNames
        guard let i = names.firstIndex(of: rule.rawValue) else { return }
        let j = i + direction
        guard j >= 0 && j < names.count else { return }
        names.swapAt(i, j)
        settingsStore.settings.selectionRuleNames = names
    }

    private var folderPriorityEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Button("Add folder…") { pickPriorityFolder() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if settingsStore.settings.folderPriority.isEmpty {
                Text("No folders set. Add at least one for the Folder priority rule to take effect.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(settingsStore.settings.folderPriority.enumerated()), id: \.offset) { idx, path in
                    HStack(spacing: 6) {
                        Text("\(idx + 1).").font(.caption.monospaced())
                            .foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                        Text(path)
                            .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            moveFolderPriority(path: path, direction: -1)
                        } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(idx == 0)

                        Button {
                            moveFolderPriority(path: path, direction: 1)
                        } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless)
                        .disabled(idx == settingsStore.settings.folderPriority.count - 1)

                        Button {
                            settingsStore.settings.folderPriority.removeAll { $0 == path }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func moveFolderPriority(path: String, direction: Int) {
        var list = settingsStore.settings.folderPriority
        guard let i = list.firstIndex(of: path) else { return }
        let j = i + direction
        guard j >= 0 && j < list.count else { return }
        list.swapAt(i, j)
        settingsStore.settings.folderPriority = list
    }

    private func pickPriorityFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !settingsStore.settings.folderPriority.contains(path) {
                settingsStore.settings.folderPriority.append(path)
            }
        }
    }

    private var backupTab: some View {
        Form {
            Toggle("Run backup on launch", isOn: Binding(
                get: { settingsStore.settings.autoBackupEnabled },
                set: { settingsStore.settings.autoBackupEnabled = $0 }
            ))

            Section("Location") {
                HStack {
                    Text(settingsStore.resolvedBackupPath.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { pickBackupFolder() }
                }
                .help("Backup archives are written here. Default: ~/Downloads/PurpleDedup backup/")
            }

            Section("Retention") {
                HStack {
                    Stepper(
                        value: Binding(
                            get: { settingsStore.settings.backupRetentionDays },
                            set: { settingsStore.settings.backupRetentionDays = $0 }
                        ),
                        in: 0...365
                    ) {
                        Text("Keep \(settingsStore.settings.backupRetentionDays) day(s)")
                    }
                }
                .help("0 = keep forever. Trim only touches files prefixed PurpleDedup-.")
            }

            Section("Last backup") {
                Text(settingsStore.settings.lastBackupAt ?? "(none yet)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                if let s = lastRunStatus {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
                Button("Run backup now") { runNow() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var engineTab: some View {
        Form {
            Toggle("Use cached scan engine", isOn: Binding(
                get: { settingsStore.settings.useCachedEngine },
                set: { settingsStore.settings.useCachedEngine = $0 }
            ))
            .help("Cached scans skip re-hashing unchanged files. Disable only for debugging.")

            Section("Cache location") {
                Text(PurpleDedup.supportDirectoryURL.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            Section("Threshold-without-rescan") {
                Text("After a scan, adjusting the photo or video threshold re-clusters from the cached fingerprints — no re-hashing needed. Adjust the steppers in the main window.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Deletion destination") {
                let stage = settingsStore.settings.stageFolderPath ?? ""
                if stage.isEmpty {
                    Text("Files marked DELETE go to the Finder Trash (default).")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Files marked DELETE are moved to:")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(stage)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                    Text("(Operation log records each move so Cmd+Z still restores from this folder.)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose stage folder…") { pickStageFolder() }
                        .buttonStyle(.bordered).controlSize(.small)
                    if !stage.isEmpty {
                        Button("Reset to Trash") {
                            settingsStore.settings.stageFolderPath = nil
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pickStageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this folder"
        panel.message = "Files marked DELETE will be moved here instead of the Finder Trash."
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.settings.stageFolderPath = url.path
        }
    }

    private func pickBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this folder"
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.settings.backupPath = url.path
        }
    }

    private func runNow() {
        let supportDir = PurpleDedup.supportDirectoryURL
        do {
            try FileManager.default.createDirectory(
                at: supportDir, withIntermediateDirectories: true
            )
            let url = try BackupService.runBackup(
                supportDir: supportDir,
                backupDir: settingsStore.resolvedBackupPath
            )
            _ = BackupService.trimOldBackups(
                in: settingsStore.resolvedBackupPath,
                retentionDays: settingsStore.settings.backupRetentionDays
            )
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            settingsStore.settings.lastBackupAt = f.string(from: Date())
            lastRunStatus = "Wrote \(url.lastPathComponent)"
        } catch {
            lastRunStatus = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Updates tab

    private var updatesTab: some View {
        Form {
            Section {
                Toggle(isOn: $updaterController.automaticallyChecksForUpdates) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check for updates automatically")
                        Text("Sparkle polls the appcast every 24 hours when this is on. Even off, you can run **Check for Updates…** from the PurpleDedup menu.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Automatic checks").font(.headline)
            }

            Section {
                HStack {
                    Button("Check now") {
                        updaterController.checkForUpdates()
                    }
                    .disabled(!updaterController.canCheckForUpdates)
                    Spacer()
                    if let last = updaterController.lastUpdateCheckDate {
                        Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Never checked")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Manual check").font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This build trusts updates signed with the developer's EdDSA key. Updates without a valid signature are refused — Sparkle won't run an unsigned binary even if the appcast points at one.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Feed: \(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "(missing)")")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
            } header: {
                Text("Security").font(.headline)
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }
}

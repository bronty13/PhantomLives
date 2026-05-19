import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            TagsSettingsView()
                .tabItem { Label("Tags", systemImage: "tag") }
            ConversionSettingsView()
                .tabItem { Label("Conversion", systemImage: "wand.and.stars") }
            DevicesSettingsView()
                .tabItem { Label("Devices", systemImage: "externaldrive.connected.to.line.below") }
            TransferSettingsView()
                .tabItem { Label("Transfer", systemImage: "network") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("lutFolderPath") private var lutFolderPath: String = ""
    @AppStorage("importLUTsFromFCP") private var importLUTsFromFCP: Bool = true
    @AppStorage("importLUTsFromResolve") private var importLUTsFromResolve: Bool = true
    @AppStorage("applyLUTsToThumbnails") private var applyLUTsToThumbnails: Bool = false
    @AppStorage("applyLUTToExportedFrames") private var applyLUTToExports: Bool = true
    @AppStorage("autoApplySuggestedLUT") private var autoApplySuggestedLUT: Bool = true
    @AppStorage("defaultViewOnLaunch") private var defaultViewOnLaunch: String = "list"
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage(KynoCompatibility.modeKey) private var kynoMode: Bool = false
    @AppStorage(WorkspaceCacheService.enabledDefaultsKey)
    private var workspaceCacheEnabled: Bool = false
    /// C35 — age cap (days) for the workspace-cache sidecar prune.
    /// 0 disables age-based eviction so prune is orphan-only.
    @AppStorage("sidecarMaxAgeDays") private var sidecarMaxAgeDays: Int = 0
    /// C36 — auto-prune-on-launch interval (days). 0 disables auto-
    /// prune so the button-only flow is the entire prune story.
    @AppStorage(AppState.autoPruneIntervalKey)
    private var sidecarAutoPruneIntervalDays: Int = 0

    var body: some View {
        Form {
            Section("Kyno Compatibility") {
                Toggle(isOn: Binding(
                    get: { kynoMode && KynoCompatibility.allDrivenKeysMatchKyno() },
                    set: { newValue in
                        if newValue {
                            KynoCompatibility.apply()
                        } else {
                            KynoCompatibility.restore()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Kyno keyboard & defaults")
                        Text("Flips J/L to 5-sec jumps, 'Thumbnail' label, numeric sort, no auto-drilldown on camera mounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Kyno-familiar shortcuts (X mute, ⌘⇧D drilldown, ⌘U subclip export, ⌃⌥E zebra, ⌃⌥W widescreen, ⌥⇧O default-app open, ⌘⌥M focus metadata) are wired regardless of this toggle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Picker("Default view on launch", selection: $defaultViewOnLaunch) {
                    Text("List").tag("list")
                    Text("Grid").tag("grid")
                    Text("Detail").tag("detail")
                }
                Text("Mid-session switches still work; this decides what to land on every time the app opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Text("Match System follows macOS Appearance (System Settings → Appearance). Pick Light or Dark to override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Workspace Cache (Shared NAS / SAN)") {
                Toggle(isOn: $workspaceCacheEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write shared metadata cache next to media")
                        Text("Drops a hidden .purplereel/<file>.json sidecar next to each clip carrying rating, tags, markers, subclips, and log fields. A second user opening the same volume inherits everything without rescanning — and AVAsset probes (codec / dims / fps / duration) skip too. Best-effort writes; read-only volumes silently no-op.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Concurrent edits between two users on the same clip are last-writer-wins. Thumbnails and waveforms stay local — they regenerate cheaply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // C32 (G1) — orphan-sidecar prune. Walks each
                // workspace root and deletes any `.purplereel/*.json`
                // whose source file no longer exists. C35 — also
                // accepts an age cap so sidecars that have aged out
                // get pruned even when their source file still
                // exists (stale-by-time, not stale-by-orphan).
                if !appState.workspaceRoots.isEmpty {
                    HStack {
                        Button("Prune Orphaned Sidecars…") {
                            pruneOrphanedSidecars()
                        }
                        Spacer()
                        Text("Walks each workspace root and deletes .purplereel/ entries whose source file is gone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    // C35 — age-based eviction policy. 0 disables
                    // the age cap so prune-by-orphan-only stays the
                    // default. Non-zero values combine with the
                    // orphan check — either reason deletes.
                    HStack {
                        Stepper(value: $sidecarMaxAgeDays, in: 0...365) {
                            HStack(spacing: 4) {
                                Text("Also delete sidecars older than")
                                Text("\(sidecarMaxAgeDays)")
                                    .monospacedDigit()
                                Text("day(s)")
                            }
                            .font(.callout)
                        }
                        Spacer()
                        Text(sidecarMaxAgeDays == 0
                              ? "0 disables age-based eviction (orphan-only)."
                              : "Older sidecars are deleted on the next prune run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    // C36 — auto-prune-on-launch cadence. 0 = button-
                    // only. Non-zero fires the same prune the button
                    // does, scheduled to run at most once per N days.
                    HStack {
                        Stepper(value: $sidecarAutoPruneIntervalDays, in: 0...90) {
                            HStack(spacing: 4) {
                                Text("Auto-prune on launch every")
                                Text("\(sidecarAutoPruneIntervalDays)")
                                    .monospacedDigit()
                                Text("day(s)")
                            }
                            .font(.callout)
                        }
                        Spacer()
                        Text(sidecarAutoPruneIntervalDays == 0
                              ? "0 disables auto-prune (manual button only)."
                              : "Runs in the background after launch when due. Same rules as the button.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Section("LUTs") {
                HStack {
                    TextField("LUTs folder", text: $lutFolderPath,
                                prompt: Text("~/Library/Application Support/PurpleReel/LUTs"))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK {
                            lutFolderPath = panel.url?.path ?? ""
                        }
                    }
                    Button("Open") {
                        let p = lutFolderPath.isEmpty
                            ? (NSHomeDirectory() as NSString)
                                .appendingPathComponent("Library/Application Support/PurpleReel/LUTs")
                            : lutFolderPath
                        try? FileManager.default.createDirectory(
                            atPath: p, withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(URL(fileURLWithPath: p))
                    }
                }
                Toggle("Import LUTs from Final Cut Pro", isOn: $importLUTsFromFCP)
                    .onChange(of: importLUTsFromFCP) { _, _ in
                        LUTLibraryService.invalidate()
                    }
                Toggle("Import LUTs from DaVinci Resolve", isOn: $importLUTsFromResolve)
                    .onChange(of: importLUTsFromResolve) { _, _ in
                        LUTLibraryService.invalidate()
                    }
                Toggle("Auto-apply suggested LUT on clip load", isOn: $autoApplySuggestedLUT)
                Text("Matches log-profile keywords in the filename (SLog3, V-Log, LogC, HLG, etc.) against discovered LUTs. User-managed PurpleReel LUTs win ties over FCP / Resolve.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Apply detected LUTs to thumbnails", isOn: $applyLUTsToThumbnails)
                Toggle("Apply current LUT to exported frames", isOn: $applyLUTToExports)
                Text("When on (default, matches Kyno 1.8+), ⌘⇧E bakes the active LUT into the PNG it writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Cache") {
                Button("Clear Thumbnail Cache") {
                    ThumbnailService.purgeCache()
                }
                .help("Wipes ~/Library/Application Support/PurpleReel/thumbnails")
            }
        }
        .formStyle(.grouped)
    }

    /// C32 (G1) — sweep each workspace root for `.purplereel/*.json`
    /// sidecars whose source file is gone and delete them. Reports
    /// the aggregated result in an NSAlert. Runs on a background
    /// Task so a large NAS scan doesn't freeze Settings.
    private func pruneOrphanedSidecars() {
        let roots = appState.workspaceRoots
        // C35 — age cap passed by value into the detached task;
        // 0 disables age-based eviction (caller-side nil is the
        // service-level "no age limit", expressed here as 0 →
        // `nil` so the same Settings stepper handles both).
        let ageDays = sidecarMaxAgeDays > 0 ? sidecarMaxAgeDays : nil
        Task.detached(priority: .userInitiated) {
            var totalScanned = 0
            var totalDeleted = 0
            var totalFailed = 0
            for root in roots {
                let r = WorkspaceCacheService.pruneOrphans(
                    under: root, maxAgeDays: ageDays
                )
                totalScanned += r.scanned
                totalDeleted += r.deleted.count
                totalFailed += r.failed.count
            }
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Pruned \(totalDeleted) orphaned sidecar(s)"
                var lines: [String] = []
                lines.append("Scanned: \(totalScanned)")
                lines.append("Deleted: \(totalDeleted)")
                if totalFailed > 0 {
                    lines.append("Failed: \(totalFailed) (likely permission denied)")
                }
                lines.append("Across \(roots.count) workspace root(s).")
                alert.informativeText = lines.joined(separator: "\n")
                alert.runModal()
            }
        }
    }
}

// MARK: - Tags

struct TagsSettingsView: View {
    @State private var userTags: [String] = (UserDefaults.standard.array(forKey: "userDefinedTags") as? [String]) ?? []
    @State private var newTag: String = ""
    @State private var importStatus: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("User-defined Tags").font(.headline)
            Text("Tags pre-populated when typing in the Tags field on a clip.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(userTags, id: \.self) { tag in
                    Text(tag)
                }
                .onDelete { idx in
                    userTags.remove(atOffsets: idx)
                    save()
                }
            }
            HStack {
                TextField("New tag", text: $newTag)
                Button("Add") { commitNew() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            HStack {
                Button("Import…")  { importTags() }
                Button("Export…")  { exportTags() }
                    .disabled(userTags.isEmpty)
                Spacer()
                if !importStatus.isEmpty {
                    Text(importStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private func commitNew() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !userTags.contains(trimmed) else { return }
        userTags.append(trimmed)
        newTag = ""
        save()
    }

    private func save() {
        UserDefaults.standard.set(userTags, forKey: "userDefinedTags")
    }

    /// JSON import — accepts both `["a", "b", "c"]` and
    /// `{"tags":["a","b","c"]}` shapes. Union'd with the existing
    /// set; never destructive.
    private func importTags() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            absorb(arr)
        } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["tags"] as? [String] {
            absorb(arr)
        } else {
            importStatus = "Couldn't parse \(url.lastPathComponent) as JSON tags."
        }
    }

    private func absorb(_ incoming: [String]) {
        let cleaned = incoming.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let before = userTags.count
        for tag in cleaned where !userTags.contains(tag) {
            userTags.append(tag)
        }
        save()
        importStatus = "Imported \(userTags.count - before) new tag(s)."
    }

    private func exportTags() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PurpleReel-tags.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let payload: [String: Any] = ["tags": userTags]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: url, options: .atomic)
            importStatus = "Wrote \(userTags.count) tag(s) to \(url.lastPathComponent)."
        } catch {
            importStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Conversion

struct ConversionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("maxParallelConversions") private var maxParallel: Int = 1
    @AppStorage("maxParallelCPUConversions") private var maxParallelCPU: Int = 3
    @AppStorage("transcodeOutputDir") private var outputDir: String = ""
    @AppStorage("preserveTranscodeTimestamps") private var preserveMtime: Bool = false

    @State private var customPresets: [TranscodePreset] = []
    @State private var customPresetStatus: String = ""
    @State private var exportTargetPresetID: String = ""

    var body: some View {
        Form {
            Section("Queue") {
                Stepper("Hardware-encoder conversions (H.264 / HEVC): \(maxParallel)",
                        value: $maxParallel, in: 1...4)
                Text("Apple Silicon's hardware video encoder serializes — running two H.264 / HEVC jobs in parallel against it doesn't actually speed anything up. Default 1; raising past 2 rarely helps real workloads.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("CPU-codec conversions (ProRes / DNxHR / Cineform / rewrap): \(maxParallelCPU)",
                        value: $maxParallelCPU, in: 1...8)
                Text("CPU codecs and pass-through rewraps can run in parallel without contending for shared hardware. 3 is the default sweet spot on most Apple Silicon machines; bump to 4-6 on M2 Max / M3 Max if you're transcoding 4K ProRes batches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Output") {
                HStack {
                    TextField("Output folder", text: $outputDir,
                                prompt: Text("~/Downloads/PurpleReel/transcoded"))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK {
                            outputDir = panel.url?.path ?? ""
                        }
                    }
                }
                Toggle("Preserve source file timestamps", isOn: $preserveMtime)
                Text("Sets the transcoded output's modified-date to match the source. Useful for archival pipelines that key off mtime; off by default so freshly-rendered files show as just-modified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Clear Conversion History") {
                        appState.transcodeQueue.clearDone()
                    }
                    .disabled(appState.transcodeQueue.done.isEmpty)
                    Text("\(appState.transcodeQueue.done.count) finished job(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Custom Presets") {
                if customPresets.isEmpty {
                    Text("No custom presets yet. Import a JSON file someone shared with you, or export a built-in preset as a starting template you can edit in TextEdit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customPresets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.body)
                                HStack(spacing: 6) {
                                    Text(preset.category.displayName)
                                    Text("·")
                                    Text(preset.isFFmpeg ? "ffmpeg" : "AVFoundation")
                                    Text("·")
                                    Text(".\(preset.fileExtension)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reveal") {
                                if let dir = CustomPresets.directory() {
                                    let url = dir.appendingPathComponent("\(preset.id).json")
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .controlSize(.small)
                            Button("Delete", role: .destructive) {
                                CustomPresets.delete(preset)
                                refreshCustoms()
                                customPresetStatus = "Removed “\(preset.name)”."
                            }
                            .controlSize(.small)
                        }
                    }
                }
                HStack {
                    Button("Import…") { importPreset() }
                    Menu("Export Built-in as Custom…") {
                        ForEach(TranscodePreset.all) { preset in
                            Button(preset.name) { exportPreset(preset) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button("Reveal Folder") {
                        if let dir = CustomPresets.directory() {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                    Spacer()
                }
                if !customPresetStatus.isEmpty {
                    Text(customPresetStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Customs live in ~/Library/Application Support/PurpleReel/CustomPresets/<id>.json. Each is a Codable TranscodePreset — edit in TextEdit, restart the app to pick up edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshCustoms)
    }

    private func refreshCustoms() {
        customPresets = CustomPresets.load()
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = try CustomPresets.import(from: url)
            refreshCustoms()
            customPresetStatus = "Imported “\(preset.name)” (\(preset.id))."
        } catch {
            customPresetStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportPreset(_ preset: TranscodePreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.id).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CustomPresets.export(preset, to: url)
            customPresetStatus = "Exported “\(preset.name)” to \(url.lastPathComponent)."
        } catch {
            customPresetStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Devices

struct DevicesSettingsView: View {
    @AppStorage("selectDeviceWhenConnected") private var selectOnConnect: Bool = true
    @AppStorage("autoDrilldownCameraMedia") private var autoDrilldownCamera: Bool = true
    @AppStorage("showDMGInDevices") private var showDMG: Bool = false
    @AppStorage("reactLocalDrives") private var reactLocal: Bool = true
    @AppStorage("reactRemovableDrives") private var reactRemovable: Bool = true
    @AppStorage("reactNetworkDrives") private var reactNetwork: Bool = true

    var body: some View {
        Form {
            Section("Removable devices") {
                Toggle("Select device when connected", isOn: $selectOnConnect)
                Toggle("Automatically turn on drilldown for camera media",
                        isOn: $autoDrilldownCamera)
                Toggle("Show disk images (DMG) in devices", isOn: $showDMG)
            }
            Section("React to changes on") {
                Toggle("Local drives", isOn: $reactLocal)
                Toggle("Removable drives", isOn: $reactRemovable)
                Toggle("Network drives", isOn: $reactNetwork)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Transfer

struct TransferSettingsView: View {
    @AppStorage("slackWebhookURL") private var slackWebhookURL: String = ""
    @AppStorage("sidecarFileExtension") private var sidecarExt: String = "lpmd"

    var body: some View {
        Form {
            Section("SFTP Endpoints") {
                Text("Configure per-job via Toolbar → SFTP Delivery. Saved destinations persist in the in-app picker.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Slack Notification") {
                TextField("Web-hook URL", text: $slackWebhookURL)
            }
            Section("Sidecar Files") {
                Picker("Sidecar file extension", selection: $sidecarExt) {
                    Text(".lpmd").tag("lpmd")
                    Text(".xmp").tag("xmp")
                    Text(".json").tag("json")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @AppStorage("thumbnailLoadingPerformance") private var thumbPerf: String = "medium"
    @AppStorage("ignoredFilesGlob") private var ignoredGlob: String = ""
    @AppStorage("useDropFrameTimecode") private var dropFrameTC: Bool = true
    @AppStorage("useZeroBasedTimecode") private var zeroBasedTC: Bool = false
    @AppStorage("confirmCopyAndMove") private var confirmCopyMove: Bool = true
    @AppStorage("debugMode") private var debugMode: Bool = false
    @AppStorage("metadataStorage") private var metadataStorage: String = "hidden"
    @AppStorage("fileCountSafetyLimit") private var fileCountLimit: Int = 50_000

    var body: some View {
        Form {
            Section("Performance") {
                Picker("Thumbnail loading performance", selection: $thumbPerf) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                TextField("Ignored files and folders", text: $ignoredGlob,
                            prompt: Text("e.g.: tmp;*backup"))
                Stepper("Warn when workspace exceeds \(fileCountLimit) files",
                        value: $fileCountLimit, in: 1_000...1_000_000, step: 5_000)
                Text("Soft warning only — the catalogue still loads. Raise it if you regularly browse season-of-dailies sized workspaces; lower it to nudge yourself toward narrower roots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Timecode") {
                Toggle("Use drop-frame timecode", isOn: $dropFrameTC)
                Toggle("Use zero-based timecode", isOn: $zeroBasedTC)
                Text("PurpleReel currently normalizes every clip to start at 00:00:00:00, so this toggle's display effect is the same either way. It's reserved for a future build that surfaces container-embedded source timecode (e.g. ARRI / RED / camera-card TC tracks).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Behavior") {
                Toggle("Confirm copy and move in Navigator",
                        isOn: $confirmCopyMove)
                Toggle("Activate debug mode", isOn: $debugMode)
            }
            Section("Metadata") {
                Picker("Store metadata in", selection: $metadataStorage) {
                    Text("Hidden directories (default)").tag("hidden")
                    Text("Sidecar files").tag("sidecar")
                }
            }
            Section("Reset") {
                Button("Reset All Preferences…") {
                    confirmAndResetAllPreferences()
                }
                Text("Clears every PurpleReel preference (sidebar collapse, sort, columns, filters, AI overrides, …). Window state and the catalog DB are NOT touched. Restart PurpleReel after confirming.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func confirmAndResetAllPreferences() {
        let alert = NSAlert()
        alert.messageText = "Reset all PurpleReel preferences?"
        alert.informativeText = "Every Settings value (across all panes), persisted sort / filter / drilldown / column state, and the Recently Used Convert presets will be cleared. The catalog DB, your media, and the auto-backup history are not affected.\n\nQuit and relaunch after confirming."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Wipe every key under our bundle ID. The user-facing
        // 'Reset Window State' (Window menu) is the separate path
        // for layout corruption — this is the prefs-only reset.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}

struct BackupSettingsView: View {
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled: Bool = true
    @AppStorage("backupRetentionDays") private var backupRetentionDays: Int = 14
    @AppStorage("backupPath") private var backupPath: String = ""

    @State private var backups: [URL] = []
    @State private var status: String = ""
    @State private var lastBackup: Date? = BackupService.lastBackupDate

    private var resolvedBackupDir: String {
        if !backupPath.isEmpty { return backupPath }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Downloads/PurpleReel backup")
    }

    var body: some View {
        Form {
            Section("Auto-backup") {
                Toggle("Backup on launch", isOn: $autoBackupEnabled)
                Stepper("Retention: \(backupRetentionDays) days · 0 keeps forever",
                        value: $backupRetentionDays, in: 0...365)
                HStack {
                    Text("Last backup:").foregroundStyle(.secondary)
                    Text(lastBackup.map { Self.longDate($0) } ?? "never")
                }
                .font(.caption)
            }
            Section("Backup location") {
                HStack {
                    TextField("Backup directory", text: $backupPath,
                                prompt: Text("~/Downloads/PurpleReel backup"))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK {
                            backupPath = panel.url?.path ?? ""
                        }
                    }
                    Button("Default") { backupPath = "" }
                        .disabled(backupPath.isEmpty)
                }
                Text(resolvedBackupDir)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Button("Reveal in Finder") {
                        let url = URL(fileURLWithPath: resolvedBackupDir)
                        try? FileManager.default.createDirectory(
                            at: url, withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Run Backup Now") {
                        runBackupNow()
                    }
                    Spacer()
                }
            }
            Section("Recent backups") {
                if backups.isEmpty {
                    Text("No backups yet — relaunch the app or click \"Run Backup Now\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.self) { url in
                        BackupRow(url: url, onTest: { testBackup(url) },
                                    onRestore: { restoreBackup(url) },
                                    onRefresh: refreshList)
                    }
                }
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshList)
    }

    private func refreshList() {
        backups = (try? BackupService.listBackups()) ?? []
        lastBackup = BackupService.lastBackupDate
    }

    private func runBackupNow() {
        status = "Backing up…"
        DispatchQueue.global(qos: .utility).async {
            do {
                try BackupService.runBackup()
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                            forKey: "lastBackupAt")
                try? BackupService.trimOld()
                DispatchQueue.main.async {
                    status = "✓ Backup complete."
                    refreshList()
                }
            } catch {
                DispatchQueue.main.async {
                    status = "Backup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func testBackup(_ url: URL) {
        status = "Verifying \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .utility).async {
            let result: (ok: Bool, summary: String) =
                (try? BackupService.verify(archive: url)) ?? (false, "verify threw")
            DispatchQueue.main.async {
                status = "\(url.lastPathComponent): \(result.summary)"
            }
        }
    }

    private func restoreBackup(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Restore from \(url.lastPathComponent)?"
        alert.informativeText = "This replaces PurpleReel's current state with the contents of the backup. A safety backup of the current state will be created first. You must quit and relaunch PurpleReel after restoring."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        status = "Restoring \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .utility).async {
            do {
                try BackupService.restore(from: url)
                DispatchQueue.main.async {
                    status = "✓ Restored. Quit and relaunch PurpleReel."
                    refreshList()
                }
            } catch {
                DispatchQueue.main.async {
                    status = "Restore failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

private struct BackupRow: View {
    let url: URL
    let onTest: () -> Void
    let onRestore: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.caption.monospaced())
                Text(modDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test", action: onTest)
                .controlSize(.small)
            Button("Restore", action: onRestore)
                .controlSize(.small)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }

    private var modDate: String {
        let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

struct AISettingsView: View {
    @AppStorage("whisperScriptPath") private var whisperScriptPath: String = ""
    @AppStorage("whisperModel") private var whisperModel: String = "turbo"
    @AppStorage("ollamaModel") private var ollamaModel: String = OllamaService.defaultModel

    @State private var ollamaReachable: Bool? = nil
    @State private var installedOllamaModels: [String] = []
    @State private var whisperScriptOK: Bool? = nil

    private let whisperModels = ["turbo", "tiny", "base", "small", "medium", "large-v3"]

    var body: some View {
        Form {
            Section("Whisper transcription") {
                HStack {
                    TextField("Script path", text: $whisperScriptPath,
                                prompt: Text(WhisperService.defaultScriptPath))
                    Button("Choose…") { pickScript() }
                    Button("Default") { whisperScriptPath = "" }
                        .disabled(whisperScriptPath.isEmpty)
                }
                Picker("Model", selection: $whisperModel) {
                    ForEach(whisperModels, id: \.self) { Text($0).tag($0) }
                }
                statusLabel(whisperScriptOK,
                             ok: "transcribe.py found",
                             bad: "transcribe.py not found at \(effectiveWhisperPath)")
                Text("First run downloads MLX-Whisper weights (~1 GB for turbo). Subsequent runs reuse them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ollama auto-describe") {
                HStack {
                    if installedOllamaModels.isEmpty {
                        TextField("Model name", text: $ollamaModel)
                    } else {
                        Picker("Model", selection: $ollamaModel) {
                            ForEach(installedOllamaModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Refresh") { refreshOllama() }
                }
                statusLabel(ollamaReachable,
                             ok: "Ollama is running at localhost:11434",
                             bad: "Ollama unreachable. Install from ollama.com and run `ollama serve`.")
                Text("Pull a small model for fast descriptions: `ollama pull llama3.2:1b`.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshOllama()
            checkWhisperScript()
        }
        .onChange(of: whisperScriptPath) { _, _ in checkWhisperScript() }
    }

    private var effectiveWhisperPath: String {
        whisperScriptPath.isEmpty ? WhisperService.defaultScriptPath : whisperScriptPath
    }

    private func pickScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            whisperScriptPath = url.path
        }
    }

    private func checkWhisperScript() {
        whisperScriptOK = FileManager.default.fileExists(atPath: effectiveWhisperPath)
    }

    private func refreshOllama() {
        Task {
            let reachable = await OllamaService.isReachable()
            let models = reachable ? await OllamaService.listInstalledModels() : []
            await MainActor.run {
                self.ollamaReachable = reachable
                self.installedOllamaModels = models
                if reachable, !models.isEmpty, !models.contains(self.ollamaModel) {
                    self.ollamaModel = models.first ?? self.ollamaModel
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ ok: Bool?, ok okText: String, bad badText: String) -> some View {
        if let ok {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? .green : .red)
                Text(ok ? okText : badText)
                    .font(.caption)
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PurpleReel \(AppVersion.display)").font(.headline)
            Text("Media management for Final Cut Pro, with on-device AI augmentation.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

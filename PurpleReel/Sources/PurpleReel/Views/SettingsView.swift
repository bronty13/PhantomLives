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
    @AppStorage("lutFolderPath") private var lutFolderPath: String = ""
    @AppStorage("importLUTsFromFCP") private var importLUTsFromFCP: Bool = true
    @AppStorage("importLUTsFromResolve") private var importLUTsFromResolve: Bool = true
    @AppStorage("applyLUTsToThumbnails") private var applyLUTsToThumbnails: Bool = false

    var body: some View {
        Form {
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
                Toggle("Import LUTs from DaVinci Resolve", isOn: $importLUTsFromResolve)
                Toggle("Apply detected LUTs to thumbnails", isOn: $applyLUTsToThumbnails)
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
}

// MARK: - Tags

struct TagsSettingsView: View {
    @State private var userTags: [String] = (UserDefaults.standard.array(forKey: "userDefinedTags") as? [String]) ?? []
    @State private var newTag: String = ""

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
                Button("Add") {
                    let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !userTags.contains(trimmed) else { return }
                    userTags.append(trimmed)
                    newTag = ""
                    save()
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func save() {
        UserDefaults.standard.set(userTags, forKey: "userDefinedTags")
    }
}

// MARK: - Conversion

struct ConversionSettingsView: View {
    @AppStorage("maxParallelConversions") private var maxParallel: Int = 1
    @AppStorage("transcodeOutputDir") private var outputDir: String = ""

    var body: some View {
        Form {
            Section("Queue") {
                Stepper("Maximum parallel conversions: \(maxParallel)",
                        value: $maxParallel, in: 1...8)
                Text("Native AVAssetExportSession can run concurrently but shares one hardware HEVC encoder; values > 2 typically don't speed up real workloads.")
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
                Button("Clear Conversion History") {
                    // Stub for now — transcode queue history is in-memory.
                }
            }
        }
        .formStyle(.grouped)
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
            }
            Section("Timecode") {
                Toggle("Use drop-frame timecode", isOn: $dropFrameTC)
                Toggle("Use zero-based timecode", isOn: $zeroBasedTC)
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
        }
        .formStyle(.grouped)
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

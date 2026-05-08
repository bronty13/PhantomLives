import SwiftUI
import AppKit

/// Default parent directory for exports. Per the PhantomLives convention,
/// every tool's user-facing output defaults to a subfolder of ~/Downloads/
/// named after the project, so all exports across all tools land in one
/// predictable place. The CLI then creates a `<contact>_<timestamp>`
/// subfolder inside this, e.g.
/// ~/Downloads/messages-exporter-gui/Sallie_20260427_172132/.
/// Created on demand the first time it's read.
func defaultOutputDir() -> URL {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let dir = downloads.appendingPathComponent("messages-exporter-gui", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// User-configurable export root. Stored in UserDefaults so the
/// Settings scene and the main window stay in sync.
enum SettingsKeys {
    static let outputDir       = "outputDirPath"
    static let transcribeOn    = "transcribeEnabled"
    static let transcribeModel = "transcribeModel"
    static let debugLogging    = "debugLogging"
    static let emojiMode       = "emojiMode"
    static let themePreference = "themePreference"
}

struct RootView: View {
    @EnvironmentObject private var runner: ExportRunner
    @EnvironmentObject private var presets: PresetStore

    @State private var contact = ""
    @State private var start: Date = Self.todayAtStartOfDay()
    @State private var end:   Date = Date()
    @State private var mode:  ExportMode = .sanitized
    @State private var showInstallSheet  = false
    @State private var showFDASheet      = false
    @State private var showCancelConfirm = false
    @State private var showSavePreset    = false

    @AppStorage(SettingsKeys.outputDir) private var outputDirPath: String = defaultOutputDir().path
    @AppStorage(SettingsKeys.transcribeOn) private var transcribeEnabled: Bool = false
    @AppStorage(SettingsKeys.transcribeModel) private var transcribeModelRaw: String = WhisperModel.turbo.rawValue
    @AppStorage(SettingsKeys.debugLogging) private var debugLogging: Bool = false
    @AppStorage(SettingsKeys.emojiMode) private var emojiRaw: String = EmojiMode.word.rawValue
    @AppStorage(SettingsKeys.themePreference) private var themeRaw: String = ThemePreference.system.rawValue

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        MissionThemeReader { theme in
            ZStack {
                LinearGradient(colors: [theme.bg1, theme.bg2],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    Sidebar(
                        showFDASheet: $showFDASheet,
                        applyRecent: applyRecent,
                        applyPreset: applyPreset
                    )
                    main(theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .preferredColorScheme(themePreference.colorScheme)
            .sheet(isPresented: $showInstallSheet) {
                InstallSheet(showInstallSheet: $showInstallSheet)
            }
            .sheet(isPresented: $showFDASheet) {
                FullDiskAccessSheet(showSheet: $showFDASheet)
            }
            .sheet(isPresented: $showSavePreset) {
                SavePresetSheet(
                    isPresented: $showSavePreset,
                    contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: start,
                    end: end,
                    mode: mode,
                    transcribe: transcribeEnabled,
                    transcribeModel: WhisperModel(rawValue: transcribeModelRaw) ?? .turbo,
                    emoji: EmojiMode(rawValue: emojiRaw) ?? .word
                )
                .environmentObject(presets)
            }
            .task {
                if runner.fdaStatus == .unknown {
                    runner.checkFullDiskAccess()
                }
                if runner.fdaStatus == .denied {
                    showFDASheet = true
                }
            }
            .onReceive(NotificationCenter.default
                        .publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if runner.fdaStatus != .granted {
                    runner.checkFullDiskAccess()
                }
            }
        }
    }

    @ViewBuilder
    private func main(_ t: MissionTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if runner.fdaStatus == .denied {
                FDABanner(showSheet: $showFDASheet)
            }

            header(t)

            StatTiles(pendingStart: start, pendingEnd: end)

            FormCard(
                contact: $contact,
                start: $start,
                end: $end,
                mode: $mode,
                transcribeEnabled: $transcribeEnabled,
                transcribeModelRaw: $transcribeModelRaw
            )

            RunStrip(
                canRun: !runner.isRunning && !contact.trimmingCharacters(in: .whitespaces).isEmpty,
                runAction: { Task { await runExport() } },
                cancelAction: { showCancelConfirm = true }
            )
            .confirmationDialog("Cancel export?",
                                isPresented: $showCancelConfirm,
                                titleVisibility: .visible) {
                Button("Stop export", role: .destructive) { runner.cancel() }
                Button("Keep running", role: .cancel) { }
            } message: {
                Text("The export is still in progress. Any attachments already written will remain in the output folder.")
            }

            LiveOutputCard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Spacer()
                VersionFooter()
            }
        }
        .padding(.horizontal, 22)
        // Generous top inset so the contact-name h1 (display 26pt with
        // negative tracking) breathes above the hidden-title-bar window
        // edge. The macOS traffic lights still sit in the chrome above
        // this; we only own the content area, so spacing here is what
        // separates the heading from the window's top edge.
        .padding(.top, 36)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func header(_ t: MissionTheme) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEW EXPORT")
                    .font(MissionFont.kicker(11))
                    .tracking(1.6)
                    .foregroundStyle(t.inkMute)
                Text(displayContact)
                    .font(MissionFont.display(26, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            HStack(spacing: 8) {
                ChipButton(label: themePreference.label,
                           icon: themePreference.icon) {
                    themeRaw = themePreference.next.rawValue
                }
                .help("Appearance: \(themePreference.label). Click to cycle Auto → Light → Dark.")
                ChipButton(label: "Save preset", icon: "star",
                           disabled: contact.trimmingCharacters(in: .whitespaces).isEmpty) {
                    showSavePreset = true
                }
                    .help("Save the current Contact + range + Mode + Transcribe + Emoji as a named preset.")
                ChipButton(label: "Reveal output", icon: "folder",
                           disabled: runner.runFolder == nil
                                  && !FileManager.default.fileExists(atPath: outputDirPath)) {
                    let url = runner.runFolder ?? URL(fileURLWithPath: outputDirPath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    private var displayContact: String {
        let s = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Untitled export" : s
    }

    private func runExport() async {
        guard ExportRunner.cliIsInstalled() else {
            showInstallSheet = true
            return
        }
        let request = ExportRequest(
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            start: start,
            end: end,
            outputDir: URL(fileURLWithPath: outputDirPath),
            emoji: EmojiMode(rawValue: emojiRaw) ?? .word,
            mode: mode,
            transcribe: transcribeEnabled,
            transcribeModel: WhisperModel(rawValue: transcribeModelRaw) ?? .turbo,
            debug: debugLogging
        )
        await runner.run(request)
    }

    private static func todayAtStartOfDay() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Sidebar callback: load a past run's settings back into the form.
    /// Dates default to "today 00:00 → now" if the entry didn't capture
    /// them (open-ended range exports).
    private func applyRecent(_ entry: RunHistoryEntry) {
        contact = entry.contact
        start = entry.start ?? Self.todayAtStartOfDay()
        end   = entry.end ?? Date()
        mode  = entry.mode
        transcribeEnabled  = entry.transcribe
        transcribeModelRaw = entry.transcribeModel.rawValue
        emojiRaw           = entry.emoji.rawValue
    }

    /// Sidebar callback: apply a saved preset onto the form. Same shape
    /// as `applyRecent` — different source.
    private func applyPreset(_ preset: ExportPreset) {
        contact = preset.contact
        start = preset.start ?? Self.todayAtStartOfDay()
        end   = preset.end ?? Date()
        mode  = preset.mode
        transcribeEnabled  = preset.transcribe
        transcribeModelRaw = preset.transcribeModel.rawValue
        emojiRaw           = preset.emoji.rawValue
    }
}

// MARK: - Form card

/// The grid card containing Contact / From / To / Mode / Transcribe.
/// Output folder and Emoji moved to Settings — they're rarely changed,
/// and the redesign trades visible chrome for focus on the run inputs.
struct FormCard: View {
    @Environment(\.missionTheme) private var t

    @Binding var contact: String
    @Binding var start: Date
    @Binding var end:   Date
    @Binding var mode:  ExportMode
    @Binding var transcribeEnabled: Bool
    @Binding var transcribeModelRaw: String

    var body: some View {
        GlassCard(cornerRadius: 12) {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
                GridRow {
                    fieldLabel("Contact").gridCellColumns(1)
                    contactField.gridCellColumns(3)
                }
                GridRow {
                    fieldLabel("From")
                    DatePicker("", selection: $start,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    fieldLabel("To")
                    DatePicker("", selection: $end,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                GridRow {
                    fieldLabel("Mode")
                    modePicker.gridCellColumns(3)
                }
                GridRow {
                    fieldLabel("Transcribe")
                    transcribeRow.gridCellColumns(3)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(MissionFont.kicker(10))
            .tracking(1.0)
            .foregroundStyle(t.inkMute)
    }

    private var contactField: some View {
        HStack(spacing: 10) {
            avatarBubble
            TextField("Search AddressBook…", text: $contact)
                .textFieldStyle(.plain)
                .font(MissionFont.sans(14, weight: .medium))
                .foregroundStyle(t.ink)
            Spacer(minLength: 0)
            Text(matchHint)
                .font(MissionFont.mono(11))
                .foregroundStyle(t.inkMute)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(t.cardFillStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(t.rule, lineWidth: 1)
        )
    }

    private var avatarBubble: some View {
        let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let initials = trimmed.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.55, blue: 0.95),
                        Color(red: 0.74, green: 0.36, blue: 0.78)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials.isEmpty ? "?" : initials)
                .font(MissionFont.sans(11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }

    private var matchHint: String {
        contact.trimmingCharacters(in: .whitespaces).isEmpty
            ? "type to begin"
            : "match via AddressBook"
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(ExportMode.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320, alignment: .leading)
        .help("Sanitized: HEIC→JPG, EXIF stripped, caption-derived filenames. Raw (forensic): byte-identical copies, original filenames, sha256 + EXIF in metadata.json.")
    }

    private var transcribeRow: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $transcribeEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
            Text(transcribeEnabled ? "Audio & video" : "Skip audio & video")
                .font(MissionFont.sans(13))
                .foregroundStyle(t.ink)
            Spacer()
            modelTag
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(t.cardFillStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(t.rule, lineWidth: 1)
        )
    }

    private var modelTag: some View {
        let model = WhisperModel(rawValue: transcribeModelRaw)?.shortLabel ?? "turbo"
        return Text(model)
            .font(MissionFont.mono(10, weight: .medium))
            .foregroundStyle(t.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(t.accentSoft)
            )
            .opacity(transcribeEnabled ? 1 : 0.5)
            .help("Change the Whisper model in Settings ⌘,. First run downloads the model and bootstraps a venv.")
    }
}

// MARK: - Footer + banners

/// Footer that surfaces the app version (CFBundleShortVersionString +
/// CFBundleVersion) so the user knows what build is running. Useful for
/// bug reports — version derives from git commit count via build-app.sh.
struct VersionFooter: View {
    @Environment(\.missionTheme) private var t

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (build \(build))"
    }

    var body: some View {
        Text(version)
            .font(MissionFont.mono(10))
            .foregroundStyle(t.inkMute)
            .textSelection(.enabled)
    }
}

/// Inline orange banner shown above the main heading whenever the runner
/// has confirmed FDA is denied. **Re-check** re-probes chat.db without
/// re-opening the sheet (covers the "I just granted access in another
/// window" case); **Resolve…** re-opens the modal sheet for the full
/// guidance + tccutil reset action.
struct FDABanner: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(t.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access required")
                    .font(MissionFont.sans(13, weight: .semibold))
                    .foregroundStyle(t.ink)
                Text("Exports will fail until access is granted. Click Re-check after granting.")
                    .font(MissionFont.sans(11))
                    .foregroundStyle(t.inkDim)
            }
            Spacer()
            ChipButton(label: "Re-check") { runner.checkFullDiskAccess() }
            ChipButton(label: "Resolve…") { showSheet = true }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(t.amber.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(t.amber.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Modal sheet shown on launch when chat.db is unreadable. The three
/// branches (grant for the first time / clean up duplicate entries /
/// continue anyway) cover the realistic states a user lands in:
///
///   - First launch: chat.db is unreadable, no TCC row exists yet.
///     "Open Privacy Settings" + drag the .app in.
///   - Stale cdhash: ad-hoc rebuild rotated the signature; old TCC rows
///     don't match. "Reset Privacy entries" wipes them all so the next
///     re-grant produces a clean single entry.
///   - Smoke-testing without exporting (rare): "Continue anyway" leaves
///     the persistent banner up and lets the user poke around.
///
/// "Quit" is offered because TCC pins the cdhash at process spawn — once
/// FDA is granted to the *running* process, the kernel still answers EPERM
/// until it's relaunched. Confusing without an explicit hint.
struct FullDiskAccessSheet: View {
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showSheet: Bool
    @State private var resetting = false
    @State private var resetMessage: String?
    @State private var stillDeniedHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("Full Disk Access required")
                    .font(.title2).bold()
            }
            Text("This app reads `~/Library/Messages/chat.db` to export your iMessages. macOS protects that file behind Full Disk Access — without it, every export fails at stage 1.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("How to grant access").font(.callout).bold()
                Text("1. Click **Open Privacy Settings** below.\n2. Drag **MessagesExporterGUI.app** into the Full Disk Access list (or click + and select it). Toggle the switch on.\n3. Switch back to this window — the banner clears automatically as soon as the grant takes effect. If it doesn't, click **I've granted access** to re-probe; if still denied, **Quit** and relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Seeing duplicate \"MessagesExporterGUI\" / \"… 2\" entries?")
                    .font(.callout).bold()
                Text("Ad-hoc rebuilds rotate the app's code signature, so each rebuild can leave a stale Privacy entry behind. Reset wipes them all so the next grant is a single clean entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let resetMessage {
                Text(resetMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if stillDeniedHint {
                Text("Still denied. The TCC grant didn't apply to this running process — quit and relaunch the app.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Reset Privacy entries") {
                    resetting = true
                    Task {
                        let ok = await runner.resetTCCEntries()
                        resetting = false
                        resetMessage = ok
                            ? "Reset complete. Quit, re-grant, and relaunch."
                            : "Reset failed — see log for details."
                    }
                }
                .disabled(resetting)
                Spacer()
                Button("Continue anyway") {
                    runner.checkFullDiskAccess()
                    showSheet = false
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Button("I've granted access") {
                    runner.checkFullDiskAccess()
                    if runner.fdaStatus == .granted {
                        showSheet = false
                    } else {
                        stillDeniedHint = true
                    }
                }
                Button("Open Privacy Settings") {
                    ExportRunner.openPrivacySettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580)
    }
}

/// Pre-flight sheet shown when ~/.local/bin/export_messages is missing.
/// Offers to run the sibling install.sh in-place; output is streamed
/// into the runner's logLines so the user can watch brew/pip work.
private struct InstallSheet: View {
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showInstallSheet: Bool
    @State private var installing = false

    private static let bottomID = "install-log-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages Exporter CLI is not installed")
                .font(.headline)
            Text("The export tool isn't at \(ExportRunner.cliPath). It's installed by running messages-exporter/install.sh from the PhantomLives repo. Install it now?")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if installing || !runner.logLines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Text(runner.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .textSelection(.enabled)
                            Color.clear.frame(height: 0).id(Self.bottomID)
                        }
                    }
                    .background(Color.black.opacity(0.05))
                    .frame(height: 180)
                    .onChange(of: runner.logLines.count) { _, count in
                        guard count > 0 else { return }
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { showInstallSheet = false }
                    .disabled(installing)
                Button(installing ? "Installing…" : "Install now") {
                    installing = true
                    Task {
                        let ok = await runner.installCLI()
                        installing = false
                        if ok { showInstallSheet = false }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(installing)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

// MARK: - Settings (Output + Emoji moved here)

struct SettingsView: View {
    @AppStorage(SettingsKeys.outputDir) private var outputDirPath: String = defaultOutputDir().path
    @AppStorage(SettingsKeys.transcribeModel) private var transcribeModelRaw: String = WhisperModel.turbo.rawValue
    @AppStorage(SettingsKeys.debugLogging) private var debugLogging: Bool = false
    @AppStorage(SettingsKeys.emojiMode) private var emojiRaw: String = EmojiMode.word.rawValue
    @AppStorage(SettingsKeys.themePreference) private var themeRaw: String = ThemePreference.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(ThemePreference.allCases) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("**Auto** follows System Settings → Appearance. **Light** and **Dark** force the chosen scheme regardless of system. The header has a quick-toggle chip that cycles through the same three options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Default output folder") {
                HStack {
                    Text(outputDirPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.directoryURL = URL(fileURLWithPath: outputDirPath)
                        if panel.runModal() == .OK, let url = panel.url {
                            outputDirPath = url.path
                        }
                    }
                    Button("Reset to Downloads") {
                        outputDirPath = defaultOutputDir().path
                    }
                }
                Text("Each run creates a <contact>_<timestamp>/ subfolder here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Emoji handling") {
                Picker("In derived filenames", selection: $emojiRaw) {
                    ForEach(EmojiMode.allCases) { e in
                        Text(e.label).tag(e.rawValue)
                    }
                }
                Text("How emoji are treated when the CLI builds attachment filenames from message captions. Ignored in Raw (forensic) mode — original filenames are preserved verbatim.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Whisper transcription") {
                Picker("Model", selection: $transcribeModelRaw) {
                    ForEach(WhisperModel.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
                Text("Used when the inline **Transcribe** toggle is on. First run for a given model downloads it (~150 MB for tiny up to ~3 GB for large) and self-bootstraps a venv at PhantomLives/transcribe/.venv via mlx-whisper. Subsequent runs reuse the cached model. Apple Silicon Metal-accelerated; no server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset to turbo") {
                    transcribeModelRaw = WhisperModel.turbo.rawValue
                }
                .controlSize(.small)
            }
            Section("Diagnostics") {
                Toggle("Debug logging", isOn: $debugLogging)
                Text("Shows pip install lines, HuggingFace download progress, and Whisper internals in the log pane. Turn on when troubleshooting a transcription failure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Backup") {
                BackupSettingsView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 720)
    }
}

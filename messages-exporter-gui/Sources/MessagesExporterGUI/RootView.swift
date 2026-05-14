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
    /// When on, the resolved start is pulled 60s earlier than what the
    /// user picked. Compensates for Messages.app's swipe-time display,
    /// which rounds to the displayed minute and can leave the first
    /// message a few seconds short of the user-chosen bound.
    static let expandStart     = "expandStartByOneMinute"
    /// Global kill switch for the whole transcription subsystem. When
    /// OFF, the form's per-run Transcribe toggle is force-disabled,
    /// `--transcribe` never reaches the CLI, and the launch-time
    /// preflight is skipped. Defaults ON so existing users see no
    /// change — flip it off in Settings → Transcription if you never
    /// need audio/video transcripts.
    static let transcribeMasterOn = "transcribeMasterEnabled"
}

struct RootView: View {
    @EnvironmentObject private var runner: ExportRunner
    @EnvironmentObject private var presets: PresetStore

    @State private var contact = ""
    /// Set when the user picks a row from the SenderCombobox. Non-nil
    /// means "send via --handle, skip CLI fuzzy match." Typing in the
    /// field after a pick resets this to nil and falls back to the
    /// positional-contact path.
    @State private var pickedHandle: String?
    @State private var start: Date = Self.todayAtStartOfDay()
    @State private var end:   Date = Date()
    // Seconds steppers — SwiftUI's DatePicker is HH:MM only, so the
    // seconds field lives next to it. Defaults model "the whole minute
    // I picked": start at :00, end at :59. Loaded from a preset/history
    // entry, both pull the saved Date's actual second component back in.
    @State private var startSeconds: Int = 0
    @State private var endSeconds:   Int = 59
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
    @AppStorage(SettingsKeys.expandStart) private var expandStartByOneMinute: Bool = true
    @AppStorage(SettingsKeys.transcribeMasterOn) private var transcribeMasterEnabled: Bool = true
    @StateObject private var preflight = TranscriptionPreflightService()
    @State private var showPreflightSheet = false

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        MissionThemeReader { theme in
            HStack(spacing: 0) {
                Sidebar(
                    showFDASheet: $showFDASheet,
                    applyRecent: applyRecent,
                    applyPreset: applyPreset
                )
                main(theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [theme.bg1, theme.bg2],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .preferredColorScheme(themePreference.colorScheme)
            .sheet(isPresented: $showInstallSheet) {
                InstallSheet(showInstallSheet: $showInstallSheet)
            }
            .sheet(isPresented: $showFDASheet) {
                FullDiskAccessSheet(showSheet: $showFDASheet)
            }
            .sheet(isPresented: $showPreflightSheet) {
                TranscriptionPreflightSheet(
                    service: preflight,
                    isPresented: $showPreflightSheet,
                    masterEnabled: $transcribeMasterEnabled
                )
            }
            .sheet(isPresented: $showSavePreset) {
                // Presets snapshot the resolved range (picker + SS + buffer
                // collapsed into a single Date pair) so reloading a preset
                // restores exactly what was previously run, independent of
                // the buffer toggle's current global state.
                SavePresetSheet(
                    isPresented: $showSavePreset,
                    contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: resolvedStart,
                    end: resolvedEnd,
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
                // Run the transcription preflight only when the master
                // switch is on — flipping it off is a deliberate "I never
                // transcribe" signal and we shouldn't pester the user
                // with setup prompts in that mode. The probe is cheap
                // (subprocess spawns capped by exit) so we let it run
                // every launch; auto-opening the sheet is gated on
                // failures so a healthy system never sees it.
                if transcribeMasterEnabled {
                    await preflight.probeAll()
                    // Two-sheet collision guard: SwiftUI can only show
                    // one `.sheet(isPresented:)` at a time. If FDA is
                    // still denied the user is mid-grant — surfacing
                    // the preflight on top would either be ignored or
                    // bury the FDA guidance. They can open it later
                    // from Settings → Transcription → Run preflight.
                    if preflight.hasFailures && !showFDASheet {
                        showPreflightSheet = true
                    }
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
            // Post-run problem banner. Surfaces transcription failures the
            // CLI logged but which would otherwise hide inside the live
            // output — and any other terminal error captured in
            // `lastError`. Hidden while a run is in flight so the user
            // sees progress unobstructed.
            if !runner.isRunning, let err = runner.lastError {
                RunErrorBanner(
                    message: err,
                    showPreflight: runner.transcriptFailureCount > 0
                                || runner.transcriptFailureSummary != nil,
                    openPreflight: {
                        showPreflightSheet = true
                        Task { await preflight.probeAll() }
                    }
                )
            }

            header(t)

            // Span tile shows the resolved range so the user can see the
            // 60s start buffer (and any non-zero seconds) accounted for
            // before they hit Run.
            StatTiles(pendingStart: resolvedStart, pendingEnd: resolvedEnd)

            FormCard(
                contact: $contact,
                pickedHandle: $pickedHandle,
                start: $start,
                end: $end,
                startSeconds: $startSeconds,
                endSeconds: $endSeconds,
                mode: $mode,
                transcribeEnabled: $transcribeEnabled,
                transcribeModelRaw: $transcribeModelRaw,
                transcribeMasterEnabled: transcribeMasterEnabled,
                expandStartByOneMinute: expandStartByOneMinute,
                resolvedStart: resolvedStart,
                resolvedEnd: resolvedEnd
            )

            HStack(spacing: 12) {
                RunStrip(
                    canRun: !runner.isRunning && !contact.trimmingCharacters(in: .whitespaces).isEmpty,
                    runAction: { Task { await runExport() } },
                    cancelAction: { showCancelConfirm = true }
                )
                .layoutPriority(1)
                // Always-on Reveal-in-Finder action next to the primary
                // Run/Cancel control. Lives here (in addition to the
                // header chip) so the button is unmistakably visible at
                // any window size — the header chips can compress out of
                // sight on narrow windows, and this is the artifact users
                // reach for after every successful run.
                RevealOutputButton(
                    runFolder: runner.runFolder,
                    fallbackDir: outputDirPath
                )
            }
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
        .padding(.top, 32)
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
        // Pin the header's vertical size. Without this, LiveOutputCard's
        // `.frame(maxHeight: .infinity)` can greedily claim space on a
        // window near its minimum height (632pt) and SwiftUI compresses
        // the header — which (a) hides the chips and (b) overlaps the
        // title bar. layoutPriority(1) makes the header the *last* row
        // to give up space rather than the first.
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
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
        // Hard kill switch: when the master is off, never send
        // --transcribe to the CLI regardless of the per-run toggle's
        // stored value. Keeps the user's per-run preference intact for
        // when they re-enable the master.
        let effectiveTranscribe = transcribeMasterEnabled && transcribeEnabled

        // Pre-run transcription gate. When the user asked for transcription,
        // probe the venv RIGHT NOW (not at launch — state can change in
        // between, especially across multiple back-to-back exports). If
        // the dependencies aren't ready, surface the warm preflight sheet
        // instead of launching a CLI that would spam 42 tracebacks across
        // every attachment. The user sees a single dialog with a clear
        // path forward — and can opt to run without transcription if they
        // want the export anyway.
        if effectiveTranscribe {
            await preflight.probeAll()
            if preflight.hasFailures {
                showPreflightSheet = true
                return
            }
        }

        let request = ExportRequest(
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            handles: pickedHandle.map { [$0] } ?? [],
            start: resolvedStart,
            end: resolvedEnd,
            outputDir: URL(fileURLWithPath: outputDirPath),
            emoji: EmojiMode(rawValue: emojiRaw) ?? .word,
            mode: mode,
            transcribe: effectiveTranscribe,
            transcribeModel: WhisperModel(rawValue: transcribeModelRaw) ?? .turbo,
            debug: debugLogging
        )
        await runner.run(request)
    }

    private var resolvedStart: Date {
        RangeResolver.resolvedStart(picker: start, seconds: startSeconds,
                                    expandStartByOneMinute: expandStartByOneMinute)
    }
    private var resolvedEnd: Date {
        RangeResolver.resolvedEnd(picker: end, seconds: endSeconds)
    }

    private static func todayAtStartOfDay() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Sidebar callback: load a past run's settings back into the form.
    /// Dates default to "today 00:00 → now" if the entry didn't capture
    /// them (open-ended range exports). The saved Date carries the full
    /// resolved second, so we split it back into the HH:MM picker value
    /// + the SS stepper rather than truncating to the minute.
    private func applyRecent(_ entry: RunHistoryEntry) {
        contact = entry.contact
        // History entries don't (yet) capture the picked-handle latch —
        // applying a recent run drops the user back into the legacy
        // positional-contact path. They can re-pick from the combobox
        // if they want the exact-handle form.
        pickedHandle = nil
        Self.split(entry.start ?? Self.todayAtStartOfDay(),
                   into: &start, seconds: &startSeconds)
        Self.split(entry.end ?? Date(),
                   into: &end, seconds: &endSeconds)
        mode  = entry.mode
        transcribeEnabled  = entry.transcribe
        transcribeModelRaw = entry.transcribeModel.rawValue
        emojiRaw           = entry.emoji.rawValue
    }

    /// Sidebar callback: apply a saved preset onto the form. Same shape
    /// as `applyRecent` — different source.
    private func applyPreset(_ preset: ExportPreset) {
        contact = preset.contact
        pickedHandle = nil
        Self.split(preset.start ?? Self.todayAtStartOfDay(),
                   into: &start, seconds: &startSeconds)
        Self.split(preset.end ?? Date(),
                   into: &end, seconds: &endSeconds)
        mode  = preset.mode
        transcribeEnabled  = preset.transcribe
        transcribeModelRaw = preset.transcribeModel.rawValue
        emojiRaw           = preset.emoji.rawValue
    }

    /// Decompose a saved/loaded `Date` into the picker's minute-precision
    /// value + the seconds stepper's integer. The picker side has seconds
    /// zeroed out so an HH:MM change later doesn't fight the SS stepper.
    private static func split(_ d: Date,
                              into picker: inout Date,
                              seconds: inout Int) {
        let cal = Calendar.current
        seconds = cal.component(.second, from: d)
        picker  = RangeResolver.setSeconds(0, on: d, calendar: cal)
    }
}

// MARK: - Form card

/// The grid card containing Contact / From / To / Mode / Transcribe.
/// Output folder and Emoji moved to Settings — they're rarely changed,
/// and the redesign trades visible chrome for focus on the run inputs.
struct FormCard: View {
    @Environment(\.missionTheme) private var t

    @Binding var contact: String
    @Binding var pickedHandle: String?
    @Binding var start: Date
    @Binding var end:   Date
    @Binding var startSeconds: Int
    @Binding var endSeconds:   Int
    @Binding var mode:  ExportMode
    @Binding var transcribeEnabled: Bool
    @Binding var transcribeModelRaw: String
    /// Honours the Settings → Transcription master switch. When false,
    /// the per-run toggle is hard-disabled and the row paints a hint
    /// pointing the user at Settings instead of pretending to be live.
    var transcribeMasterEnabled: Bool
    var expandStartByOneMinute: Bool
    var resolvedStart: Date
    var resolvedEnd:   Date

    var body: some View {
        GlassCard(cornerRadius: 12) {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
                GridRow {
                    fieldLabel("Contact").gridCellColumns(1)
                    SenderCombobox(contact: $contact,
                                   pickedHandle: $pickedHandle)
                        .gridCellColumns(3)
                }
                GridRow {
                    fieldLabel("From")
                    dateAndSeconds(date: $start, seconds: $startSeconds)
                    fieldLabel("To")
                    dateAndSeconds(date: $end, seconds: $endSeconds)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    resolvedHint.gridCellColumns(3)
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
    private func dateAndSeconds(date: Binding<Date>, seconds: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            DatePicker("", selection: date,
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
            // Seconds field — the DatePicker is HH:MM only, so this is
            // the user's knob for sub-minute precision. Kept tight (40pt)
            // so the row still fits at the form's minimum width.
            TextField("00",
                      value: seconds,
                      formatter: Self.secondsFormatter)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(MissionFont.mono(12))
                .frame(width: 40)
                .help("Seconds (0–59). Pair with the HH:MM picker for forensic precision.")
            Stepper("", value: seconds, in: 0...59)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private static let secondsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 59
        f.allowsFloats = false
        f.minimumIntegerDigits = 2
        return f
    }()

    /// Caption that surfaces the actual range about to be sent to the
    /// CLI — including the 60s start buffer when on. Without this the
    /// buffer would be invisible and surprising the first time a run
    /// returned messages from a minute earlier than the picker says.
    @ViewBuilder
    private var resolvedHint: some View {
        let f = Self.hintFormatter
        let bufferNote = expandStartByOneMinute
            ? " (start expanded 60s for Messages.app rounding)"
            : ""
        Text("Resolved: \(f.string(from: resolvedStart)) → \(f.string(from: resolvedEnd))\(bufferNote)")
            .font(MissionFont.mono(10))
            .foregroundStyle(t.inkMute)
            .help("The exact bounds sent to the CLI. Toggle the 60s buffer in Settings → Range precision.")
    }

    private static let hintFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    @ViewBuilder
    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(MissionFont.kicker(10))
            .tracking(1.0)
            .foregroundStyle(t.inkMute)
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
        // When the master switch is OFF, force-show the toggle as off
        // and disable it. We don't mutate the per-run @AppStorage value —
        // flipping the master back on should restore whatever the user
        // had set per-run, not silently clobber it.
        let effectiveOn = transcribeMasterEnabled && transcribeEnabled
        return HStack(spacing: 10) {
            Toggle("", isOn: $transcribeEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!transcribeMasterEnabled)
            Text(rowCaption(effectiveOn: effectiveOn))
                .font(MissionFont.sans(13))
                .foregroundStyle(transcribeMasterEnabled ? t.ink : t.inkMute)
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
        .opacity(transcribeMasterEnabled ? 1 : 0.6)
        .help(transcribeMasterEnabled
              ? "Run Whisper over audio/video attachments. First run downloads the model and bootstraps a venv."
              : "Transcription is disabled in Settings → Transcription. Enable the master switch to use this toggle.")
    }

    private func rowCaption(effectiveOn: Bool) -> String {
        if !transcribeMasterEnabled { return "Disabled in Settings" }
        return effectiveOn ? "Audio & video" : "Skip audio & video"
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

/// Prominent Reveal-in-Finder button anchored next to the Run/Cancel
/// strip. Always visible regardless of header chip layout — the previous
/// "Reveal output" lived only in the top-right chip row and could
/// disappear at narrow window widths. Falls back to the configured
/// output dir when no run folder has been captured yet.
struct RevealOutputButton: View {
    @Environment(\.missionTheme) private var t

    let runFolder: URL?
    /// Display path to use when `runFolder` is nil. Typed as String to
    /// match the @AppStorage caller; we convert to URL at click time.
    let fallbackDir: String

    private var targetURL: URL {
        runFolder ?? URL(fileURLWithPath: fallbackDir)
    }

    /// Disabled only if we have neither a run folder nor a writable
    /// fallback directory on disk — otherwise the click always does
    /// something useful (reveal the output root if no run yet).
    private var disabled: Bool {
        runFolder == nil
            && !FileManager.default.fileExists(atPath: fallbackDir)
    }

    var body: some View {
        Button(action: {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                Text("Reveal")
                    .font(MissionFont.sans(13, weight: .semibold))
            }
            .foregroundStyle(t.runGradStart)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(t.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(runFolder != nil
              ? "Reveal the run folder in Finder."
              : "Reveal the configured output folder in Finder. After a run, this jumps to the run subfolder.")
    }
}

/// Inline banner shown after a run that surfaced a recoverable error —
/// most commonly per-attachment transcription failures the CLI logs but
/// the run pill still claims as "Done." Offers a one-click jump back to
/// the transcription preflight wizard when the failure looks like a
/// dependency issue. Hidden as soon as the user starts a new run or the
/// runner clears `lastError`.
struct RunErrorBanner: View {
    @Environment(\.missionTheme) private var t

    let message: String
    /// When true, the banner shows a `Run preflight` chip — used for the
    /// transcription-failure case where the wizard has a real chance of
    /// helping. False for generic export failures where we'd just open
    /// an empty wizard.
    let showPreflight: Bool
    let openPreflight: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(t.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last run reported a problem")
                    .font(MissionFont.sans(13, weight: .semibold))
                    .foregroundStyle(t.ink)
                Text(message)
                    .font(MissionFont.sans(11))
                    .foregroundStyle(t.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if showPreflight {
                ChipButton(label: "Run preflight",
                           icon: "stethoscope",
                           action: openPreflight)
            }
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
    @AppStorage(SettingsKeys.transcribeMasterOn) private var transcribeMasterEnabled: Bool = true
    @AppStorage(SettingsKeys.debugLogging) private var debugLogging: Bool = false
    @AppStorage(SettingsKeys.emojiMode) private var emojiRaw: String = EmojiMode.word.rawValue
    @AppStorage(SettingsKeys.themePreference) private var themeRaw: String = ThemePreference.system.rawValue
    @AppStorage(SettingsKeys.expandStart) private var expandStartByOneMinute: Bool = true
    /// The Settings scene gets its own preflight instance — it lives in a
    /// separate window from RootView and SwiftUI's @EnvironmentObject
    /// doesn't follow across Scene boundaries reliably. Probes are
    /// idempotent so two instances don't interfere.
    @StateObject private var settingsPreflight = TranscriptionPreflightService()
    @State private var showPreflightSheet = false

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
            Section("Range precision") {
                Toggle("Expand start by 60 seconds (Messages.app rounding)",
                       isOn: $expandStartByOneMinute)
                Text("Messages.app's swipe-to-reveal time rounds to the displayed minute, so the actual `message.date` for a message shown as 10:12 can be a few seconds before 10:12:00. With this on, the CLI is queried from one full minute earlier than your picker — over-inclusive but safe for forensic exports. The form's **Resolved** caption shows the exact bounds before you click Run.")
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
            Section("Transcription") {
                Toggle("Enable transcription", isOn: $transcribeMasterEnabled)
                Text("Master switch. When off, the per-run **Transcribe** toggle on the main form is disabled, exports never pass `--transcribe` to the CLI, and the launch-time preflight is skipped. Flip this off if you never need audio/video transcripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Model", selection: $transcribeModelRaw) {
                    ForEach(WhisperModel.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
                .disabled(!transcribeMasterEnabled)
                Text("First run for a given model downloads it (~150 MB for tiny up to ~3 GB for large) and self-bootstraps a venv at PhantomLives/transcribe/.venv via mlx-whisper. Subsequent runs reuse the cached model. Apple Silicon Metal-accelerated; no server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Reset to turbo") {
                        transcribeModelRaw = WhisperModel.turbo.rawValue
                    }
                    .controlSize(.small)
                    .disabled(!transcribeMasterEnabled)

                    Spacer()
                    Button("Run preflight…") {
                        showPreflightSheet = true
                        Task { await settingsPreflight.probeAll() }
                    }
                    .controlSize(.small)
                    .disabled(!transcribeMasterEnabled)
                    .help("Re-probe the transcription dependencies (transcribe.py, Python 3.10+, ffmpeg, venv, mlx-whisper) and surface fix suggestions in a wizard.")
                }
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
        .sheet(isPresented: $showPreflightSheet) {
            TranscriptionPreflightSheet(
                service: settingsPreflight,
                isPresented: $showPreflightSheet,
                masterEnabled: $transcribeMasterEnabled
            )
        }
    }
}

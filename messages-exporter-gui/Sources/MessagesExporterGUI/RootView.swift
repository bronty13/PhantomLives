import SwiftUI
import AppKit

/// Default parent directory for exports. Per the PhantomLives convention,
/// every tool's user-facing output defaults to a subfolder of ~/Downloads/
/// named after the project, so all exports across all tools land in one
/// predictable place. The CLI then creates a `<contact>_<timestamp>`
/// subfolder inside this, e.g.
/// ~/Downloads/messages-exporter-gui/Sallie_20260427_172132/.
/// Created on demand the first time it's read.
private func defaultOutputDir() -> URL {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let dir = downloads.appendingPathComponent("messages-exporter-gui", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// User-configurable export root. Stored in UserDefaults so the
/// Settings scene and the main window stay in sync.
enum SettingsKeys {
    static let outputDir = "outputDirPath"
}

struct RootView: View {
    @EnvironmentObject private var runner: ExportRunner

    @State private var contact = ""
    @State private var start: Date = Self.todayAtStartOfDay()
    @State private var end:   Date = Date()
    @State private var emoji: EmojiMode = .word
    @State private var mode:  ExportMode = .sanitized
    @State private var showInstallSheet = false
    @State private var showFDASheet     = false

    @AppStorage(SettingsKeys.outputDir) private var outputDirPath: String = defaultOutputDir().path

    private static let labelWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Persistent FDA-denied banner. Surfaces the issue inline once
            // the modal sheet is dismissed so the user always knows why
            // exports will fail. Disappears as soon as fdaStatus flips to
            // .granted — re-probed on every Re-check click and on every
            // app activation (NSApplication.didBecomeActiveNotification),
            // so granting FDA in System Settings and switching back will
            // clear the banner without quitting.
            if runner.fdaStatus == .denied {
                FDABanner(showSheet: $showFDASheet)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }
            // Inputs — tight grid using LabeledContent so all six fields
            // fit above the fold without scrolling.
            VStack(alignment: .leading, spacing: 6) {
                LabeledRow("Output") {
                    OutputFolderRow(path: $outputDirPath)
                }
                LabeledRow("Contact") {
                    TextField("Contact name", text: $contact)
                        .textFieldStyle(.roundedBorder)
                        .help("Substring matched against AddressBook by the CLI.")
                }
                LabeledRow("From") {
                    DatePicker("", selection: $start,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                LabeledRow("To") {
                    DatePicker("", selection: $end,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                LabeledRow("Mode") {
                    Picker("", selection: $mode) {
                        ForEach(ExportMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280, alignment: .leading)
                    .help("Sanitized: HEIC→JPG, EXIF stripped, caption-derived filenames. Raw (forensic): byte-identical copies, original filenames, sha256 + EXIF in metadata.json.")
                }
                LabeledRow("Emoji") {
                    Picker("", selection: $emoji) {
                        ForEach(EmojiMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280, alignment: .leading)
                    .disabled(mode == .raw)
                    .help(mode == .raw
                          ? "Ignored in raw mode — original filenames are preserved."
                          : "Emoji handling in derived filenames.")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider().padding(.horizontal, 14)

            // Run row + progress, kept on a single horizontal line.
            HStack(spacing: 12) {
                Button {
                    Task { await runExport() }
                } label: {
                    Label("Run export", systemImage: "play.fill")
                        .frame(minWidth: 110)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .controlSize(.large)
                .disabled(runner.isRunning || contact.trimmingCharacters(in: .whitespaces).isEmpty)

                ProgressBar(stage: runner.stage, isRunning: runner.isRunning)
            }
            .padding(.horizontal, 14)

            LogPane(lines: runner.logLines,
                    runFolder: runner.runFolder,
                    lastError: runner.lastError)
                .padding(.horizontal, 14)

            VersionFooter()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallSheet(showInstallSheet: $showInstallSheet)
        }
        .sheet(isPresented: $showFDASheet) {
            FullDiskAccessSheet(showSheet: $showFDASheet)
        }
        .task {
            // Pre-flight Full Disk Access on first appearance so we can
            // surface the issue before the user fills in a contact, sets
            // a date range, and hits Run only to see an EPERM at stage 1.
            // Skipped if we've already determined status earlier this run.
            if runner.fdaStatus == .unknown {
                runner.checkFullDiskAccess()
            }
            if runner.fdaStatus == .denied {
                showFDASheet = true
            }
        }
        .onReceive(NotificationCenter.default
                    .publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // User probably switched away to System Settings to grant
            // FDA, then switched back. Re-probe the chat.db readability
            // — kernel TCC checks at every I/O so a mid-session grant
            // can flip .denied -> .granted without a relaunch (despite
            // some folklore that says otherwise; this is true at least
            // for filesystem TCC). Skip while .granted to avoid pointless
            // syscalls on every focus change.
            if runner.fdaStatus != .granted {
                runner.checkFullDiskAccess()
            }
        }
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
            emoji: emoji,
            mode: mode
        )
        await runner.run(request)
    }

    private static func todayAtStartOfDay() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
}

/// Aligned label + control row. Keeps every input aligned on the same
/// vertical guideline without the vertical bloat of `.formStyle(.grouped)`.
struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline output-folder picker. Single horizontal row with the path,
/// optional Default badge, Choose, and Reset. No caption (the implicit
/// behavior is documented in the README and Settings tooltip).
struct OutputFolderRow: View {
    @Binding var path: String

    private var isDefault: Bool {
        URL(fileURLWithPath: path).standardizedFileURL ==
            defaultOutputDir().standardizedFileURL
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
            if isDefault {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Spacer()
            Button("Choose…") { choose() }
                .controlSize(.small)
            if !isDefault {
                Button("Reset") { path = defaultOutputDir().path }
                    .controlSize(.small)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: path)
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

/// Footer that surfaces the app version (CFBundleShortVersionString +
/// CFBundleVersion) so the user knows what build is running. Useful for
/// bug reports — version derives from git commit count via build-app.sh.
struct VersionFooter: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (build \(build))"
    }

    var body: some View {
        HStack {
            Spacer()
            Text(version)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

/// Inline orange banner shown beneath the title bar whenever the runner
/// has confirmed FDA is denied. **Re-check** re-probes chat.db without
/// re-opening the sheet (covers the "I just granted access in another
/// window" case); **Resolve…** re-opens the modal sheet for the full
/// guidance + tccutil reset action.
struct FDABanner: View {
    @EnvironmentObject private var runner: ExportRunner
    @Binding var showSheet: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access required")
                    .font(.callout).bold()
                Text("Exports will fail until access is granted. Click Re-check after granting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-check") { runner.checkFullDiskAccess() }
                .controlSize(.small)
            Button("Resolve…") { showSheet = true }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(10)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1))
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
                    // Re-probe before dismissing. If the user granted FDA
                    // while the sheet was open, this catches it and the
                    // banner won't appear. If still denied, dismiss the
                    // sheet and fall back to the persistent banner.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages Exporter CLI is not installed")
                .font(.headline)
            Text("The export tool isn't at \(ExportRunner.cliPath). It's installed by running messages-exporter/install.sh from the PhantomLives repo. Install it now?")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { showInstallSheet = false }
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
        .frame(width: 460)
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.outputDir) private var outputDirPath: String = defaultOutputDir().path

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 200)
    }
}

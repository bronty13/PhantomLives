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
    @State private var showInstallSheet = false

    @AppStorage(SettingsKeys.outputDir) private var outputDirPath: String = defaultOutputDir().path

    private static let labelWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Inputs — tight grid using LabeledContent so all five fields
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
                LabeledRow("Emoji") {
                    Picker("", selection: $emoji) {
                        ForEach(EmojiMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280, alignment: .leading)
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
            emoji: emoji
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

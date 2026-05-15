import SwiftUI
import AppKit

/// SlackSucker's preferences window. Modeled after messages-exporter-gui:
/// one long scrollable pane rather than separate tabs, so settings stay
/// discoverable without UI chrome to navigate.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var runner: ArchiveRunner

    @AppStorage("themePreference") private var themePref: String = ThemePreference.system.rawValue
    @AppStorage("debugLogging") private var debugLogging: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                outputSection
                defaultsSection
                postProcessingSection
                appearanceSection
                diagnosticsSection
                BackupSettingsView()
            }
            .padding(20)
        }
        .frame(minWidth: 540, minHeight: 560)
    }

    @ViewBuilder
    private var outputSection: some View {
        section(title: "OUTPUT FOLDER") {
            HStack {
                TextField("Default: ~/Downloads/SlackSucker",
                          text: Binding(get: { settings.outputDirOverride ?? "" },
                                        set: { settings.outputDirOverride = $0.isEmpty ? nil : $0
                                               settings.save() }))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseOutputDir() }
            }
            Text("Resolved: \(settings.resolvedOutputDir.path)")
                .font(AppFont.mono(10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var defaultsSection: some View {
        section(title: "DEFAULT ARCHIVE OPTIONS") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Download files", isOn: Binding(
                    get: { settings.defaultArchiveOptions.includeFiles },
                    set: { settings.defaultArchiveOptions.includeFiles = $0; settings.save() }))
                Toggle("Download avatars", isOn: Binding(
                    get: { settings.defaultArchiveOptions.includeAvatars },
                    set: { settings.defaultArchiveOptions.includeAvatars = $0; settings.save() }))
                Toggle("Member-only channels (workspace-wide runs)", isOn: Binding(
                    get: { settings.defaultArchiveOptions.memberOnly },
                    set: { settings.defaultArchiveOptions.memberOnly = $0; settings.save() }))
                Toggle("Sort attachments into Videos / Photos / Audio / Other", isOn: Binding(
                    get: { settings.defaultArchiveOptions.organizeFiles },
                    set: { settings.defaultArchiveOptions.organizeFiles = $0; settings.save() }))
                Text("When on, attachments are moved out of slackdump's \u{201C}__uploads/<ID>/\u{201D} layout into category subfolders at the run-folder root. The SQLite database and avatar thumbnails are untouched.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var postProcessingSection: some View {
        section(title: "POST-PROCESSING DEFAULTS") {
            VStack(alignment: .leading, spacing: 10) {
                // File ordering
                Picker("File ordering (within each category)", selection: Binding(
                    get: { settings.defaultArchiveOptions.fileOrdering },
                    set: { settings.defaultArchiveOptions.fileOrdering = $0; settings.save() })) {
                    ForEach(FileOrdering.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Determines the 0001_, 0002_, … per-category prefix applied by FileOrganizer.  \u{2022} Slack message timestamp: joins slackdump.sqlite for each FILE's parent MESSAGE.TS.  \u{2022} File created (ms): on-disk creation date with millisecond precision (reflects when slackdump wrote the file).  \u{2022} No order: original filenames preserved.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)

                Divider().padding(.vertical, 2)

                // Bake orientation
                Toggle("Bake EXIF orientation into photos / videos by default", isOn: Binding(
                    get: { settings.defaultArchiveOptions.bakeOrientation },
                    set: { settings.defaultArchiveOptions.bakeOrientation = $0; settings.save() }))
                Text("Photos: read the Orientation EXIF tag and bake the rotation into pixel data using Core Image. Videos: re-encode via ffmpeg with the display rotation flattened. Cannot infer orientation when there's no tag (e.g. screenshots) — that requires ML and is out of scope.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)

                // Strip metadata
                Toggle("Strip EXIF / IPTC / XMP metadata by default", isOn: Binding(
                    get: { settings.defaultArchiveOptions.stripPhotoMetadata },
                    set: { settings.defaultArchiveOptions.stripPhotoMetadata = $0; settings.save() }))
                Text("Uses `exiftool` (install via `brew install exiftool`). Runs AFTER orientation baking — stripping wipes the Orientation tag too.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)

                // Transcribe
                Toggle("Transcribe audio / video files by default", isOn: Binding(
                    get: { settings.defaultArchiveOptions.transcribeMedia },
                    set: { settings.defaultArchiveOptions.transcribeMedia = $0; settings.save() }))
                Picker("Whisper model", selection: Binding(
                    get: { settings.defaultArchiveOptions.transcribeModel },
                    set: { settings.defaultArchiveOptions.transcribeModel = $0; settings.save() })) {
                    ForEach(TranscriptionModel.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!settings.defaultArchiveOptions.transcribeMedia)
                Text("Shells to PhantomLives/transcribe/transcribe.py. Apple Silicon only. Emits <name>.txt next to each source media file.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)

                // Hashes
                Toggle("Generate file hashes by default", isOn: Binding(
                    get: { settings.defaultArchiveOptions.generateHashes },
                    set: { settings.defaultArchiveOptions.generateHashes = $0; settings.save() }))
                HStack(spacing: 14) {
                    ForEach(HashAlgorithm.allCases) { algo in
                        Toggle(algo.label, isOn: Binding(
                            get: { settings.defaultArchiveOptions.hashAlgorithms.contains(algo) },
                            set: { yes in
                                if yes { settings.defaultArchiveOptions.hashAlgorithms.insert(algo) }
                                else   { settings.defaultArchiveOptions.hashAlgorithms.remove(algo) }
                                settings.save()
                            }))
                            .disabled(!settings.defaultArchiveOptions.generateHashes)
                    }
                }
                Text("Writes hashes.txt at the run-folder root, GNU-coreutils-compatible format. SHA-256 is the modern default; MD5 / SHA-1 are kept available for cross-referencing legacy archives.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        section(title: "APPEARANCE") {
            Picker("Theme", selection: $themePref) {
                ForEach(ThemePreference.allCases) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        section(title: "DIAGNOSTICS") {
            Toggle("Verbose slackdump output (-v)", isOn: $debugLogging)
            Text("Slack workspace credentials live in ~/Library/Caches/slackdump, owned and encrypted by slackdump itself.")
                .font(AppFont.sans(11))
                .foregroundStyle(.tertiary)
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.resolvedOutputDir
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirOverride = url.path
            settings.save()
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            content()
        }
    }
}

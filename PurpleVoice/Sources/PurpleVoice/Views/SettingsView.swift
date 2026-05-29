import SwiftUI
import AppKit

/// Preferences pane. Three tabs:
///
/// - **General**: output dir / format, default profile, after-process toggles
/// - **Processing**: engine choice, loudness target, de-esser/de-clicker,
///   enhancement, stereo preservation
/// - **Advanced**: DeepFilterNet path override + reachability check
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var presetStore: PresetStore

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            processingTab
                .tabItem { Label("Processing", systemImage: "slider.horizontal.3") }
            presetsTab
                .tabItem { Label("Presets", systemImage: "square.stack.3d.up") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .padding(20)
        .frame(minHeight: 380)
    }

    private var presetsTab: some View {
        ManagePresetsView(embedded: true)
            .environmentObject(settings)
            .environmentObject(presetStore)
    }

    private var generalTab: some View {
        Form {
            Section("Output") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.outputDirectory.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { chooseOutputFolder() }
                        Button("Default") {
                            settings.outputDirectory = SettingsStore.defaultOutputDirectory
                        }
                    }
                }
                LabeledContent("Format") {
                    Picker("", selection: Binding(
                        get: { settings.outputFormat },
                        set: { settings.outputFormat = $0 }
                    )) {
                        ForEach(OutputFormat.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            Section("Defaults") {
                LabeledContent("Profile") {
                    Picker("", selection: Binding(
                        get: { settings.profile },
                        set: { settings.profile = $0 }
                    )) {
                        ForEach(ProcessingProfile.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Toggle("Enhancement chain", isOn: Binding(
                    get: { settings.enhancementEnabled },
                    set: { settings.enhancementEnabled = $0 }
                ))
            }
            Section("After processing") {
                Toggle("Reveal output in Finder", isOn: Binding(
                    get: { settings.autoRevealAfterProcess },
                    set: { settings.autoRevealAfterProcess = $0 }
                ))
            }
            Section("Version") {
                LabeledContent("Version") {
                    Text("\(AppVersion.short) (build \(AppVersion.build))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var processingTab: some View {
        Form {
            Section("Engine") {
                Picker("", selection: Binding(
                    get: { settings.processingEngine },
                    set: { settings.processingEngine = $0 }
                )) {
                    ForEach(ProcessingEngine.allCases) { e in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.displayName)
                            Text(e.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(e)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Loudness target") {
                LabeledContent("Normalize to") {
                    Picker("", selection: Binding(
                        get: { settings.loudnessTarget },
                        set: { settings.loudnessTarget = $0 }
                    )) {
                        ForEach(LoudnessTarget.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
            }

            Section("Cleanup") {
                Toggle("De-esser (sibilance reduction)", isOn: Binding(
                    get: { settings.deEsserEnabled },
                    set: { settings.deEsserEnabled = $0 }
                ))
                Toggle("De-clicker (pop / click removal)", isOn: Binding(
                    get: { settings.deClickerEnabled },
                    set: { settings.deClickerEnabled = $0 }
                ))
                Toggle("Reduce reverb (DeepFilterNet engine only)", isOn: Binding(
                    get: { settings.dereverbEnabled },
                    set: { settings.dereverbEnabled = $0 }
                ))
                .disabled(settings.processingEngine != .deepFilterNet)
            }

            Section("Channels") {
                Toggle("Preserve stereo (skip mono downmix)", isOn: Binding(
                    get: { settings.preserveStereo },
                    set: { settings.preserveStereo = $0 }
                ))
                Text("Voice work normally wants mono. Turn this on for music podcasts or stereo field recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var advancedTab: some View {
        Form {
            Section("DeepFilterNet binary") {
                LabeledContent("Path override") {
                    HStack {
                        TextField("Auto-detect", text: Binding(
                            get: { settings.deepFilterPathOverride },
                            set: { settings.deepFilterPathOverride = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseDeepFilterBinary() }
                        Button("Clear") { settings.deepFilterPathOverride = "" }
                    }
                }
                dfnStatusRow
            }

            Section("FFmpeg binary") {
                ffmpegStatusRow
            }

            Section("Install hints") {
                VStack(alignment: .leading, spacing: 6) {
                    copyableCommand("brew install ffmpeg")
                    copyableCommand("cargo install deep_filter")
                    Text("DeepFilterNet needs Rust's `cargo` (install with `brew install rust`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dfnStatusRow: some View {
        let found = DeepFilterNetLocator.find(
            override: settings.deepFilterPathOverride
        )
        return LabeledContent("Status") {
            HStack(spacing: 6) {
                if let url = found {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Not found — install or set the override path above.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private var ffmpegStatusRow: some View {
        let found = FFmpegLocator.find()
        return LabeledContent("Status") {
            HStack(spacing: 6) {
                if let url = found {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Not found — install ffmpeg.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose output folder"
        panel.prompt = "Choose"
        panel.directoryURL = settings.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
    }

    private func chooseDeepFilterBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Locate deep-filter binary"
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url {
            settings.deepFilterPathOverride = url.path
        }
    }

    private func copyableCommand(_ cmd: String) -> some View {
        HStack(spacing: 8) {
            Text(cmd)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// Empty-state landing pane. Big drag-and-drop target plus the same
/// profile + enhancement knobs that show in `ClipDetailView`, so the
/// user can configure the run before queuing anything.
struct DropZoneView: View {
    @EnvironmentObject var queue: ProcessingQueue
    @EnvironmentObject var settings: SettingsStore
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            dropTarget
                .frame(maxWidth: 540, maxHeight: 280)
            ProcessingControls()
                .frame(maxWidth: 540)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2,
                                                 dash: [8, 6]))
                .foregroundStyle(isTargeted
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text("Drop audio or video here")
                    .font(.title3)
                Text("m4a · mp3 · wav · mp4 · mov · aif · aac · caf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted
                      ? Color.accentColor.opacity(0.06)
                      : Color.secondary.opacity(0.04))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            queue.ingest(urls: collected, settings: settings)
        }
        return !providers.isEmpty
    }
}

/// The profile picker + enhancement toggle. Lives in its own view so
/// it can be shared between `DropZoneView` and `ClipDetailView`.
struct ProcessingControls: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var showFineTune: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profile")
                    .font(.subheadline)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: Binding(
                    get: { settings.profile },
                    set: { settings.profile = $0 }
                )) {
                    ForEach(ProcessingProfile.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(settings.profile.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 80)

            HStack {
                Text("Output")
                    .font(.subheadline)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: Binding(
                    get: { settings.outputFormat },
                    set: { settings.outputFormat = $0 }
                )) {
                    ForEach(OutputFormat.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                Toggle(isOn: Binding(
                    get: { settings.enhancementEnabled },
                    set: { settings.enhancementEnabled = $0 }
                )) {
                    Text("Enhancement chain")
                }
                .toggleStyle(.checkbox)
                .help("Adds compression + limiting + normalization for a podcast-style sound.")
            }

            HStack(spacing: 8) {
                Button {
                    showFineTune = true
                } label: {
                    Label("Tune…", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .help("Override individual filter parameters (high-pass, denoise depth, compressor, limiter, etc.)")
                if settings.customTuningEnabled && settings.filterTuning.hasAnyOverride {
                    Label("Custom tuning active",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .sheet(isPresented: $showFineTune) {
            FineTuneSheet()
                .environmentObject(settings)
        }
    }
}

import SwiftUI

/// Per-channel Video settings sheet. Tabbed editor matching Kyno's
/// Video Settings flyout (Images #80-#86): Encoding / Filters / LUTs
/// / Overlays. Each tab binds against the shared `TranscodeOptions`
/// — so a change here propagates back to the parent ConvertSheet's
/// `editableOptions` and ultimately into the composable runtime when
/// the user hits Start.
struct VideoSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var options: TranscodeOptions

    @State private var tab: Tab = .encoding

    enum Tab: String, CaseIterable, Identifiable {
        case encoding, filters, luts, overlays
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .encoding: return "Encoding"
            case .filters:  return "Filters"
            case .luts:     return "LUTs"
            case .overlays: return "Overlays"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .encoding: encodingTab
                    case .filters:  filtersTab
                    case .luts:     lutsTab
                    case .overlays: overlaysTab
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        HStack {
            Text("Video Settings").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Encoding tab

    @ViewBuilder
    private var encodingTab: some View {
        switch options.video {
        case .copy:
            Text("Video is set to Copy — no encoding parameters apply. Switch the Video channel to Re-Encode in the main Convert dialog to edit codec, frame rate, size, and bitrate.")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .disabled:
            Text("Video is disabled — output will have no video track. Switch the Video channel to Copy or Re-Encode in the main Convert dialog to restore.")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .reencode(let encoding):
            encodingForm(encoding: encoding)
        }
    }

    @ViewBuilder
    private func encodingForm(encoding: VideoEncoding) -> some View {
        let codecBinding = Binding<VideoCodec>(
            get: { encoding.codec },
            set: { newCodec in
                guard var e = videoEncodingBinding()?.wrappedValue else { return }
                e.codec = newCodec
                videoEncodingBinding()?.wrappedValue = e
            }
        )

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Codec:").foregroundStyle(.secondary)
                Picker("", selection: codecBinding) {
                    ForEach(VideoCodec.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
            }
            GridRow {
                Text("Frame rate:").foregroundStyle(.secondary)
                frameRatePicker(encoding: encoding)
            }
            GridRow {
                Text("Size:").foregroundStyle(.secondary)
                sizePicker(encoding: encoding)
            }
            GridRow {
                Text("Quality:").foregroundStyle(.secondary)
                qualityControl(encoding: encoding)
            }
        }
        .font(.callout)
    }

    private func videoEncodingBinding() -> Binding<VideoEncoding>? {
        guard case .reencode(let e) = options.video else { return nil }
        return Binding<VideoEncoding>(
            get: { e },
            set: { options.video = .reencode($0) }
        )
    }

    @ViewBuilder
    private func frameRatePicker(encoding: VideoEncoding) -> some View {
        let binding = Binding<FrameRateSpec>(
            get: { encoding.frameRate },
            set: { newRate in
                guard var e = videoEncodingBinding()?.wrappedValue else { return }
                e.frameRate = newRate
                videoEncodingBinding()?.wrappedValue = e
            }
        )
        Picker("", selection: binding) {
            Text("Like Source").tag(FrameRateSpec.likeSource)
            Text("23.976 fps").tag(FrameRateSpec.fixed(23.976))
            Text("24 fps").tag(FrameRateSpec.fixed(24))
            Text("25 fps").tag(FrameRateSpec.fixed(25))
            Text("29.97 fps").tag(FrameRateSpec.fixed(29.97))
            Text("30 fps").tag(FrameRateSpec.fixed(30))
            Text("50 fps").tag(FrameRateSpec.fixed(50))
            Text("59.94 fps").tag(FrameRateSpec.fixed(59.94))
            Text("60 fps").tag(FrameRateSpec.fixed(60))
        }
        .labelsHidden()
        .frame(maxWidth: 200, alignment: .leading)
    }

    @ViewBuilder
    private func sizePicker(encoding: VideoEncoding) -> some View {
        let binding = Binding<SizeSpec>(
            get: { encoding.size },
            set: { newSize in
                guard var e = videoEncodingBinding()?.wrappedValue else { return }
                e.size = newSize
                videoEncodingBinding()?.wrappedValue = e
            }
        )
        Picker("", selection: binding) {
            Text("Like Source").tag(SizeSpec.likeSource)
            Text("3840×2160 (4K UHD)").tag(SizeSpec.fixed(width: 3840, height: 2160))
            Text("1920×1080 (1080p)").tag(SizeSpec.fixed(width: 1920, height: 1080))
            Text("1280×720 (720p)").tag(SizeSpec.fixed(width: 1280, height: 720))
            Text("960×540 (540p)").tag(SizeSpec.fixed(width: 960, height: 540))
            Text("Half (½×)").tag(SizeSpec.scale(0.5))
            Text("Quarter (¼×)").tag(SizeSpec.scale(0.25))
        }
        .labelsHidden()
        .frame(maxWidth: 240, alignment: .leading)
    }

    @ViewBuilder
    private func qualityControl(encoding: VideoEncoding) -> some View {
        let qualityBinding = Binding<QualityControl>(
            get: { encoding.quality },
            set: { newQ in
                guard var e = videoEncodingBinding()?.wrappedValue else { return }
                e.quality = newQ
                videoEncodingBinding()?.wrappedValue = e
            }
        )
        let modeBinding = Binding<QualityMode>(
            get: {
                switch encoding.quality {
                case .codecDefault: return .codecDefault
                case .bitrate:      return .bitrate
                case .crf:          return .crf
                }
            },
            set: { newMode in
                switch newMode {
                case .codecDefault: qualityBinding.wrappedValue = .codecDefault
                case .bitrate:      qualityBinding.wrappedValue = .bitrate(kbps: 10_000)
                case .crf:          qualityBinding.wrappedValue = .crf(value: 23)
                }
            }
        )
        HStack(spacing: 8) {
            Picker("", selection: modeBinding) {
                Text("Codec Default").tag(QualityMode.codecDefault)
                Text("Bitrate-based").tag(QualityMode.bitrate)
                Text("CRF").tag(QualityMode.crf)
            }
            .labelsHidden()
            .frame(width: 160)
            switch encoding.quality {
            case .bitrate(let kbps):
                TextField("", value: Binding<Int>(
                    get: { kbps },
                    set: { qualityBinding.wrappedValue = .bitrate(kbps: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                Text("kbit/s").foregroundStyle(.secondary)
            case .crf(let value):
                Stepper(value: Binding<Int>(
                    get: { value },
                    set: { qualityBinding.wrappedValue = .crf(value: $0) }
                ), in: 0...51) {
                    Text("CRF \(value)")
                }
            case .codecDefault:
                EmptyView()
            }
        }
    }

    private enum QualityMode: Hashable { case codecDefault, bitrate, crf }

    // MARK: - Filters tab

    @ViewBuilder
    private var filtersTab: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Toggle("Denoise", isOn: $options.filters.denoise)
                    .gridCellColumns(2)
            }
            GridRow {
                Toggle("Sharpen/Blur",
                        isOn: $options.filters.sharpenBlurEnabled)
                    .gridCellColumns(2)
            }
            if options.filters.sharpenBlurEnabled {
                GridRow {
                    Text("Luma radius:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.sharpenBlur.lumaRadius,
                            in: -50...50, step: 1)
                }
                GridRow {
                    Text("Luma strength:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.sharpenBlur.lumaStrength,
                            in: 0...5, step: 0.1)
                }
                GridRow {
                    Text("Chroma radius:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.sharpenBlur.chromaRadius,
                            in: -50...50, step: 1)
                }
                GridRow {
                    Text("Chroma strength:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.sharpenBlur.chromaStrength,
                            in: 0...5, step: 0.1)
                }
            }
            GridRow {
                Toggle("Add noise", isOn: $options.filters.addNoiseEnabled)
                    .gridCellColumns(2)
            }
            if options.filters.addNoiseEnabled {
                GridRow {
                    Text("Luma strength:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.addNoise.lumaStrength,
                            in: 0...1, step: 0.01)
                }
                GridRow {
                    Text("Chroma strength:").foregroundStyle(.secondary)
                    Slider(value: $options.filters.addNoise.chromaStrength,
                            in: 0...1, step: 0.01)
                }
            }
            GridRow {
                Text("Fade in (sec):").foregroundStyle(.secondary)
                Stepper(value: $options.filters.fadeInSeconds,
                         in: 0...10, step: 0.5) {
                    Text(String(format: "%.1f", options.filters.fadeInSeconds))
                }
            }
            GridRow {
                Text("Fade out (sec):").foregroundStyle(.secondary)
                Stepper(value: $options.filters.fadeOutSeconds,
                         in: 0...10, step: 0.5) {
                    Text(String(format: "%.1f", options.filters.fadeOutSeconds))
                }
            }
        }
        .font(.callout)
    }

    // MARK: - LUTs tab

    @ViewBuilder
    private var lutsTab: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Camera LUT:").foregroundStyle(.secondary)
                lutPicker(binding: $options.cameraLUT, isCamera: true)
            }
            GridRow {
                Text("Creative LUT:").foregroundStyle(.secondary)
                lutPicker(binding: $options.creativeLUT, isCamera: false)
            }
            GridRow {
                Text("").foregroundStyle(.secondary)
                Text("Camera LUT corrects input log → Rec.709. Creative LUT is the look applied on top. Both bake into the output when applied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func lutPicker(binding: Binding<LUTSelection>,
                            isCamera: Bool) -> some View {
        // We represent the picker via a simplified Tag enum so the
        // Picker stays Hashable. C22 — `.file` mode now opens an
        // NSOpenPanel; the chosen path lands on the binding as
        // `LUTSelection.file(path:)`. Cancel reverts to the previous
        // mode so a stray click on "Pick from disk…" doesn't strand
        // the user on a path-less .file selection.
        let modeBinding = Binding<LUTMode>(
            get: {
                switch binding.wrappedValue {
                case .none:              return .none
                case .automatic:         return .automatic
                case .sidecarIfPresent:  return .sidecarIfPresent
                case .asDefinedInPlayer: return .asDefinedInPlayer
                case .file:              return .file
                }
            },
            set: { mode in
                switch mode {
                case .none:              binding.wrappedValue = .none
                case .automatic:         binding.wrappedValue = .automatic
                case .sidecarIfPresent:  binding.wrappedValue = .sidecarIfPresent
                case .asDefinedInPlayer: binding.wrappedValue = .asDefinedInPlayer
                case .file:
                    let prev = binding.wrappedValue
                    if let picked = Self.pickLUTFile() {
                        binding.wrappedValue = .file(path: picked.path)
                    } else {
                        // Cancelled — revert to the previous mode
                        // so the picker doesn't get stuck on an
                        // empty .file selection.
                        binding.wrappedValue = prev
                    }
                }
            }
        )
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: modeBinding) {
                Text("None").tag(LUTMode.none)
                if isCamera {
                    Text("Automatic (if applicable)").tag(LUTMode.automatic)
                }
                Text("Sidecar file (if present)").tag(LUTMode.sidecarIfPresent)
                Text("As Defined in Player").tag(LUTMode.asDefinedInPlayer)
                Text("Pick from disk…").tag(LUTMode.file)
            }
            .labelsHidden()
            .frame(maxWidth: 280, alignment: .leading)
            // C22 — surface the currently-picked LUT filename when
            // .file mode is active. Easy way to verify which custom
            // LUT will bake without re-running the panel.
            if case .file(let path) = binding.wrappedValue, !path.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                    Text((path as NSString).lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") {
                        if let picked = Self.pickLUTFile() {
                            binding.wrappedValue = .file(path: picked.path)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .frame(maxWidth: 280, alignment: .leading)
            }
        }
    }

    /// C22 — open-panel helper for LUT file selection. Filters to
    /// the formats `LUTService.load(url:)` already understands
    /// (`.cube`, `.3dl`, `.dat`, `.lut`) so the user can't pick a
    /// file that'll just fail at bake time.
    private static func pickLUTFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []  // fall back to extension filter
        panel.message = "Pick a LUT file to bake into the export."
        // Restrict by extension — `allowedFileTypes` is the
        // pre-UTType API but still honored on macOS 14+. Lets the
        // panel grey out unsupported files instead of accepting them
        // and failing at LUTService.load().
        if #available(macOS 11, *) {
            // Empty allowedContentTypes + non-empty
            // allowedFileTypes is the documented escape hatch for
            // "filter by extension only".
        }
        panel.allowedFileTypes = ["cube", "3dl", "dat", "lut"]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private enum LUTMode: Hashable {
        case none, automatic, sidecarIfPresent, asDefinedInPlayer, file
    }

    // MARK: - Overlays tab

    @ViewBuilder
    private var overlaysTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timecode Overlay").font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("").foregroundStyle(.secondary)
                    Toggle("Render Timecode Overlay",
                            isOn: $options.overlays.timecodeEnabled)
                }
                if options.overlays.timecodeEnabled {
                    GridRow {
                        Text("Size:").foregroundStyle(.secondary)
                        Picker("", selection: $options.overlays.timecodeSize) {
                            Text("Small").tag(OverlaySize.small)
                            Text("Regular").tag(OverlaySize.regular)
                            Text("Large").tag(OverlaySize.large)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                    GridRow {
                        Text("Position:").foregroundStyle(.secondary)
                        Picker("", selection: $options.overlays.timecodePosition) {
                            ForEach(OverlayPosition.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200, alignment: .leading)
                    }
                    GridRow {
                        Text("Opacity:").foregroundStyle(.secondary)
                        Slider(value: $options.overlays.timecodeOpacity,
                                in: 0...1, step: 0.05)
                    }
                }
            }
            .font(.callout)
        }
    }
}

import SwiftUI
import AppKit

/// Kyno-style "Content" inspector for the currently selected clip:
/// rich file metadata block stacked above a clickable frame grid.
///
/// Frame grid is a 30-thumb (5×6) set. Cached independently of the
/// 12-frame hover-scrub strip so neither clobbers the other.
/// User-selectable thumbnail size for the Frames grid. Persists via
/// @AppStorage so the choice survives selection changes + relaunches.
enum FrameGridSize: String, CaseIterable, Identifiable {
    case small, medium, large, xlarge
    var id: String { rawValue }
    var columns: Int {
        switch self {
        case .small:  return 5
        case .medium: return 4
        case .large:  return 3
        case .xlarge: return 2
        }
    }
    var label: String {
        switch self {
        case .small:  return "S"
        case .medium: return "M"
        case .large:  return "L"
        case .xlarge: return "XL"
        }
    }
}

struct ClipContentView: View {
    let asset: Asset
    let onSeek: (Double) -> Void

    @State private var details: ClipDetails?
    @State private var frameURLs: [URL] = []
    @State private var loadingFrames = true

    @AppStorage("frameGridSize") private var frameSizeRaw: String = FrameGridSize.medium.rawValue
    private var frameSize: FrameGridSize {
        FrameGridSize(rawValue: frameSizeRaw) ?? .medium
    }

    private let frameCount = 30
    private var columns: [GridItem] {
        [GridItem](repeating: GridItem(.flexible(), spacing: 4),
                    count: frameSize.columns)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metadataBlock
                Divider()
                framesBlock
            }
            .padding(12)
        }
        .onAppear(perform: load)
        .onChange(of: asset.path) { _, _ in load() }
    }

    // MARK: - Metadata block

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(asset.filename)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .help(asset.path)
            Text(asset.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let d = details {
                FieldGrid(rows: detailRows(d))
                    .padding(.top, 6)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading clip details…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
    }

    private func detailRows(_ d: ClipDetails) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        rows.append(("Size", byteCount(d.sizeBytes)))
        if let m = d.modificationDate {
            rows.append(("Modified", longDate(m)))
        }
        if let c = d.creationDate {
            rows.append(("Recorded", longDate(c)))
        }
        if let f = d.container {
            rows.append(("Container", f))
        }
        if let dur = d.durationSeconds {
            rows.append(("Duration", timecode(dur)))
        }
        let totalBitrate = (d.videoBitrateBps ?? 0) + (d.audioBitrateBps ?? 0)
        if totalBitrate > 0 {
            rows.append(("Total bitrate", mbits(totalBitrate)))
        }

        // Video line — codec + resolution + aspect + fps + video bitrate
        var videoBits: [String] = []
        if let c = d.videoCodec { videoBits.append(c) }
        if let w = d.widthPx, let h = d.heightPx {
            videoBits.append("\(w) × \(h)")
            videoBits.append(aspectLabel(w: w, h: h))
        }
        if let r = d.frameRate {
            videoBits.append(String(format: "%.2f fps", r))
        }
        if let vb = d.videoBitrateBps, vb > 0 {
            videoBits.append(mbits(vb))
        }
        if !videoBits.isEmpty {
            rows.append(("Video", videoBits.joined(separator: ", ")))
        }

        // Audio line — codec + sample rate + channel layout + bitrate
        var audioBits: [String] = []
        if let c = d.audioCodec { audioBits.append(c) }
        if let r = d.audioSampleRate { audioBits.append(String(format: "%.0f kHz", r / 1000)) }
        if let ch = d.audioChannels {
            audioBits.append(ch == 1 ? "Mono" : (ch == 2 ? "Stereo" : "\(ch) ch"))
        }
        if let ab = d.audioBitrateBps, ab > 0 {
            audioBits.append(kbits(ab))
        }
        if !audioBits.isEmpty {
            rows.append(("Audio", audioBits.joined(separator: ", ")))
        }
        return rows
    }

    // MARK: - Frames block

    private var framesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Frames").font(.headline)
                Spacer()
                Picker("", selection: Binding(
                    get: { frameSize },
                    set: { frameSizeRaw = $0.rawValue }
                )) {
                    ForEach(FrameGridSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                .controlSize(.small)
                if !frameURLs.isEmpty {
                    Text("\(frameURLs.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if loadingFrames && frameURLs.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Extracting \(frameCount) frames…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if frameURLs.isEmpty {
                Text("Could not extract frames.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(frameURLs.enumerated()), id: \.offset) { idx, url in
                        FrameGridCell(url: url, index: idx, total: frameURLs.count,
                                       onClick: { secs in onSeek(secs) },
                                       duration: details?.durationSeconds ?? asset.durationSeconds ?? 0)
                    }
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func load() {
        details = nil
        frameURLs = []
        loadingFrames = true

        Task {
            let d = await ClipDetailsService.load(asset: asset)
            await MainActor.run { self.details = d }
        }
        Task {
            let urls = await ThumbnailService.thumbnails(for: asset, count: frameCount)
            await MainActor.run {
                self.frameURLs = urls
                self.loadingFrames = false
            }
        }
    }

    // MARK: - Formatting helpers

    private func byteCount(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: n)) (\(n) bytes)"
    }

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func timecode(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let frames = Int((seconds - Double(total)) * (asset.frameRate ?? 30))
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, frames)
    }

    private func mbits(_ bps: Double) -> String {
        String(format: "%.2f MBit/s", bps / 1_000_000)
    }

    private func kbits(_ bps: Double) -> String {
        String(format: "%.0f kBit/s", bps / 1_000)
    }

    private func aspectLabel(w: Int, h: Int) -> String {
        let g = gcd(w, h)
        return "\(w / g):\(h / g)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

private struct FieldGrid: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rows[i].label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Text(rows[i].value)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}

/// Frames-only view used by the Detail-view "Content" tab —
/// renders the same N-up thumbnail grid `ClipContentView` does in
/// its `framesBlock`, but without the duplicated file-metadata
/// header (the inline Detail view already shows that on the left).
/// Click-to-seek delegates back to the parent player via `onSeek`.
struct ClipFramesGrid: View {
    let asset: Asset
    let onSeek: (Double) -> Void

    @State private var frameURLs: [URL] = []
    @State private var loading: Bool = true
    @AppStorage("frameGridSize") private var frameSizeRaw: String = FrameGridSize.medium.rawValue
    private var frameSize: FrameGridSize {
        FrameGridSize(rawValue: frameSizeRaw) ?? .medium
    }
    private let frameCount = 30
    private var columns: [GridItem] {
        [GridItem](repeating: GridItem(.flexible(), spacing: 4),
                    count: frameSize.columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Frames").font(.headline)
                Spacer()
                Picker("", selection: Binding(
                    get: { frameSize },
                    set: { frameSizeRaw = $0.rawValue }
                )) {
                    ForEach(FrameGridSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                .controlSize(.small)
                if !frameURLs.isEmpty {
                    Text("\(frameURLs.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if loading && frameURLs.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Extracting \(frameCount) frames…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if frameURLs.isEmpty {
                Text("Could not extract frames.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(frameURLs.enumerated()), id: \.offset) { idx, url in
                            FrameGridCell(
                                url: url, index: idx, total: frameURLs.count,
                                onClick: { secs in onSeek(secs) },
                                duration: asset.durationSeconds ?? 0
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .onAppear(perform: load)
        .onChange(of: asset.path) { _, _ in load() }
    }

    private func load() {
        frameURLs = []
        loading = true
        Task {
            let urls = await ThumbnailService.thumbnails(for: asset, count: frameCount)
            await MainActor.run {
                self.frameURLs = urls
                self.loading = false
            }
        }
    }
}

struct FrameGridCell: View {
    let url: URL
    let index: Int
    let total: Int
    let onClick: (Double) -> Void
    let duration: Double

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.18))
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(seekLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 2))
                .padding(2)
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            // Click-to-seek: map index to its bias position in the
            // clip (matches ThumbnailService's middle-90% spread).
            guard duration > 0, total > 0 else { return }
            let t = (Double(index) + 0.5) / Double(total)
            let bias = 0.05 + t * 0.90
            onClick(bias * duration)
        }
        .onAppear {
            if image == nil { image = NSImage(contentsOf: url) }
        }
    }

    private var seekLabel: String {
        // Show approx-seconds offset (matches the click-to-seek target).
        guard duration > 0, total > 0 else { return "" }
        let t = (Double(index) + 0.5) / Double(total)
        let bias = 0.05 + t * 0.90
        let secs = Int(bias * duration)
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}

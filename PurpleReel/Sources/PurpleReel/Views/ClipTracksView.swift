import SwiftUI

/// Per-track inspector matching Kyno's "Tracks" tab: video and audio
/// streams broken out with their AVFoundation-derived technical
/// details. Loads lazily on appear.
struct ClipTracksView: View {
    let asset: Asset

    @State private var details: ClipDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = details {
                    videoTrack(d)
                    audioTrack(d)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reading track info…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .onAppear(perform: load)
        .onChange(of: asset.path) { _, _ in load() }
    }

    @ViewBuilder
    private func videoTrack(_ d: ClipDetails) -> some View {
        if d.videoCodec != nil || d.widthPx != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Track #1").font(.headline)
                TrackFieldGrid(rows: [
                    ("Type", "Video"),
                    ("Codec", d.videoCodec ?? "—"),
                    ("Frame rate", d.frameRate.map { String(format: "%.2f fps", $0) } ?? "—"),
                    ("Resolution", resolutionLabel(d)),
                    ("Aspect ratio", aspectLabel(d)),
                    ("Bitrate", bitrate(d.videoBitrateBps)),
                    ("Duration", duration(d.durationSeconds)),
                ])
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func audioTrack(_ d: ClipDetails) -> some View {
        if d.audioCodec != nil || d.audioSampleRate != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Track #2").font(.headline)
                TrackFieldGrid(rows: [
                    ("Type", "Audio"),
                    ("Codec", d.audioCodec ?? "—"),
                    ("Sample rate", d.audioSampleRate.map { String(format: "%.0f Hz", $0) } ?? "—"),
                    ("Channels", channelLabel(d.audioChannels)),
                    ("Bitrate", bitrate(d.audioBitrateBps)),
                    ("Duration", duration(d.durationSeconds)),
                ])
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func load() {
        details = nil
        Task {
            let d = await ClipDetailsService.load(asset: asset)
            await MainActor.run { self.details = d }
        }
    }

    private func resolutionLabel(_ d: ClipDetails) -> String {
        if let w = d.widthPx, let h = d.heightPx { return "\(w) × \(h)" }
        return "—"
    }

    private func aspectLabel(_ d: ClipDetails) -> String {
        guard let w = d.widthPx, let h = d.heightPx, w > 0, h > 0 else { return "—" }
        let g = gcd(w, h)
        return "\(w / g):\(h / g)"
    }

    private func bitrate(_ bps: Double?) -> String {
        guard let bps, bps > 0 else { return "—" }
        if bps >= 1_000_000 { return String(format: "%.2f MBit/s", bps / 1_000_000) }
        return String(format: "%.0f kBit/s", bps / 1_000)
    }

    private func channelLabel(_ ch: Int?) -> String {
        guard let ch else { return "—" }
        switch ch {
        case 1: return "1.0 Mono"
        case 2: return "2.0 Stereo"
        case 6: return "5.1 Surround"
        default: return "\(ch) ch"
        }
    }

    private func duration(_ s: Double?) -> String {
        guard let s, s > 0 else { return "—" }
        return String(format: "%.3fs", s)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

private struct TrackFieldGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rows[i].0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Text(rows[i].1)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}

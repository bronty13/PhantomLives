import SwiftUI

/// Tiny inline audio waveform for the List-view "Waveform" column
/// (Kyno-parity row 68). Each cell:
///   1. On appear, hits `WaveformService.cachedOrGenerate` so the
///      first-render cost is a JSON read off SSD once the cache is
///      primed (one-time 1-2s/clip the first time).
///   2. Renders a mirrored peak bar via `WaveformShape` (same shape
///      as the player scrubber, just smaller).
///
/// Image / audio-only assets show their waveform too; video assets
/// without an audio track show a "—" so the row stays readable.
struct WaveformInlineView: View {
    let asset: Asset

    @State private var samples: WaveformSamples?
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let s = samples {
                WaveformShape(peaks: s.peaks)
                    .fill(Color.secondary.opacity(0.7))
                    .frame(height: 18)
            } else if loadFailed {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // While the generator runs, paint a faint placeholder
                // so the row doesn't visibly snap on first appearance.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 18)
            }
        }
        .onAppear(perform: load)
        .onChange(of: asset.path) { _, _ in
            samples = nil
            loadFailed = false
            load()
        }
    }

    private func load() {
        let url = URL(fileURLWithPath: asset.path)
        Task {
            let s = await WaveformService.cachedOrGenerate(url: url)
            await MainActor.run {
                if let s {
                    samples = s
                } else {
                    loadFailed = true
                }
            }
        }
    }
}

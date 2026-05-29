import SwiftUI

/// Stacked-pair waveform view: original on top, cleaned on the bottom
/// (when available). Overlays the playhead and a draggable trim
/// region. Acts as the visual control surface for region trimming.
struct WaveformView: View {
    @ObservedObject var clip: Clip
    @ObservedObject var player: AudioPlayer

    @State private var sourceWaveform: WaveformGenerator.Result?
    @State private var processedWaveform: WaveformGenerator.Result?
    @State private var loadError: String?

    /// While dragging a trim handle we keep the in-flight value in
    /// `@State` to avoid spamming the model + dropping frames. On
    /// drag-end we commit to `clip.trimStart` / `clip.trimEnd`.
    @State private var dragStart: Double?
    @State private var dragEnd: Double?

    private let waveHeight: CGFloat = 56
    private let pairSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .task(id: clip.sourceURL) {
            await loadWaveforms()
        }
        .onChange(of: clip.outputURL) { _, _ in
            Task { await loadProcessedWaveform() }
        }
    }

    private var header: some View {
        HStack {
            Label("Waveform", systemImage: "waveform")
                .font(.headline)
            Spacer()
            if clip.trimStart != nil || clip.trimEnd != nil {
                Button {
                    clip.trimStart = nil
                    clip.trimEnd = nil
                    dragStart = nil
                    dragEnd = nil
                } label: {
                    Label("Clear Trim", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            if let total = clip.durationSeconds {
                Text(trimSummary(totalDuration: total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                Text("Couldn't load waveform: \(loadError)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
        } else if sourceWaveform == nil {
            HStack {
                ProgressView().controlSize(.small)
                Text("Drawing waveform…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: pairSpacing) {
                        waveRow(result: sourceWaveform,
                                title: "Original",
                                color: .accentColor)
                        waveRow(result: processedWaveform,
                                title: "Cleaned",
                                color: .green)
                    }
                    overlay(width: proxy.size.width,
                            height: proxy.size.height)
                }
            }
            .frame(height: waveHeight * 2 + pairSpacing)
        }
    }

    @ViewBuilder
    private func waveRow(result: WaveformGenerator.Result?,
                         title: String,
                         color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
            if let result {
                WaveformShape(peaks: result)
                    .fill(color.opacity(0.75))
                    .padding(.vertical, 4)
            } else {
                Text(title == "Cleaned"
                     ? "(no output yet)"
                     : "(no waveform)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
        .frame(height: waveHeight)
    }

    private func overlay(width: CGFloat, height: CGFloat) -> some View {
        let total = clip.durationSeconds ?? player.duration
        guard total > 0 else { return AnyView(EmptyView()) }

        let start = dragStart ?? clip.trimStart ?? 0
        let end   = dragEnd   ?? clip.trimEnd   ?? total
        let startX = CGFloat(start / total) * width
        let endX   = CGFloat(end / total)   * width
        let playTime = player.duration > 0 ? player.currentTime : 0
        let playX = CGFloat(playTime / total) * width

        return AnyView(
            ZStack(alignment: .topLeading) {
                // Bottom layer: full-width click-to-seek hitbox.
                // Single tap moves the playhead to the clicked point;
                // drags here scrub. Trim handles + the playhead drag
                // gesture sit on top and win on overlap via ZStack
                // ordering. Audio pauses for the duration of the drag
                // (begin/end scrub) so the user doesn't hear bursts
                // of the audio at each position they hover.
                Color.clear
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                player.beginScrub(url: currentlyPlayingOrNil())
                                let t = seconds(forX: value.location.x,
                                                width: width,
                                                total: total)
                                player.scrubSeek(to: t)
                            }
                            .onEnded { _ in
                                player.endScrub()
                            }
                    )

                // Trim region tint.
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: max(0, endX - startX), height: height)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                // Playhead — always rendered when there's a duration.
                // Drag the playhead body or its widened hitbox to
                // scrub; the active audio player jumps in real time.
                playheadHandle(x: playX,
                               width: width,
                               height: height,
                               total: total)

                // Trim handles (rendered LAST so they sit on top of
                // the playhead and win when they overlap — users care
                // more about adjusting trim than scrubbing in that
                // narrow overlap region).
                trimHandle(x: startX, height: height) { newX in
                    let proposed = clamped(seconds: Double(newX / width) * total,
                                            min: 0,
                                            max: (dragEnd ?? end) - 0.05)
                    dragStart = proposed
                } onEnd: {
                    if let s = dragStart {
                        clip.trimStart = s > 0 ? s : nil
                    }
                    dragStart = nil
                }
                trimHandle(x: endX, height: height) { newX in
                    let proposed = clamped(seconds: Double(newX / width) * total,
                                            min: (dragStart ?? start) + 0.05,
                                            max: total)
                    dragEnd = proposed
                } onEnd: {
                    if let e = dragEnd {
                        clip.trimEnd = e < total ? e : nil
                    }
                    dragEnd = nil
                }
            }
            .allowsHitTesting(true)
        )
    }

    /// Draggable playhead. A thin red line for visual reference plus
    /// a wider invisible hitbox for grabbability.
    private func playheadHandle(x: CGFloat,
                                width: CGFloat,
                                height: CGFloat,
                                total: Double) -> some View {
        ZStack {
            // Hitbox — 14pt wide so users can grab it without pixel
            // precision.
            Color.clear
                .frame(width: 14, height: height)
                .contentShape(Rectangle())
            // Visual: thin red line with a small grip-knob at the top
            // for affordance.
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
            }
            .frame(height: height, alignment: .top)
        }
        .offset(x: x - 7)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    player.beginScrub(url: currentlyPlayingOrNil())
                    let t = seconds(forX: x + value.translation.width,
                                    width: width,
                                    total: total)
                    player.scrubSeek(to: t)
                }
                .onEnded { _ in
                    player.endScrub()
                }
        )
        .help("Drag to scrub")
    }

    /// Convert an X coordinate within the waveform pane into a
    /// seconds-into-clip value, clamped to `[0, total]`.
    private func seconds(forX x: CGFloat,
                         width: CGFloat,
                         total: Double) -> Double {
        let pct = max(0, min(1, Double(x / max(width, 1))))
        return pct * total
    }

    /// Resolve which URL the player should attach to if it isn't
    /// already loaded — needed for click-to-seek before play.
    /// Returns nil when there's nothing reasonable to attach
    /// (e.g. cleaned waveform but cleaned file not on disk).
    private func currentlyPlayingOrNil() -> URL? {
        if let now = player.nowPlayingURL { return now }
        return clip.sourceURL
    }

    private func trimHandle(x: CGFloat,
                            height: CGFloat,
                            onDrag: @escaping (CGFloat) -> Void,
                            onEnd: @escaping () -> Void) -> some View {
        // Two-layer hitbox: a wide invisible drag area for grabbability
        // and a thin visible line so the user can see where they're
        // grabbing.
        ZStack {
            Color.clear
                .frame(width: 16, height: height)
                .contentShape(Rectangle())
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: height)
        }
        .offset(x: x - 8)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDrag(x + value.translation.width)
                }
                .onEnded { _ in onEnd() }
        )
    }

    // MARK: - Loading

    private func loadWaveforms() async {
        loadError = nil
        do {
            sourceWaveform = try await WaveformCache.shared.waveform(for: clip.sourceURL)
        } catch {
            loadError = error.localizedDescription
        }
        await loadProcessedWaveform()
    }

    private func loadProcessedWaveform() async {
        guard let out = clip.outputURL,
              FileManager.default.fileExists(atPath: out.path) else {
            processedWaveform = nil
            return
        }
        processedWaveform = try? await WaveformCache.shared.waveform(for: out)
    }

    // MARK: - Helpers

    private func clamped(seconds: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(Swift.max(seconds, lo), hi)
    }

    private func trimSummary(totalDuration total: Double) -> String {
        let start = clip.trimStart ?? 0
        let end   = clip.trimEnd   ?? total
        let span  = max(0, end - start)
        if clip.trimStart == nil && clip.trimEnd == nil {
            return "\(format(total))"
        }
        return "trim \(format(start))–\(format(end)) (\(format(span)))"
    }

    private func format(_ s: Double) -> String {
        let mins = Int(s) / 60
        let secs = s - Double(mins * 60)
        return String(format: "%d:%05.2f", mins, secs)
    }
}

/// Path-based waveform rendering. Faster than drawing 1500 individual
/// rectangles in a `Canvas`, and crisp at any DPI.
struct WaveformShape: Shape {
    let peaks: WaveformGenerator.Result

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = peaks.maxPeaks.count
        guard count > 0 else { return p }
        let midY = rect.midY
        let halfH = rect.height / 2
        let stepX = rect.width / CGFloat(count)
        for i in 0..<count {
            let x = CGFloat(i) * stepX
            let topY = midY - CGFloat(peaks.maxPeaks[i]) * halfH
            let botY = midY + CGFloat(peaks.minPeaks[i]) * halfH
            p.addRect(CGRect(x: x,
                             y: topY,
                             width: max(stepX - 0.5, 0.5),
                             height: max(botY - topY, 1)))
        }
        return p
    }
}

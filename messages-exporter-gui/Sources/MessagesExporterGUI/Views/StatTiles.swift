import SwiftUI

/// Four-tile stat strip below the main heading. Tiles read from
/// `runner.runStats`; values that haven't been measured yet render as an
/// em-dash so the layout doesn't shift between runs.
///
/// Tiles, left to right:
///   Messages     — set mid-run (parsed from `[3/5] N messages in range`),
///                  refined post-run from metadata.json
///   Attachments  — set post-run (sum of per-message attachments arrays)
///   Span         — derived from the configured From/To dates; available
///                  immediately so the tile is not always blank
///   Output size  — set post-run (folder walk; allocated-size bytes)
struct StatTiles: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner

    /// Span shown when no run is in flight: derive from the form's
    /// pending dates so the tile gives feedback as the user picks them.
    let pendingStart: Date
    let pendingEnd:   Date

    var body: some View {
        let stats = runner.runStats

        // Prefer the runner's recorded span (set when a run kicks off);
        // before any run, fall back to the form's pending dates so the
        // user sees their selection reflected.
        let spanStart = stats.spanStart ?? pendingStart
        let spanEnd   = stats.spanEnd   ?? pendingEnd

        HStack(spacing: 10) {
            tile(
                kicker: "Messages",
                value: RunStats.formatInt(stats.messageCount),
                detail: stats.messageCount.map { _ in "in range" } ?? "—"
            )
            tile(
                kicker: "Attachments",
                value: RunStats.formatInt(stats.attachmentCount),
                detail: attachmentsDetail(stats)
            )
            tile(
                kicker: "Span",
                value: RunStats.formatSpan(start: spanStart, end: spanEnd),
                detail: RunStats.formatSpanCaption(start: spanStart, end: spanEnd)
            )
            tile(
                kicker: "Output size",
                value: RunStats.formatBytes(stats.outputBytes),
                detail: stats.outputBytes == nil ? "—" : "on disk",
                accent: true
            )
        }
    }

    @ViewBuilder
    private func tile(kicker: String,
                      value: String,
                      detail: String,
                      accent: Bool = false) -> some View {
        GlassCard(cornerRadius: 12, accent: accent) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker.uppercased())
                    .font(MissionFont.kicker(10))
                    .tracking(1.0)
                    .foregroundStyle(t.inkMute)
                Text(value)
                    .font(MissionFont.display(28, weight: .semibold))
                    .foregroundStyle(accent ? t.accent : t.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(MissionFont.sans(11))
                    .foregroundStyle(t.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "912 photos · 38 voice" when we have detail; otherwise raw count
    /// or "—". Photo/video/voice counts come from metadata.json's summary.
    private func attachmentsDetail(_ s: RunStats) -> String {
        var parts: [String] = []
        if let p = s.photoCount, p > 0 { parts.append("\(p) photos") }
        if let v = s.videoCount, v > 0 { parts.append("\(v) videos") }
        if let a = s.voiceCount, a > 0 { parts.append("\(a) voice") }
        if parts.isEmpty { return s.attachmentCount == nil ? "—" : "files" }
        return parts.joined(separator: " · ")
    }
}

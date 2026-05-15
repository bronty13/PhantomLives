import SwiftUI

/// Four KPI tiles: channels, messages, files, output size. Updated
/// live as `ArchiveRunner.runStats` flows through.
struct StatTiles: View {
    let stats: RunStats

    var body: some View {
        HStack(spacing: 12) {
            tile(title: "CHANNELS", value: stats.channelCount.map(String.init) ?? "—")
            tile(title: "MESSAGES", value: stats.messageCount.map(String.init) ?? "—")
            tile(title: "FILES",    value: stats.fileCount.map(String.init) ?? "—")
            tile(title: "OUTPUT",   value: stats.outputBytes.map(formatBytes) ?? "—")
        }
    }

    private func tile(title: String, value: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.kicker())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppFont.display(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}

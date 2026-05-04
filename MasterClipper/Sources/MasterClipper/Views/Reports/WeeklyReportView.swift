import SwiftUI

/// Three-week go-live planning view + a list of every active clip not yet in
/// `production` status. Week boundaries follow Settings → General →
/// Calendar first-weekday. Anchor date can be shifted with the chevrons to
/// look at any historical or future window.
struct WeeklyReportView: View {
    @EnvironmentObject private var appState: AppState

    @State private var anchor: Date = Date()
    @State private var rollup: ReportService.WeeklyRollup?
    @State private var lastSavedURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let r = rollup {
                    weekSection(
                        title: "Last week",
                        subtitle: "Items that went live last week",
                        range: r.lastWeekRange,
                        items: r.lastWeek,
                        emptyMessage: "Nothing went live last week.",
                        accent: .secondary
                    )
                    weekSection(
                        title: "This week",
                        subtitle: "Items going live this week",
                        range: r.thisWeekRange,
                        items: r.thisWeek,
                        emptyMessage: "Nothing scheduled this week.",
                        accent: .accentColor
                    )
                    weekSection(
                        title: "Next week",
                        subtitle: "Items going live the following week",
                        range: r.nextWeekRange,
                        items: r.nextWeek,
                        emptyMessage: "Nothing scheduled for next week.",
                        accent: .blue
                    )
                    notInProductionSection(items: r.notInProduction)
                }
            }
            .padding(20)
        }
        .onAppear { reload() }
        .onChange(of: anchor) { _, _ in reload() }
        .onChange(of: appState.clips.count) { _, _ in reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Weekly report").font(.title3.weight(.semibold))
            Spacer()
            Menu {
                Button("Markdown…")  { exportMarkdown() }
                Button("PDF…")       { exportPDF() }
                Button("CSV…")       { exportCSV() }
            } label: {
                Label("Export this report…", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export the visible week's data — distinct from the toolbar Export which dumps the full clip dataset")
            .disabled(rollup == nil)

            if lastSavedURL != nil {
                Button {
                    if let url = lastSavedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help(lastSavedURL?.lastPathComponent ?? "")
            }

            Divider().frame(height: 18)

            Button {
                anchor = Calendar.current.date(byAdding: .day, value: -7, to: anchor) ?? anchor
            } label: { Image(systemName: "chevron.left") }
            Button("Today") { anchor = Date() }
            Button {
                anchor = Calendar.current.date(byAdding: .day, value: 7, to: anchor) ?? anchor
            } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - Export

    private func exportMarkdown() {
        guard let r = rollup else { return }
        let md = ExportService.exportWeeklyMarkdown(rollup: r, appState: appState)
        save(md.data(using: .utf8) ?? Data(), suggested: "MasterClipper-weekly-\(stamp()).md")
    }

    private func exportCSV() {
        guard let r = rollup else { return }
        let csv = ExportService.exportWeeklyCSV(rollup: r)
        save(csv.data(using: .utf8) ?? Data(), suggested: "MasterClipper-weekly-\(stamp()).csv")
    }

    private func exportPDF() {
        guard let r = rollup else { return }
        let data = ExportService.exportWeeklyPDF(rollup: r, appState: appState)
        save(data, suggested: "MasterClipper-weekly-\(stamp()).pdf")
    }

    private func save(_ data: Data, suggested: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(
            at: appState.settingsStore.resolvedExportDirectory,
            withIntermediateDirectories: true
        )
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                lastSavedURL = url
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn't save export"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func stamp() -> String {
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        let weekStart = rollup.map { isoFmt.string(from: $0.thisWeekRange.start) }
            ?? isoFmt.string(from: anchor)
        return weekStart
    }

    // MARK: - Week sections

    private func weekSection(
        title: String,
        subtitle: String,
        range: (start: Date, end: Date),
        items: [ReportService.WeeklyRollup.Item],
        emptyMessage: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Text(formatRange(range)).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        clipRow(item.clip, accent: accent)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.3), lineWidth: 1))
    }

    private func clipRow(_ clip: Clip, accent: Color) -> some View {
        Button {
            appState.focusedClipId = clip.id
            appState.selectedSection = .clips
        } label: {
            HStack(spacing: 10) {
                Text(clip.goLiveDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                PersonaPill(code: clip.personaCode)
                Text(clip.title.isEmpty ? "Untitled" : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                Spacer()
                statusPill(clip.statusEnum)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Not in production

    private func notInProductionSection(items: [ReportService.WeeklyRollup.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Not in production").font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Active clips that haven't reached the Production stage yet — every persona-scope site is not yet posted.")
                .font(.caption).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Everything's in production. 🎉")
                    .font(.callout).foregroundStyle(.green).padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        notInProdRow(item.clip)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.3), lineWidth: 1))
    }

    private func notInProdRow(_ clip: Clip) -> some View {
        Button {
            appState.focusedClipId = clip.id
            appState.selectedSection = .clips
        } label: {
            HStack(spacing: 10) {
                statusPill(clip.statusEnum)
                    .frame(width: 110, alignment: .leading)
                PersonaPill(code: clip.personaCode)
                Text(clip.title.isEmpty ? "Untitled" : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                Spacer()
                Text(clip.goLiveDate ?? "no go-live")
                    .font(.caption.monospaced())
                    .foregroundStyle((clip.goLiveDate ?? "").isEmpty ? .tertiary : .secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func statusPill(_ s: ClipStatus) -> some View {
        let color = statusColor(s)
        return HStack(spacing: 4) {
            Image(systemName: s.systemImage).font(.caption2)
            Text(s.label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.22), in: Capsule())
        .foregroundStyle(color)
    }

    private func statusColor(_ s: ClipStatus) -> Color {
        switch s {
        case .new:        return .gray
        case .editing:    return .orange
        case .toPost:     return .blue
        case .posting:    return .purple
        case .production: return .green
        case .archived:   return .secondary
        }
    }

    private func formatRange(_ range: (start: Date, end: Date)) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        // end is exclusive (start of next week); show inclusive last day.
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(f.string(from: range.start)) – \(f.string(from: lastDay))"
    }

    private func reload() {
        rollup = ReportService.weeklyRollup(appState: appState, anchor: anchor)
    }
}

import SwiftUI
import MasterClipperCore

struct ReportsRootView: View {
    enum Kind: String, CaseIterable, Hashable {
        case fullClip, weekly, postingStatus, categoryUsage, calendar, audit, informationNeeded

        var label: String {
            switch self {
            case .fullClip:           return "Full Clip Report"
            case .weekly:             return "Weekly Report"
            case .postingStatus:      return "Posting Status"
            case .categoryUsage:      return "Category Usage"
            case .calendar:           return "Calendar Rollup"
            case .audit:              return "Clip Audit"
            case .informationNeeded:  return "Information Needed"
            }
        }

        var icon: String {
            switch self {
            case .fullClip:           return "list.bullet.rectangle"
            case .weekly:             return "calendar.badge.exclamationmark"
            case .postingStatus:      return "paperplane"
            case .categoryUsage:      return "tag.fill"
            case .calendar:           return "calendar.badge.clock"
            case .audit:              return "checkmark.shield"
            case .informationNeeded:  return "questionmark.bubble"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var selection: Kind = .fullClip

    var body: some View {
        EdPageShell(
            eyebrow: "Section · Reports",
            headline: "Pull a report.",
            emphasized: "report",
            deck: "Read-only views over your clip data, ready to export as Markdown, CSV, or PDF.",
            trailing: AnyView(ExportMenu(reportKind: selection))
        ) {
            HSplitView {
                List(Kind.allCases, id: \.self, selection: $selection) { k in
                    Label(k.label, systemImage: k.icon).tag(k)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

                Group {
                    switch selection {
                    case .fullClip:       FullClipReportView()
                    case .weekly:         WeeklyReportView()
                    case .postingStatus:  PostingStatusReportView()
                    case .categoryUsage:  CategoryUsageReportView()
                    case .calendar:       CalendarReportView()
                    case .audit:              ClipAuditReportView()
                    case .informationNeeded:  InformationNeededReportView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Reports

struct FullClipReportView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Full clip report — \(appState.clips.count) clips")
                    .font(.title3.weight(.semibold))
                Spacer()
                ReportExportMenu(
                    suggestedBaseName: "MasterClipper-clips-\(stamp())",
                    provider: .init(
                        markdown: { ExportService.exportMarkdown(clips: clips, appState: appState).data(using: .utf8) ?? Data() },
                        pdf:      { ExportService.exportPDFReport(clips: clips, appState: appState) },
                        csv:      { ExportService.exportCSV(clips: clips, appState: appState).data(using: .utf8) ?? Data() }
                    )
                )
            }
            .padding(12)
            Divider()
            Table(clips) {
                TableColumn("ID")      { Text($0.id).font(.caption.monospaced()) }.width(min: 110)
                TableColumn("Persona") { Text($0.personaCode) }.width(min: 70)
                TableColumn("Title")   { Text($0.title.isEmpty ? "—" : $0.title) }
                TableColumn("Status")  { Text($0.statusEnum.label) }.width(min: 110)
                TableColumn("Length")  { Text(DurationFormatter.format($0.lengthSeconds)) }.width(min: 70)
                TableColumn("Go-Live") { Text($0.goLiveDate ?? "—") }.width(min: 100)
            }
        }
    }

    private var clips: [Clip] { appState.clips.sorted { $0.createdAt > $1.createdAt } }
}

struct PostingStatusReportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rows: [ReportService.PostingStatusRow] = []
    @State private var hideCompleted: Bool = true

    var visible: [ReportService.PostingStatusRow] {
        hideCompleted ? rows.filter { !$0.posted } : rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Posting status — \(rows.count) (clip × site) pairs")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("Hide already-posted", isOn: $hideCompleted)
                    .toggleStyle(.switch).controlSize(.small)
                ReportExportMenu(
                    suggestedBaseName: "MasterClipper-posting-status-\(stamp())",
                    provider: .init(
                        markdown: { ExportService.exportPostingStatusMarkdown(rows: visible).data(using: .utf8) ?? Data() },
                        pdf:      { ExportService.exportPostingStatusPDF(rows: visible) },
                        csv:      { ExportService.exportPostingStatusCSV(rows: visible).data(using: .utf8) ?? Data() }
                    )
                )
            }
            .padding(12)

            Divider()
            Table(visible) {
                TableColumn("Clip ID")  { Text($0.clipId).font(.caption.monospaced()) }.width(min: 120)
                TableColumn("Persona")  { Text($0.personaCode) }.width(min: 70)
                TableColumn("Title")    { Text($0.clipTitle) }
                TableColumn("Site")     { Text("\($0.siteName) (\($0.siteCode))").font(.caption) }.width(min: 160)
                TableColumn("Posted")   { row in
                    HStack {
                        if row.posted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                        if let d = row.postedDate { Text(d).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                }
                .width(min: 130)
            }
        }
        .onAppear { rows = ReportService.postingStatus(appState: appState) }
        .onChange(of: appState.clips.count) { _, _ in rows = ReportService.postingStatus(appState: appState) }
    }
}

struct CategoryUsageReportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rows: [ReportService.CategoryUsageRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Category usage")
                    .font(.title3.weight(.semibold))
                Spacer()
                ReportExportMenu(
                    suggestedBaseName: "MasterClipper-category-usage-\(stamp())",
                    provider: .init(
                        markdown: { ExportService.exportCategoryUsageMarkdown(rows: rows).data(using: .utf8) ?? Data() },
                        pdf:      { ExportService.exportCategoryUsagePDF(rows: rows) },
                        csv:      { ExportService.exportCategoryUsageCSV(rows: rows).data(using: .utf8) ?? Data() }
                    )
                )
            }
            .padding(12)
            Divider()
            Table(rows) {
                TableColumn("Category") { Text($0.name) }
                TableColumn("Clips")    { Text("\($0.clipCount)").font(.body.monospacedDigit()) }
                    .width(min: 90, ideal: 100)
            }
        }
        .onAppear { rows = ReportService.categoryUsage() }
    }
}

/// Date-stamp helper used by every report's suggested export filename.
@MainActor
private func stamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f.string(from: Date())
}

struct CalendarReportView: View {
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var rows: [ReportService.CalendarMonthRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Calendar rollup — \(year)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Stepper("Year \(year)", value: $year, in: 2020...2099)
                    .frame(width: 200)
            }
            .padding(12)

            Divider()
            Table(rows) {
                TableColumn("Month")    { Text($0.yearMonth).font(.body.monospaced()) }.width(min: 90)
                TableColumn("Persona")  { Text($0.personaCode) }.width(min: 70)
                TableColumn("Events")   { Text("\($0.count)").font(.body.monospacedDigit()) }
            }
        }
        .onAppear { rows = ReportService.calendarRollup(year: year) }
        .onChange(of: year) { _, newYear in rows = ReportService.calendarRollup(year: newYear) }
    }
}

// MARK: - Export menu

struct ExportMenu: View {
    @EnvironmentObject private var appState: AppState
    let reportKind: ReportsRootView.Kind

    var body: some View {
        Menu {
            Button("CSV…")       { exportCSV() }
            Button("Markdown…")  { exportMarkdown() }
            Button("XLSX…")      { exportXLSX() }
            Button("DOCX…")      { exportDOCX() }
            Button("PDF…")       { exportPDF() }
            Divider()
            Button("Full Data Export (HTML)…") { exportHTML() }
        } label: {
            Label("Export…", systemImage: "square.and.arrow.up")
        }
    }

    private func savePanel(suggested: String, types: [String]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(at: appState.settingsStore.resolvedExportDirectory,
                                                 withIntermediateDirectories: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private var exportClips: [Clip] { appState.clips }

    private func exportCSV() {
        let s = ExportService.exportCSV(clips: exportClips, appState: appState)
        guard let url = savePanel(suggested: "MasterClipper-\(stamp()).csv", types: ["csv"]) else { return }
        try? s.data(using: .utf8)?.write(to: url)
    }

    private func exportMarkdown() {
        let s = ExportService.exportMarkdown(clips: exportClips, appState: appState)
        guard let url = savePanel(suggested: "MasterClipper-\(stamp()).md", types: ["md"]) else { return }
        try? s.data(using: .utf8)?.write(to: url)
    }

    private func exportXLSX() {
        guard let data = ExportService.exportXLSX(clips: exportClips, appState: appState) else { return }
        guard let url = savePanel(suggested: "MasterClipper-\(stamp()).xlsx", types: ["xlsx"]) else { return }
        try? data.write(to: url)
    }

    private func exportDOCX() {
        guard let data = ExportService.exportDOCX(clips: exportClips, appState: appState) else { return }
        guard let url = savePanel(suggested: "MasterClipper-\(stamp()).docx", types: ["docx"]) else { return }
        try? data.write(to: url)
    }

    private func exportPDF() {
        let data = ExportService.exportPDFReport(clips: exportClips, appState: appState)
        guard let url = savePanel(suggested: "MasterClipper-\(stamp()).pdf", types: ["pdf"]) else { return }
        try? data.write(to: url)
    }

    private func exportHTML() {
        let s = HtmlExportService.build(clips: exportClips, appState: appState)
        guard let url = savePanel(suggested: "MasterClipper-export-\(stamp()).html", types: ["html"]) else { return }
        try? s.data(using: .utf8)?.write(to: url)
    }
}

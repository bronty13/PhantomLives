import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ReportsView: View {
    @EnvironmentObject var appState: AppState
    @State private var feedbackMessage = ""
    @State private var isFeedbackVisible = false

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var entries: [WeightEntry] { appState.entries }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if entries.isEmpty {
                    emptyState
                } else {
                    sectionLabel("PDF Report", icon: "doc.richtext.fill")
                    pdfRow
                    Divider()
                    sectionLabel("Export Data", icon: "square.and.arrow.up.fill")
                    exportGrid
                    statsStrip
                }
            }
            .padding(24)
        }
        .overlay(alignment: .bottom) {
            if isFeedbackVisible {
                feedbackBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.spring(duration: 0.3), value: isFeedbackVisible)
        .onReceive(NotificationCenter.default.publisher(for: .exportCSVRequested))  { _ in saveExport(.csv) }
        .onReceive(NotificationCenter.default.publisher(for: .exportMDRequested))   { _ in saveExport(.md) }
        .onReceive(NotificationCenter.default.publisher(for: .exportXLSXRequested)) { _ in saveExport(.xlsx) }
        .onReceive(NotificationCenter.default.publisher(for: .exportDOCXRequested)) { _ in saveExport(.docx) }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequested))  { _ in saveExport(.pdf) }
        .onReceive(NotificationCenter.default.publisher(for: .printRequested))      { _ in printReport() }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reports & Export")
                .font(.largeTitle.weight(.bold))
            Text("\(entries.count) entries · \(unit.label) · \(appState.settings.username)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.semibold))
    }

    // MARK: - PDF Row

    var pdfRow: some View {
        HStack(spacing: 12) {
            actionCard(
                icon: "printer.fill",
                title: "Print Report",
                subtitle: "Opens in Preview — print or share",
                color: .blue,
                action: printReport
            )
            actionCard(
                icon: "arrow.down.doc.fill",
                title: "Save PDF",
                subtitle: "Full report with stats and entry table",
                color: appState.effectiveAccentColor,
                action: { saveExport(.pdf) }
            )
        }
    }

    func actionCard(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Export Grid

    var exportGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 12
        ) {
            formatCard(.csv,  icon: "tablecells.fill",                label: "CSV",      subtitle: "Spreadsheet",    ext: ".csv",  color: .green)
            formatCard(.md,   icon: "doc.text.fill",                  label: "Markdown", subtitle: "Formatted report", ext: ".md",  color: .purple)
            formatCard(.xlsx, icon: "chart.bar.doc.horizontal.fill",  label: "XLSX",     subtitle: "Excel workbook", ext: ".xlsx", color: .teal)
            formatCard(.docx, icon: "doc.fill",                       label: "DOCX",     subtitle: "Word document",  ext: ".docx", color: .orange)
        }
    }

    enum ExportFmt { case csv, md, xlsx, docx, pdf }

    func formatCard(_ fmt: ExportFmt, icon: String, label: String, subtitle: String, ext: String, color: Color) -> some View {
        Button { saveExport(fmt) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(color)
                VStack(spacing: 3) {
                    Text(label).font(.callout.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(ext)
                        .font(.caption2.monospaced())
                        .foregroundStyle(color.opacity(0.8))
                }
                Label("Export", systemImage: "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Strip

    var statsStrip: some View {
        Group {
            if let stats = appState.stats {
                HStack(spacing: 0) {
                    stripPill("Start",   ExportService.fmt(stats.startWeight, unit: unit))
                    Divider().frame(height: 28)
                    stripPill("Current", ExportService.fmt(stats.currentWeight, unit: unit))
                    Divider().frame(height: 28)
                    stripPill("Change",  ExportService.fmtChange(stats.totalChange, unit: unit),
                              color: stats.totalChange < 0 ? .green : stats.totalChange > 0 ? .red : .secondary)
                    if let days = stats.daysToGoal {
                        Divider().frame(height: 28)
                        stripPill("Days to Goal", "\(days)", color: appState.effectiveAccentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    func stripPill(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 44))
                .foregroundStyle(appState.effectiveAccentColor.opacity(0.6))
            Text("Add at least one entry to enable exports.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Feedback Banner

    var feedbackBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(feedbackMessage)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    // MARK: - Export Actions

    private var defaultOutputDir: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = downloads.appendingPathComponent("WeightTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveExport(_ fmt: ExportFmt) {
        guard !entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultOutputDir

        switch fmt {
        case .csv:
            panel.nameFieldStringValue = "WeightTracker.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? ExportService.exportCSV(entries: entries, unit: unit)
                .write(to: url, atomically: true, encoding: .utf8)
            flash("CSV saved — \(url.lastPathComponent)")

        case .md:
            panel.nameFieldStringValue = "WeightTracker.md"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? ExportService.exportMarkdown(entries: entries, unit: unit,
                                              stats: appState.stats, username: appState.settings.username)
                .write(to: url, atomically: true, encoding: .utf8)
            flash("Markdown saved — \(url.lastPathComponent)")

        case .xlsx:
            panel.nameFieldStringValue = "WeightTracker.xlsx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            ExportService.exportXLSX(entries: entries, unit: unit).map { try? $0.write(to: url) }
            flash("XLSX saved — \(url.lastPathComponent)")

        case .docx:
            panel.nameFieldStringValue = "WeightTracker.docx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            ExportService.exportDOCX(entries: entries, unit: unit,
                                     stats: appState.stats, username: appState.settings.username)
                .map { try? $0.write(to: url) }
            flash("DOCX saved — \(url.lastPathComponent)")

        case .pdf:
            panel.nameFieldStringValue = "WeightTracker Report.pdf"
            panel.allowedContentTypes = [.pdf]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let data = ExportService.exportPDFReport(
                    entries: entries, stats: appState.stats,
                    unit: unit, username: appState.settings.username, chartImage: nil
                )
                try? data.write(to: url)
                flash("PDF saved — \(url.lastPathComponent)")
            }
        }
    }

    func printReport() {
        Task { @MainActor in
            let data = ExportService.exportPDFReport(
                entries: entries, stats: appState.stats,
                unit: unit, username: appState.settings.username, chartImage: nil
            )
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("WeightTracker-Print-\(UUID().uuidString).pdf")
            try? data.write(to: tmp)
            NSWorkspace.shared.open(tmp)
        }
    }

    private func flash(_ message: String) {
        feedbackMessage = message
        isFeedbackVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isFeedbackVisible = false
        }
    }
}

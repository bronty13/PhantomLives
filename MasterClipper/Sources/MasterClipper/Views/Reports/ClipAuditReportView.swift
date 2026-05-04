import SwiftUI

/// Bulk audit report. Lists every non-archived clip with its open audit
/// issues. Filter chip to show only failing clips. Click a row to jump into
/// the editor with the clip pre-selected so the user can fix and re-audit
/// without re-running the report.
struct ClipAuditReportView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rows: [ClipAuditService.Result] = []
    @State private var hideClean: Bool = true

    private var filteredRows: [ClipAuditService.Result] {
        hideClean ? rows.filter { !$0.ok } : rows
    }

    private var failingCount: Int { rows.filter { !$0.ok }.count }
    private var cleanCount: Int   { rows.filter(\.ok).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .onAppear { reload() }
        .onChange(of: appState.clips.count) { _, _ in reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clip audit")
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Label("\(failingCount) failing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(failingCount > 0 ? .orange : .secondary)
                Label("\(cleanCount) clean", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Toggle("Hide clean", isOn: $hideClean)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Re-run") { reload() }
            }
            .font(.callout)

            Text("Per-clip checklist: clip ID · persona · title · refined description · categories · content date · go-live date.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }

    @ViewBuilder
    private var list: some View {
        if filteredRows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.green)
                Text(hideClean
                     ? "No clips with open audit issues."
                     : "No clips to audit.")
                    .font(.headline)
                if hideClean && cleanCount > 0 {
                    Text("\(cleanCount) clean clip\(cleanCount == 1 ? "" : "s") hidden — toggle \"Hide clean\" to show them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRows, id: \.clipId) { row in
                        rowCard(row)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    private func rowCard(_ row: ClipAuditService.Result) -> some View {
        let color: Color = row.ok ? .green : .orange
        let titleText = row.title.isEmpty ? "Untitled" : row.title
        return Button {
            appState.focusedClipId = row.clipId
            appState.selectedSection = .clips
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if row.ok {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if !row.personaCode.isEmpty {
                        PersonaPill(code: row.personaCode)
                    }
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(row.title.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text(row.clipId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if !row.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(row.issues) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: issue.systemImage)
                                    .font(.caption).foregroundStyle(.orange)
                                Text(issue.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 28)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open this clip to fix the issues")
    }

    private func reload() {
        rows = ClipAuditService.auditAll(appState: appState)
    }
}

import SwiftUI
import AppKit

/// Editing-stage workflow for a single clip. Designed to chain off the
/// New Clip workflow ("Save & Continue to Editing →") but also reachable on
/// demand from the Clips toolbar for any existing clip.
///
/// Surfaces the file-audit summary (read-only, with a one-click hand-off to
/// the existing `FileAuditSheet` for the action pills) and a notes textarea
/// whose contents are appended to `clip.notes` with an `[Editing YYYY-MM-DD]`
/// marker. Mirrors the convention already used by the posting workflow
/// (`[Posted <site> YYYY-MM-DD]`) and the new-clip workflow (`[New clip
/// YYYY-MM-DD]`) so the editor's main Notes timeline reads as one chronology.
struct EditingWorkflowView: View {
    @EnvironmentObject private var appState: AppState

    let clipId: String
    let onClose: () -> Void

    @State private var clip: Clip?
    @State private var auditResult: FileAuditService.Result?
    @State private var notesDraft: String = ""
    @State private var saveError: String?
    @State private var saveSuccess: String?
    @State private var showingAuditSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sectionAudit
                    sectionNotes
                }
                .padding(20)
            }
            Divider()
            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 720, minHeight: 620)
        .onAppear(perform: loadClip)
        .sheet(isPresented: $showingAuditSheet) {
            if let live = clip {
                FileAuditSheet(clip: live) { _ in
                    // After the audit sheet's actions (rename / push / hash /
                    // capture), re-pull the clip and re-run the local audit
                    // so the inline summary reflects the changes.
                    refresh()
                }
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Editing Workflow", systemImage: "wand.and.stars")
                .font(.title2.weight(.semibold))
            if let c = clip {
                HStack(spacing: 10) {
                    ClipIDLabel(id: c.id, style: .body)
                    Text(c.title.isEmpty ? "Untitled" : c.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    PersonaPill(code: c.personaCode)
                    statusBadge(c.statusEnum)
                    Spacer()
                }
            }
            Text("Run the file audit, then jot any editing notes you want stitched into the clip's Notes timeline.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: ClipStatus) -> some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.tertiary, in: Capsule())
    }

    // MARK: - Audit summary

    private var sectionAudit: some View {
        section("File audit", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 10) {
                if let result = auditResult {
                    HStack(spacing: 14) {
                        Label("\(result.okCount) OK", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        if result.warnCount > 0 {
                            Label("\(result.warnCount) warning", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if result.missingCount > 0 {
                            Label("\(result.missingCount) missing", systemImage: "questionmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Button {
                            refresh()
                        } label: {
                            Label("Re-run", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showingAuditSheet = true
                        } label: {
                            Label("Open full audit…", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.caption)

                    Divider()

                    ForEach(result.allChecks) { check in
                        auditRow(check)
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Auditing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func auditRow(_ check: FileAuditService.Check) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: check.status))
                .foregroundStyle(color(for: check.status))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(.callout.weight(.medium))
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let size = check.sizeFormatted {
                Text(size)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconName(for status: FileAuditService.CheckStatus) -> String {
        switch status {
        case .ok:      return "checkmark.circle.fill"
        case .warn:    return "exclamationmark.triangle.fill"
        case .missing: return "questionmark.circle.fill"
        case .na:      return "minus.circle"
        }
    }

    private func color(for status: FileAuditService.CheckStatus) -> Color {
        switch status {
        case .ok:      return .green
        case .warn:    return .orange
        case .missing: return .red
        case .na:      return .secondary
        }
    }

    // MARK: - Notes

    private var sectionNotes: some View {
        section("Editing notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved as `[Editing YYYY-MM-DD] <text>` and appended to clip notes. Sits in the same timeline as `[New clip …]` and `[Posted …]` markers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $notesDraft)
                    .font(.body)
                    .frame(minHeight: 110, maxHeight: 240)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                if let c = clip,
                   !c.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("Existing notes (\(c.notes.split(separator: "\n").count) line\(c.notes.split(separator: "\n").count == 1 ? "" : "s"))") {
                        Text(c.notes)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption).lineLimit(2)
            } else if let saveSuccess {
                Label(saveSuccess, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            }
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button {
                appendNotesAndClose()
            } label: {
                Label("Save notes & close", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && saveSuccess == nil)
        }
    }

    // MARK: - Logic

    private func loadClip() {
        do {
            let live = try DatabaseService.shared.fetchClip(id: clipId)
            clip = live
            if let live {
                auditResult = FileAuditService.audit(clip: live, settings: appState.settings)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func refresh() {
        loadClip()
    }

    private func appendNotesAndClose() {
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Treat empty save as a plain close — same as Cancel/Close.
            onClose()
            return
        }
        guard var live = clip else {
            saveError = "Clip not loaded."
            return
        }
        let marker = "[Editing \(DatabaseService.isoDate(Date()))] \(trimmed)"
        let existing = live.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        live.notes = existing.isEmpty ? marker : live.notes + "\n" + marker
        do {
            try appState.updateClip(live)
            clip = try DatabaseService.shared.fetchClip(id: live.id) ?? live
            saveSuccess = "Note appended to clip.notes."
            saveError = nil
            notesDraft = ""
            // Brief delay so the user sees the green confirmation before the
            // sheet dismisses; matches the sub-second flashes used elsewhere.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                onClose()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Layout helper

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

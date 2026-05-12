import SwiftUI
import AppKit
import MasterClipperCore

/// Three-stage wizard that ingests the **ClipperInfo** companion-app
/// payload, diffs it against the live clips, and lets the user accept
/// or reject every individual change before anything is written.
///
/// Reset via `.creatorImportRequested` notification (posted from the
/// File menu and from the *Information Needed* report's quick-link).
struct ClipperInfoImportWizardView: View {
    @EnvironmentObject private var appState: AppState

    enum Stage: Hashable { case paste, review, done }

    @State private var stage: Stage = .paste
    @State private var pasted: String = ""
    @State private var parsed: [ClipperInfoImportService.ParsedEntry] = []
    @State private var diffs: [ClipperInfoImportService.ClipDiff] = []
    @State private var parseError: String?
    @State private var applyResult: ClipperInfoImportService.ApplyResult?

    var body: some View {
        EdPageShell(
            eyebrow: "Section · Creator Import",
            headline: "Bring the edits back in.",
            emphasized: "back",
            deck: "Paste the ClipperInfo payload, review every change, then apply.",
            trailing: AnyView(
                Button { reset() } label: { Text("RESET") }
                    .buttonStyle(EdGhostButtonStyle())
            )
        ) {
            VStack(spacing: 0) {
                stepIndicator
                EdHairline(color: EdColor.ink(0.18))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .creatorImportRequested)) { _ in
            reset()
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 14) {
            stepLabel("1. Paste",   active: stage == .paste)
            chevron
            stepLabel("2. Review",  active: stage == .review,
                      enabled: !diffs.isEmpty)
            chevron
            stepLabel("3. Done",    active: stage == .done,
                      enabled: applyResult != nil)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(EdColor.bone)
    }

    @ViewBuilder
    private func stepLabel(_ title: String, active: Bool, enabled: Bool = true) -> some View {
        let foreground: Color = active ? EdColor.ink : (enabled ? EdColor.ink(0.6) : EdColor.ink(0.35))
        Text(title.uppercased())
            .font(EdFont.mono(11, weight: active ? .semibold : .regular))
            .tracking(0.84)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? EdColor.acid : Color.clear)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(EdFont.mono(11))
            .foregroundStyle(EdColor.ink(0.35))
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .paste:  pasteStep
        case .review: reviewStep
        case .done:   doneStep
        }
    }

    // MARK: - Step 1 — Paste

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste the ClipperInfo output")
                .font(.title3.weight(.semibold))
            Text("Paste the block the creator copied out of ClipperInfo (the same shape as **Reports → Information Needed → Copy for creator**). One block per clip, separated by blank lines.")
                .font(.callout).foregroundStyle(.secondary)

            TextEditor(text: $pasted)
                .font(.body.monospaced())
                .frame(minHeight: 240)
                .border(.separator)

            HStack(spacing: 12) {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        pasted = s
                    }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                }

                if let parseError {
                    Text(parseError).font(.caption).foregroundStyle(.red)
                }
                Spacer()

                Button("Parse →") { runParse() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func runParse() {
        parseError = nil
        let entries = ClipperInfoImportService.parse(pasted)
        if entries.isEmpty {
            parseError = "Couldn't find any valid clip blocks. Each block must start with `YYYY-MM-DD-##### - Title [Persona]`."
            return
        }
        parsed = entries
        diffs  = ClipperInfoImportService.diff(entries: entries, appState: appState)
        stage  = .review
    }

    // MARK: - Step 2 — Review

    private var reviewStep: some View {
        VStack(spacing: 0) {
            reviewHeader
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(diffs.indices, id: \.self) { idx in
                        diffCard(idx: idx)
                    }
                }
                .padding(16)
            }
            Divider()
            reviewFooter
        }
    }

    private var reviewHeader: some View {
        let totalChanges = diffs.reduce(0) { $0 + $1.changes.count }
        let touchedClips = diffs.filter(\.hasChanges).count
        let unknown      = diffs.filter(\.unknown).count
        let unchanged    = diffs.filter { !$0.hasChanges && !$0.unknown }.count

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review changes — \(diffs.count) entries parsed")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 10) {
                    summaryPill("\(touchedClips) with changes", color: .orange)
                    summaryPill("\(totalChanges) total fields", color: .blue)
                    if unchanged > 0 {
                        summaryPill("\(unchanged) unchanged", color: .secondary)
                    }
                    if unknown > 0 {
                        summaryPill("\(unknown) unknown ID", color: .red)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Accept all changes")  { setAllAccepted(true) }
                Button("Reject all changes")  { setAllAccepted(false) }
            } label: {
                Label("Bulk", systemImage: "checklist")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
        }
        .padding(12)
        .background(EdColor.bone)
    }

    private func summaryPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var reviewFooter: some View {
        let accepted = diffs.reduce(0) { $0 + $1.acceptedChangeCount }
        return HStack {
            Button("Back") { stage = .paste }
            Spacer()
            Text("\(accepted) change\(accepted == 1 ? "" : "s") accepted")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button("Apply →") { runApply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(accepted == 0)
        }
        .padding(12)
        .background(EdColor.bone)
    }

    // MARK: - Diff card

    @ViewBuilder
    private func diffCard(idx: Int) -> some View {
        let diff = diffs[idx]

        VStack(alignment: .leading, spacing: 10) {
            // Header — ID, title, persona, status pill, per-card bulk buttons
            HStack(spacing: 8) {
                ClipIDLabel(id: diff.id, style: .caption)
                    .frame(width: 130, alignment: .leading)
                Text("—").foregroundStyle(.tertiary)
                Text(diff.clip?.title.isEmpty == false
                     ? diff.clip!.title
                     : (diff.parsed.title.isEmpty ? "Untitled" : diff.parsed.title))
                    .font(.headline).lineLimit(1)
                personaPill(diff.clip?.personaCode ?? diff.parsed.personaCode)
                Spacer()
                statusPill(for: diff)
                if diff.hasChanges {
                    Menu {
                        Button("Accept all in this clip")  { setAccepted(idx: idx, value: true) }
                        Button("Reject all in this clip")  { setAccepted(idx: idx, value: false) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }

            if diff.unknown {
                Label("This ID doesn't match any clip in MasterClipper — it will be skipped on Apply.",
                      systemImage: "questionmark.diamond.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if diff.changes.isEmpty {
                Label("No changes — this clip already matches the payload.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(diff.changes.enumerated()), id: \.element.id) { (cIdx, change) in
                        changeRow(diffIdx: idx, changeIdx: cIdx, change: change)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            diff.unknown ? Color.red.opacity(0.6) : Color.gray.opacity(0.25),
            lineWidth: 1
        ))
        .opacity(diff.unknown ? 0.75 : 1)
    }

    @ViewBuilder
    private func changeRow(diffIdx: Int, changeIdx: Int, change: ClipperInfoImportService.FieldChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { diffs[diffIdx].changes[changeIdx].accepted },
                set: { diffs[diffIdx].changes[changeIdx].accepted = $0 }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(label(for: change.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            changeBody(change)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(change.accepted ? 1 : 0.4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(rowTint(for: change.kind, accepted: change.accepted),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func changeBody(_ change: ClipperInfoImportService.FieldChange) -> some View {
        switch change.kind {
        case .categoryAdd(let name):
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                Text(name).font(.callout.monospaced())
                Text("(add)").font(.caption2).foregroundStyle(.tertiary)
            }
        case .categoryRemove(let name):
            HStack(spacing: 6) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                Text(name).font(.callout.monospaced()).strikethrough()
                Text("(remove)").font(.caption2).foregroundStyle(.tertiary)
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                valueChip(change.oldValue, kind: .old)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                valueChip(change.newValue, kind: .new)
            }
        }
    }

    private enum ChipKind { case old, new }
    private func valueChip(_ text: String, kind: ChipKind) -> some View {
        let display = text.isEmpty ? "(empty)" : text
        let isEmpty = text.isEmpty
        return Text(display)
            .font(.callout)
            .italic(isEmpty)
            .foregroundStyle(isEmpty ? .tertiary : (kind == .new ? .primary : .secondary))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                (kind == .new ? Color.green : Color.orange).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke((kind == .new ? Color.green : Color.orange).opacity(0.45),
                            lineWidth: 1)
            )
    }

    private func label(for kind: ClipperInfoImportService.FieldChange.Kind) -> String {
        switch kind {
        case .title:           return "Title"
        case .persona:         return "Persona"
        case .description:     return "Description"
        case .goLiveDate:      return "Go-live"
        case .categoryAdd:     return "Category"
        case .categoryRemove:  return "Category"
        }
    }

    private func rowTint(for kind: ClipperInfoImportService.FieldChange.Kind, accepted: Bool) -> Color {
        guard accepted else { return Color.clear }
        switch kind {
        case .categoryAdd:    return Color.green.opacity(0.06)
        case .categoryRemove: return Color.red.opacity(0.06)
        default:              return Color.orange.opacity(0.05)
        }
    }

    private func personaPill(_ code: String) -> some View {
        Text(code)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(appState.color(forPersona: code).opacity(0.2), in: Capsule())
            .foregroundStyle(appState.color(forPersona: code))
    }

    @ViewBuilder
    private func statusPill(for diff: ClipperInfoImportService.ClipDiff) -> some View {
        if diff.unknown {
            pill("UNKNOWN", color: .red)
        } else if diff.changes.isEmpty {
            pill("NO CHANGE", color: .green)
        } else {
            pill("\(diff.changes.count) CHG", color: .orange)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospaced().weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Step 3 — Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.green)
            Text("Creator import complete")
                .font(.title.weight(.semibold))

            if let r = applyResult {
                VStack(spacing: 4) {
                    Text("\(r.clipsTouched) clip\(r.clipsTouched == 1 ? "" : "s") updated")
                    Text("\(r.fieldChangesApplied) field change\(r.fieldChangesApplied == 1 ? "" : "s") applied")
                        .foregroundStyle(.secondary)
                    if r.categoriesAdded + r.categoriesRemoved > 0 {
                        Text("Categories: +\(r.categoriesAdded) / −\(r.categoriesRemoved)\(r.categoriesCreated > 0 ? "  (\(r.categoriesCreated) new)" : "")")
                            .foregroundStyle(.secondary)
                    }
                    if r.unknownIdsSkipped > 0 {
                        Text("\(r.unknownIdsSkipped) unknown ID\(r.unknownIdsSkipped == 1 ? "" : "s") skipped")
                            .foregroundStyle(.red)
                    }
                    if !r.errors.isEmpty {
                        DisclosureGroup("\(r.errors.count) error\(r.errors.count == 1 ? "" : "s")") {
                            ScrollView {
                                ForEach(r.errors, id: \.self) { e in
                                    Text(e).font(.caption.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .padding()
            }

            Button("Start over") { reset() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Actions

    private func setAllAccepted(_ value: Bool) {
        for i in diffs.indices {
            for j in diffs[i].changes.indices {
                diffs[i].changes[j].accepted = value
            }
        }
    }

    private func setAccepted(idx: Int, value: Bool) {
        for j in diffs[idx].changes.indices {
            diffs[idx].changes[j].accepted = value
        }
    }

    private func runApply() {
        let result = ClipperInfoImportService.apply(diffs: diffs, appState: appState)
        applyResult = result
        stage = .done
    }

    private func reset() {
        stage = .paste
        pasted = ""
        parsed = []
        diffs = []
        parseError = nil
        applyResult = nil
    }
}

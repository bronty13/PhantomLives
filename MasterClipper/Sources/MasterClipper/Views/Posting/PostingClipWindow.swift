import SwiftUI
import AppKit

/// Per-clip posting view rendered while running a posting batch. The
/// header is a persona-coloured banner with everything the user needs at
/// a glance — title, ID, production path (with Reveal + open-in-editor),
/// thumbnail filename, and file hashes — all read-only. Below that are
/// the description (read-only), categorisation (editable, persisted on
/// every change), the schedule strip (length / price / content / go-live
/// dates, read-only), and a posting-notes textarea that lands on the
/// posting record when the user marks it posted.
///
/// "Mark posted" updates the clip_postings row; "Posted & next" advances
/// to the next clip in the batch.
struct PostingClipWindow: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip
    let target: PostingTarget
    let onMarkPosted: (Clip) -> Void
    let onClose: () -> Void
    let onAdvance: (Clip) -> Void

    @State private var copyToast: String?
    @State private var notes: String = ""
    @State private var selectedCategoryIds: [Int64] = []
    @State private var initialCategoryIds: [Int64] = []
    /// Editable USD price. Initialised from `clip.priceCents`, persisted
    /// on `.onSubmit`, on `.onDisappear`, and right before Mark posted.
    @State private var priceDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(14)
                .background(personaGradient)
                .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    descriptionBlock
                    categorizationBlock
                    scheduleStrip
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Divider()

            postingNotesBlock
                .padding(.horizontal, 14)

            actionBar
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .overlay(alignment: .top) {
            if let toast = copyToast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            loadCategories()
            loadPrice()
        }
        .onChange(of: clip.id) { _, _ in
            // Defensive — even though PostingBatchView gives us a
            // per-clip `.id(...)`, re-seed everything when the clip
            // identity changes so values can never drift across the
            // wrong clip if the parent ever reuses the view.
            savePriceIfChanged()        // flush previous clip's edits
            loadCategories()
            loadPrice()
            notes = ""
        }
        .onDisappear {
            // Make sure any in-flight price edit lands even if the user
            // navigates away without hitting Enter or Mark posted.
            savePriceIfChanged()
        }
        .onChange(of: selectedCategoryIds) { _, new in
            // Persist immediately — no separate Save step in the
            // posting flow; the user expects category edits to stick
            // when they click Mark posted / Posted & next.
            persistCategoriesIfChanged(new)
        }
    }

    // MARK: - Header banner

    private var personaGradient: LinearGradient {
        LinearGradient(
            colors: [
                personaColor.opacity(0.42),
                personaColor.opacity(0.14),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var personaColor: Color { appState.color(forPersona: clip.personaCode) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                personaBadge
                Image(systemName: "arrow.right")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(target.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openInEditor()
                } label: {
                    Label("Open clip in editor", systemImage: "pencil.circle")
                }
                .help("Close this posting view and jump into the clip's editor.")
                Button("Back to queue", action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(clip.title.isEmpty ? "Untitled clip" : clip.title)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Button {
                        copy(clip.title, fieldName: "Title")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy title to clipboard")
                    .disabled(clip.title.isEmpty)
                }
                ClipIDLabel(id: clip.id, style: .captionTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                pathRow
                if let thumb = clip.thumbnailFilename, !thumb.isEmpty {
                    metaRow(icon: "photo", label: "Thumbnail", value: thumb)
                }
                hashRow(label: "MD5",     digest: clip.mp4Md5)
                hashRow(label: "SHA-1",   digest: clip.mp4Sha1)
                hashRow(label: "SHA-256", digest: clip.mp4Sha256)
            }
        }
    }

    /// Larger persona pill with the persona's display name spelled out so
    /// the operator can see at a glance whose flow they're posting under.
    private var personaBadge: some View {
        let name = appState.persona(forCode: clip.personaCode)?.displayName ?? clip.personaCode
        return HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.white.opacity(0.95))
            Text(clip.personaCode)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [personaColor, personaColor.opacity(0.75)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: Capsule()
        )
        .shadow(color: personaColor.opacity(0.35), radius: 3, x: 0, y: 2)
    }

    private var pathRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text("Production:")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(clip.productionFolder ?? "—")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(clip.productionFolder ?? "")
            Button {
                revealProduction()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled((clip.productionFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Open the Production folder in Finder.")
            Spacer()
        }
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text("\(label):")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                copy(value, fieldName: label)
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy \(label) to clipboard.")
        }
    }

    private func hashRow(label: String, digest: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "function").foregroundStyle(.secondary)
            Text("\(label):")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            if digest.isEmpty {
                Text("(not yet computed)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            } else {
                Text(digest)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(digest)
                Spacer()
                Button {
                    copy(digest, fieldName: label)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Description (read-only, refined)

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Description (refined)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(refinedOrFallbackDescription, fieldName: "Description")
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(refinedOrFallbackDescription.isEmpty)
            }
            ScrollView {
                Text(refinedOrFallbackDescription.isEmpty ? "—" : refinedOrFallbackDescription)
                    .font(.body)
                    .foregroundStyle(refinedOrFallbackDescription.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 80, maxHeight: 200)
            .background(.background.secondary)
            .border(.separator)
        }
    }

    // MARK: - Categorization (editable)

    private var categorizationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Categories (edits save immediately)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(categoryString, fieldName: "Categories")
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(categoryString.isEmpty)
            }
            CategoryChipPicker(selectedIds: $selectedCategoryIds)
        }
    }

    // MARK: - Schedule strip (read-only)

    private var scheduleStrip: some View {
        HStack(spacing: 18) {
            schedulePair(label: "Length",
                         value: DurationFormatter.format(clip.lengthSeconds))
            priceField
            schedulePair(label: "Content date",
                         value: clip.contentDate ?? "—")
            schedulePair(label: "Go-Live date",
                         value: clip.goLiveDate ?? "—")
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func schedulePair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
        }
    }

    /// Editable USD price field. Posting time is when prices get set per
    /// site, so this is the natural place to update it. Saves on submit
    /// (Enter), on Mark posted, and on view dismissal.
    private var priceField: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Price")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text("$")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                TextField("", text: $priceDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                    .frame(width: 70)
                    .onSubmit { savePriceIfChanged() }
                    .help("USD price for this clip on \(target.label). Saves on Enter, on Mark posted, or when you leave this window.")
            }
        }
    }

    // MARK: - Posting notes

    private var postingNotesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Posting notes (saved with the posting record)")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .frame(minHeight: 50, maxHeight: 80)
                .border(.separator)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            Button {
                copyAll()
            } label: {
                Label("Copy all (markdown)", systemImage: "doc.on.doc")
            }
            if !canMarkPosted {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Set the price before posting (use 0 for free).")
                        .font(.caption).foregroundStyle(.orange)
                }
                .padding(.leading, 8)
            }
            Spacer()
            Button {
                onAdvance(clip)
            } label: {
                Label("Skip for now", systemImage: "forward")
            }
            .help("Don't mark this clip as posted — just move to the next. The clip stays in the queue so you can come back to it later.")
            Button("Mark posted") {
                savePriceIfChanged()
                postWithNotes()
                onMarkPosted(clip)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!canMarkPosted)
            Button("Posted & next") {
                savePriceIfChanged()
                postWithNotes()
                onMarkPosted(clip)
                onAdvance(clip)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!canMarkPosted)
        }
    }

    /// Mark posted is allowed only when the price is set (zero is OK).
    /// Reads from the live `priceDraft` so the user can flip the gate
    /// just by typing — no save required to enable the buttons.
    private var canMarkPosted: Bool {
        let cleaned = priceDraft
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return false }
        guard let dollars = Double(cleaned), dollars >= 0 else { return false }
        return true
    }

    // MARK: - Persistence

    private func postWithNotes() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the user typed posting notes, append them to the
        // clip_postings row AND mirror them to clip.notes — that way
        // the per-clip Notes textarea in the editor surfaces the
        // posting context the user added at posting time, all in one
        // place, without us having to add a separate UI to view the
        // per-site notes column.
        guard !trimmed.isEmpty, let siteId = target.site.id else { return }
        do {
            let now = DatabaseService.isoNow()
            let dateStr = DatabaseService.isoDate(Date())
            let existing = (try? DatabaseService.shared.fetchPostings(forClip: clip.id))?
                .first(where: { $0.siteId == siteId })
            let row = ClipPosting(
                clipId: clip.id,
                siteId: siteId,
                postedDate: dateStr,
                status: PostingStatus.posted.rawValue,
                notes: existing?.notes.isEmpty == false ? existing!.notes + "\n" + trimmed : trimmed,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try DatabaseService.shared.upsertPosting(row)

            // Mirror into clip.notes — tagged with site code + posted
            // date so the user can see exactly which posting added
            // each note.
            if var live = try DatabaseService.shared.fetchClip(id: clip.id) {
                let marker = "[Posted \(target.site.code) \(dateStr)] \(trimmed)"
                live.notes = live.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? marker
                    : live.notes + "\n" + marker
                try appState.updateClip(live)
            }
        } catch {
            // Surfaces via reload in caller; nothing extra to do.
        }
    }

    private func loadCategories() {
        let ids = (try? DatabaseService.shared.categoryIds(forClip: clip.id)) ?? []
        selectedCategoryIds = ids
        initialCategoryIds = ids
    }

    private func loadPrice() {
        priceDraft = clip.priceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
    }

    /// Parse `priceDraft` (USD, optional `$` prefix and commas) into
    /// integer cents, persist to the clip via `appState.updateClip` if
    /// it differs from the current stored value. Empty string clears
    /// the price back to nil.
    private func savePriceIfChanged() {
        let cleaned = priceDraft
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let newCents: Int? = {
            guard !cleaned.isEmpty else { return nil }
            guard let dollars = Double(cleaned) else { return nil }
            return Int((dollars * 100).rounded())
        }()
        guard newCents != clip.priceCents else { return }
        do {
            if var live = try DatabaseService.shared.fetchClip(id: clip.id) {
                live.priceCents = newCents
                try appState.updateClip(live)
            }
        } catch {
            // Silent — the next reload will surface persistence issues.
        }
    }

    private func persistCategoriesIfChanged(_ new: [Int64]) {
        guard new != initialCategoryIds else { return }
        do {
            try appState.setClipCategories(clipId: clip.id, categoryIds: new)
            initialCategoryIds = new
        } catch {
            // Silent — the next reload will surface any persistence issue.
        }
    }

    private func revealProduction() {
        guard let p = clip.productionFolder?.trimmingCharacters(in: .whitespaces),
              !p.isEmpty else { return }
        let expanded = (p as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Fall back to the deepest existing parent so the user can
            // see where the missing folder *would* live.
            PathDefaultsService.revealInFinder(p)
        }
    }

    private func openInEditor() {
        appState.focusedClipId = clip.id
        appState.selectedSection = .clips
        onClose()
    }

    // MARK: - Helpers

    private var categoryString: String {
        selectedCategoryIds.compactMap { cid in
            appState.categories.first(where: { $0.id == cid })?.name
        }.joined(separator: ", ")
    }

    private var refinedOrFallbackDescription: String {
        clip.descriptionRefined.isEmpty ? clip.descriptionRaw : clip.descriptionRefined
    }

    private func copy(_ value: String, fieldName: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast("Copied \(fieldName)")
    }

    private func copyAll() {
        var md = "# \(clip.title.isEmpty ? "Untitled" : clip.title)\n\n"
        if !categoryString.isEmpty { md += "**Categories:** \(categoryString)\n" }
        md += "**Length:** \(DurationFormatter.format(clip.lengthSeconds))\n"
        if let cents = clip.priceCents { md += String(format: "**Price:** $%.2f\n", Double(cents) / 100) }
        md += "\n## Description\n\n\(refinedOrFallbackDescription)\n"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        showToast("Copied full clip as Markdown")
    }

    private func showToast(_ s: String) {
        withAnimation(.easeOut(duration: 0.15)) { copyToast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) { copyToast = nil }
        }
    }
}

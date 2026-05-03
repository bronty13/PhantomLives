import SwiftUI

/// Floating window-style sheet that surfaces every relevant clip field with a
/// per-field "Copy" button so the user can paste into the upload form on the
/// site of the day. "Mark posted" updates the clip_postings row; "Posted &
/// next" advances to the next clip in the batch.
struct PostingClipWindow: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip
    let target: PostingTarget
    let onMarkPosted: (Clip) -> Void
    let onClose: () -> Void
    let onAdvance: (Clip) -> Void

    @State private var copyToast: String?
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Title",            value: clip.title)
                    field("Categories",       value: categoryString)
                    field("Keywords",         value: clip.keywords)
                    field("Performers",       value: clip.performers)
                    field("Length",           value: DurationFormatter.format(clip.lengthSeconds))
                    field("Price",            value: clip.priceCents.map { String(format: "$%.2f", Double($0) / 100) } ?? "")
                    field("Content date",     value: clip.contentDate ?? "")
                    field("Go-Live date",     value: clip.goLiveDate ?? "")
                    field("Clip filename",    value: clip.clipFilename ?? "")
                    field("Thumbnail",        value: clip.thumbnailFilename ?? "")
                    field("Preview",          value: clip.previewFilename ?? "")
                    multilineField("Description (refined)", value: refinedOrFallbackDescription)
                    multilineField("Description (raw)",     value: clip.descriptionRaw)
                }
                .padding(.vertical, 6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Posting notes (saved with the posting record)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 50, maxHeight: 80)
                    .border(.separator)
            }

            actionBar
        }
        .padding(20)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Posting to \(target.label)")
                    .font(.callout).foregroundStyle(.secondary)
                Text(clip.title.isEmpty ? "Untitled clip" : clip.title)
                    .font(.title2.weight(.semibold))
                Text(clip.id)
                    .font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                copyAll()
            } label: {
                Label("Copy all (markdown)", systemImage: "doc.on.doc")
            }
            Button("Back to queue", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            Spacer()
            Button("Mark posted") {
                postWithNotes()
                onMarkPosted(clip)
            }
            .keyboardShortcut("s", modifiers: .command)
            Button("Posted & next") {
                postWithNotes()
                onMarkPosted(clip)
                onAdvance(clip)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
    }

    private func postWithNotes() {
        // If the user typed posting notes, append them to the clip_postings row.
        guard !notes.trimmingCharacters(in: .whitespaces).isEmpty,
              let siteId = target.site.id else { return }
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
                notes: existing?.notes.isEmpty == false ? existing!.notes + "\n" + notes : notes,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try DatabaseService.shared.upsertPosting(row)
        } catch {
            // Surfaces via reload in caller; nothing extra to do.
        }
    }

    // MARK: - Field rows

    private func field(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            Button {
                copy(value, fieldName: label)
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .disabled(value.isEmpty)
        }
    }

    private func multilineField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(value, fieldName: label)
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(value.isEmpty)
            }
            ScrollView {
                Text(value.isEmpty ? "—" : value)
                    .font(.body)
                    .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 60, maxHeight: 140)
            .background(.background.secondary)
            .border(.separator)
        }
    }

    // MARK: - Helpers

    private var categoryString: String {
        let ids = (try? DatabaseService.shared.categoryIds(forClip: clip.id)) ?? []
        return ids.compactMap { cid in appState.categories.first(where: { $0.id == cid })?.name }
            .joined(separator: ", ")
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
        if !clip.keywords.isEmpty  { md += "**Keywords:** \(clip.keywords)\n" }
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

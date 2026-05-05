import SwiftUI
import AppKit

/// Bulk-upload helper sheet — shows every pending clip in the current
/// posting batch in order with its ID, title, and the canonical
/// production filename (`<Title>.mp4`). Useful on sites that let you
/// upload multiple clips at once: the user can quickly see (and copy)
/// the file list to match against the OS file-picker.
///
/// Each row supports click-to-copy on every column. The bulk button at
/// the bottom copies a newline-delimited list in one of three flavours
/// (titles, filenames, or markdown rows).
struct PostingQueueListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: PostingTarget
    let clips: [Clip]

    @State private var copyToast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            listBody
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Posting queue — \(target.label)")
                    .font(.title3.weight(.semibold))
                Text("\(clips.count) clip\(clips.count == 1 ? "" : "s") pending. Click any cell to copy it; use the buttons at the bottom for bulk copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - List

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { idx, clip in
                    row(idx: idx, clip: clip)
                }
            }
            .padding(12)
        }
    }

    private func row(idx: Int, clip: Clip) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", idx + 1))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
            Text(clip.id)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Click to copy clip ID")
                .onTapGesture { copy(clip.id, label: "ID") }
            Text(clip.title.isEmpty ? "Untitled" : clip.title)
                .font(.body)
                .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help("Click to copy title")
                .onTapGesture { copy(clip.title, label: "Title") }
            Spacer()
            Text(productionFilename(for: clip))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Click to copy production filename")
                .onTapGesture { copy(productionFilename(for: clip), label: "Filename") }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Bulk copy:").font(.caption).foregroundStyle(.secondary)
            Button {
                copyAllTitles()
            } label: {
                Label("Titles", systemImage: "doc.on.doc")
            }
            Button {
                copyAllFilenames()
            } label: {
                Label("Filenames", systemImage: "doc.on.doc")
            }
            Button {
                copyAllMarkdown()
            } label: {
                Label("Markdown table", systemImage: "list.bullet.rectangle")
            }
            Spacer()
            Text("\(clips.count) row\(clips.count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func productionFilename(for clip: Clip) -> String {
        let safe = clip.title
            .replacingOccurrences(of: "/",  with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":",  with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "—" : safe + ".mp4"
    }

    private func copy(_ value: String, label: String) {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast("Copied \(label)")
    }

    private func copyAllTitles() {
        let body = clips
            .map { $0.title.isEmpty ? "Untitled" : $0.title }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        showToast("Copied \(clips.count) titles")
    }

    private func copyAllFilenames() {
        let body = clips
            .map { productionFilename(for: $0) }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        showToast("Copied \(clips.count) filenames")
    }

    private func copyAllMarkdown() {
        var md = "| # | ID | Title | Filename |\n|---:|---|---|---|\n"
        for (i, c) in clips.enumerated() {
            let title = (c.title.isEmpty ? "Untitled" : c.title)
                .replacingOccurrences(of: "|", with: "\\|")
            let file  = productionFilename(for: c)
                .replacingOccurrences(of: "|", with: "\\|")
            md += "| \(i + 1) | \(c.id) | \(title) | \(file) |\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        showToast("Copied markdown table")
    }

    private func showToast(_ s: String) {
        withAnimation(.easeOut(duration: 0.15)) { copyToast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) { copyToast = nil }
        }
    }
}

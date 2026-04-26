// ExportSheet.swift
// Modal sheet for exporting a single playlist (or all playlists) in the
// user's choice of format: Markdown, PDF, or JSON database backup.
// Triggered from the "Export" toolbar button in PlaylistDetailView.

import SwiftUI
import UniformTypeIdentifiers

/// Export format chooser sheet. Pass `playlist = nil` to export all playlists.
struct ExportSheet: View {
    let playlist: Playlist?
    @Environment(\.dismiss) var dismiss
    @State private var isExporting = false
    @State private var exportError: String?

    var title: String { playlist.map { "Export \"\($0.name)\"" } ?? "Export All Playlists" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.bold())

            Text("Choose an export format:")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ExportButton(
                    title: "Markdown (.md)",
                    subtitle: "Plain text, great for notes apps and version control",
                    systemImage: "doc.plaintext",
                    action: { exportMarkdown() }
                )
                ExportButton(
                    title: "PDF (.pdf)",
                    subtitle: "Formatted document, ready to share or print",
                    systemImage: "doc.richtext",
                    action: { exportPDF() }
                )
                ExportButton(
                    title: "JSON Database (.json)",
                    subtitle: "Full database export — playlists, tracks, and all your notes",
                    systemImage: "square.and.arrow.up",
                    action: { exportJSON() }
                )
            }

            if let error = exportError {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 440)
        .disabled(isExporting)
        .overlay { if isExporting { ProgressView() } }
    }

    // MARK: - Export actions

    private func exportMarkdown() {
        do {
            let content: String
            if let playlist {
                content = try ExportService.shared.exportPlaylistAsMarkdown(playlist)
            } else {
                content = try ExportService.shared.exportAllAsMarkdown()
            }
            let name = playlist.map { "\($0.name).md" } ?? "MusicJournal.md"
            save(data: Data(content.utf8), name: name, type: .plainText)
        } catch { exportError = error.localizedDescription }
    }

    private func exportPDF() {
        do {
            let data: Data
            if let playlist {
                data = try ExportService.shared.exportPlaylistAsPDF(playlist)
            } else {
                data = try ExportService.shared.exportAllAsPDF()
            }
            let name = playlist.map { "\($0.name).pdf" } ?? "MusicJournal.pdf"
            save(data: data, name: name, type: .pdf)
        } catch { exportError = error.localizedDescription }
    }

    private func exportJSON() {
        do {
            let data = try ExportService.shared.exportDatabaseAsJSON()
            save(data: data, name: "MusicJournal.json", type: .json)
        } catch { exportError = error.localizedDescription }
    }

    private func save(data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
        dismiss()
    }
}

// MARK: - ExportButton

/// Styled button row used inside ExportSheet.
struct ExportButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

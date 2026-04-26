// ExportService.swift
// Generates Markdown, PDF, and JSON exports from the local database.
//
// PDF rendering uses CoreText directly (no WebKit dependency) with a simple
// line-by-line Markdown parser that handles #/##/### headings and body text.
// The PDF is paginated A4 (595 × 842 pt) with 56 pt margins on all sides.

import Foundation
import PDFKit
import AppKit

/// Singleton that reads from DatabaseService and produces formatted exports.
final class ExportService {
    static let shared = ExportService()
    private let db = DatabaseService.shared

    // MARK: - Markdown export

    /// Exports a single playlist and all its tracks as a Markdown document.
    func exportPlaylistAsMarkdown(_ playlist: Playlist) throws -> String {
        let tracks = try db.fetchTracks(forPlaylist: playlist.spotifyId)
        var md = ""
        md += "# \(playlist.userTitle.isEmpty ? playlist.name : playlist.userTitle)\n\n"
        if !playlist.description.isEmpty {
            md += "> \(playlist.description)\n\n"
        }
        md += "**Owner:** \(playlist.ownerName)  \n"
        md += "**Tracks:** \(playlist.trackCount)  \n"
        md += "**Synced:** \(playlist.syncedAt.formatted(date: .abbreviated, time: .omitted))  \n\n"
        if !playlist.userNotes.isEmpty {
            md += "## My Notes\n\n\(playlist.userNotes)\n\n"
        }
        md += "---\n\n## Tracks\n\n"
        for (i, track) in tracks.enumerated() {
            let rating = track.userRating.map { String(repeating: "★", count: $0) } ?? ""
            md += "### \(i + 1). \(track.name) \(rating)\n\n"
            md += "**Artist:** \(track.artistNames)  \n"
            md += "**Album:** \(track.albumName)  \n"
            md += "**Duration:** \(track.durationFormatted)  \n\n"
            if !track.userNotes.isEmpty {
                md += "> \(track.userNotes)\n\n"
            }
        }
        md += "\n---\n*Exported from Music Journal \(AppVersion.display) on \(Date().formatted())*\n"
        return md
    }

    /// Exports every playlist in the database as a single Markdown document.
    func exportAllAsMarkdown() throws -> String {
        let playlists = try db.fetchAllPlaylists()
        var md = "# Music Journal\n\n"
        md += "*Exported \(Date().formatted())*\n\n---\n\n"
        for playlist in playlists {
            md += try exportPlaylistAsMarkdown(playlist)
            md += "\n\n---\n\n"
        }
        return md
    }

    // MARK: - PDF export

    /// Exports a single playlist as a PDF document.
    func exportPlaylistAsPDF(_ playlist: Playlist) throws -> Data {
        let md = try exportPlaylistAsMarkdown(playlist)
        return renderMarkdownToPDF(text: md, title: playlist.userTitle.isEmpty ? playlist.name : playlist.userTitle)
    }

    /// Exports all playlists as a single PDF document.
    func exportAllAsPDF() throws -> Data {
        let md = try exportAllAsMarkdown()
        return renderMarkdownToPDF(text: md, title: "Music Journal")
    }

    // MARK: - JSON export / import

    /// Serialises the entire database to pretty-printed JSON with ISO-8601 dates.
    func exportDatabaseAsJSON() throws -> Data {
        let export = try db.exportDatabase()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Replaces all local data with the contents of a JSON database export.
    func importDatabaseFromJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(DatabaseExport.self, from: data)
        try db.importDatabase(export)
    }

    // MARK: - PDF rendering

    /// Renders a Markdown string to paginated A4 PDF using CoreText.
    ///
    /// Only #, ##, and ### heading levels are styled; all other lines use
    /// the body font. Block-quote syntax (>) is passed through as plain text.
    private func renderMarkdownToPDF(text: String, title: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 points
        let margin: CGFloat = 56

        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData)!
        var mediaBox = pageRect
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]
        let h1Attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.black,
        ]
        let h2Attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.darkGray,
        ]
        let h3Attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
        ]

        let attrString = NSMutableAttributedString()
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                attrString.append(NSAttributedString(string: line.dropFirst(2) + "\n", attributes: h1Attrs))
            } else if line.hasPrefix("## ") {
                attrString.append(NSAttributedString(string: line.dropFirst(3) + "\n", attributes: h2Attrs))
            } else if line.hasPrefix("### ") {
                attrString.append(NSAttributedString(string: line.dropFirst(4) + "\n", attributes: h3Attrs))
            } else {
                attrString.append(NSAttributedString(string: line + "\n", attributes: bodyAttrs))
            }
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        var charIndex = 0

        while charIndex < attrString.length {
            context.beginPDFPage(nil)
            let textRect = CGRect(
                x: margin,
                y: margin,
                width: pageRect.width - margin * 2,
                height: pageRect.height - margin * 2
            )
            context.saveGState()
            // CoreText draws bottom-up; flip the coordinate system for normal top-down layout.
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)

            let path = CGMutablePath()
            path.addRect(textRect)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(charIndex, 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)

            let frameRange = CTFrameGetVisibleStringRange(frame)
            charIndex += frameRange.length

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return pdfData as Data
    }
}

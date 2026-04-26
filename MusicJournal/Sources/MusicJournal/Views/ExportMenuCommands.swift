// ExportMenuCommands.swift
// Injects export and import commands into the macOS menu bar under File.
// The commands mirror what's available in ExportSheet / SettingsView but
// provide keyboard shortcuts and are accessible without opening a sheet.

import SwiftUI

/// Menu bar commands injected into the File menu (replacing the default
/// import/export group). ⌘⇧E exports all playlists as Markdown.
struct ExportMenuCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Export All as Markdown…") {
                exportAll(format: .markdown)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Export All as PDF…") {
                exportAll(format: .pdf)
            }

            Divider()

            Button("Export Database (JSON)…") {
                exportAll(format: .json)
            }

            // Import is handled through Settings > Data so the user sees the
            // backup warning before choosing a file.
            Button("Import Database…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    private enum Format { case markdown, pdf, json }

    private func exportAll(format: Format) {
        do {
            switch format {
            case .markdown:
                let content = try ExportService.shared.exportAllAsMarkdown()
                saveToDisk(data: Data(content.utf8), name: "MusicJournal.md")
            case .pdf:
                let data = try ExportService.shared.exportAllAsPDF()
                saveToDisk(data: data, name: "MusicJournal.pdf")
            case .json:
                let data = try ExportService.shared.exportDatabaseAsJSON()
                saveToDisk(data: data, name: "MusicJournal.json")
            }
        } catch {}
    }

    private func saveToDisk(data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

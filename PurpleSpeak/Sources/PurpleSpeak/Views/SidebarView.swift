import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The document library + quick-add affordances + the Transcribe entry.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: DocumentStore
    @State private var renaming: Document?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.documents.isEmpty {
                Spacer()
                Text("Your library is empty.\nImport or paste something to begin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(selection: Binding(
                    get: { appState.selectedDocumentID },
                    set: { id in
                        if let id, let doc = store.documents.first(where: { $0.id == id }) {
                            appState.select(doc)
                        }
                    })
                ) {
                    ForEach(store.documents) { doc in
                        row(doc).tag(doc.id)
                            .contextMenu { rowMenu(doc) }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers); return true
        }
        .alert("Rename Document", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let doc = renaming { store.rename(doc, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "books.vertical.fill").foregroundStyle(.purple)
            Text("Library").font(.headline)
            Spacer()
            Menu {
                Button("Import Documents / Images…") { appState.presentImportPanel() }
                Button("New from Pasted Text") { appState.startPasteFlow() }
                Button("Read Web Article…") { appState.startWebFlow() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ doc: Document) -> some View {
        HStack(spacing: 8) {
            Image(systemName: doc.sourceKind.symbol)
                .foregroundStyle(.purple)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.title).lineLimit(1).truncationMode(.middle)
                Text("\(doc.characterCount.formatted()) chars")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowMenu(_ doc: Document) -> some View {
        Button("Read Aloud") { appState.select(doc); appState.startReading(from: 0) }
        Button("Rename…") { renameText = doc.title; renaming = doc }
        if let path = doc.originalPath, !path.hasPrefix("http") {
            Button("Reveal Original in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.delete(doc)
            appState.clearSelectionIfDeleted()
        }
    }

    private var footer: some View {
        Button {
            appState.presentTranscribePanel()
        } label: {
            HStack {
                Image(systemName: "waveform.badge.mic")
                Text("Transcribe Audio / Video…")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { appState.importFiles(urls) }
        }
    }
}

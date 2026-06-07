import Foundation

/// A piece of text the user has brought into PurpleSpeak to read aloud.
/// The extracted plain text is stored in a sidecar `.txt` file under
/// `SupportPaths.documentsStore`; this struct is the lightweight index
/// entry persisted in `library.json`.
struct Document: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sourceKind: SourceKind
    /// Original file path (if imported from a file), for "Reveal in Finder".
    var originalPath: String?
    var createdAt: Date
    var characterCount: Int

    enum SourceKind: String, Codable {
        case plainText, pdf, epub, docx, rtf, web, ocr, transcript

        var symbol: String {
            switch self {
            case .plainText:  return "doc.plaintext"
            case .pdf:        return "doc.richtext"
            case .epub:       return "book"
            case .docx:       return "doc.text"
            case .rtf:        return "doc.text"
            case .web:        return "globe"
            case .ocr:        return "text.viewfinder"
            case .transcript: return "waveform"
            }
        }
    }

    /// Path to the extracted-text sidecar.
    var textFileURL: URL {
        SupportPaths.documentsStore.appendingPathComponent("\(id.uuidString).txt")
    }
}

/// Persists the document library (index + extracted-text sidecars).
@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var documents: [Document] = []

    init() { load() }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601   // must match persistIndex()
        guard let data = try? Data(contentsOf: SupportPaths.libraryFile),
              let decoded = try? decoder.decode([Document].self, from: data) else {
            documents = []
            return
        }
        // Newest first.
        documents = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(documents) else { return }
        try? data.write(to: SupportPaths.libraryFile, options: .atomic)
    }

    /// Read the extracted text for a document from its sidecar.
    func text(for doc: Document) -> String {
        (try? String(contentsOf: doc.textFileURL, encoding: .utf8)) ?? ""
    }

    /// Create a new document from already-extracted text, writing the sidecar
    /// and prepending it to the library. Returns the stored document.
    @discardableResult
    func add(title: String, text: String, kind: Document.SourceKind, originalPath: String? = nil) -> Document {
        let doc = Document(
            id: UUID(),
            title: title.isEmpty ? "Untitled" : title,
            sourceKind: kind,
            originalPath: originalPath,
            createdAt: Date(),
            characterCount: text.count
        )
        try? text.write(to: doc.textFileURL, atomically: true, encoding: .utf8)
        documents.insert(doc, at: 0)
        persistIndex()
        return doc
    }

    func rename(_ doc: Document, to newTitle: String) {
        guard let idx = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents[idx].title = newTitle
        persistIndex()
    }

    func delete(_ doc: Document) {
        try? FileManager.default.removeItem(at: doc.textFileURL)
        documents.removeAll { $0.id == doc.id }
        persistIndex()
    }

    /// Update a document's stored text (e.g. after editing a transcript).
    func updateText(_ doc: Document, to newText: String) {
        guard let idx = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        try? newText.write(to: doc.textFileURL, atomically: true, encoding: .utf8)
        documents[idx].characterCount = newText.count
        persistIndex()
    }
}

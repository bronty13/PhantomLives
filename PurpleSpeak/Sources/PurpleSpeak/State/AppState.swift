import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Central coordinator: owns the stores + engines, holds the current
/// selection / reading text, and exposes the verbs the UI calls. Injected
/// into the environment alongside the individual `ObservableObject`s it owns
/// so SwiftUI observes each one directly.
@MainActor
final class AppState: ObservableObject {

    enum Mode: String { case reader, transcriber }

    let settingsStore = SettingsStore()
    let documentStore = DocumentStore()
    let tts = AVSpeechTTSEngine()
    let modelManager = WhisperModelManager()

    @Published var mode: Mode = .reader
    @Published var selectedDocumentID: UUID?
    /// The extracted text of the selected document, loaded into memory for the
    /// reader pane + highlight coordinates.
    @Published var currentText: String = ""

    @Published var isBusy = false
    @Published var busyMessage = ""
    /// Surfaces as an alert in ContentView.
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    // Transcriber state
    @Published var transcript: TranscriptionResult?
    @Published var transcriptSourceName: String = ""

    // Sheet flags driven by menu commands / sidebar buttons.
    @Published var showPasteSheet = false
    @Published var showWebSheet = false

    var selectedDocument: Document? {
        guard let id = selectedDocumentID else { return nil }
        return documentStore.documents.first { $0.id == id }
    }

    init() {
        // Auto-backup-on-launch (PhantomLives standard).
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
    }

    // MARK: - Selection

    func select(_ doc: Document) {
        tts.stop()
        selectedDocumentID = doc.id
        currentText = documentStore.text(for: doc)
        mode = .reader
    }

    func clearSelectionIfDeleted() {
        if let id = selectedDocumentID,
           !documentStore.documents.contains(where: { $0.id == id }) {
            selectedDocumentID = nil
            currentText = ""
            tts.stop()
        }
    }

    // MARK: - Reading

    /// Push current settings onto the engine, then read from `offset`.
    func startReading(from offset: Int = 0) {
        guard !currentText.isEmpty else { return }
        // Seed a sensible default voice (user's locale) on first read so the
        // picker and the spoken voice agree instead of falling to whatever
        // sorts first alphabetically.
        if settingsStore.settings.defaultVoiceIdentifier == nil {
            settingsStore.settings.defaultVoiceIdentifier = AVSpeechTTSEngine.systemDefaultVoiceID()
        }
        let s = settingsStore.settings
        tts.voiceIdentifier = s.defaultVoiceIdentifier
        tts.rateMultiplier = s.speechRateMultiplier
        tts.pitch = s.speechPitch
        tts.highlightSentence = s.highlightSentence
        tts.speak(currentText, from: offset)
    }

    func togglePlayPause() {
        if tts.isSpeaking && !tts.isPaused {
            tts.pause()
        } else if tts.isPaused {
            tts.resume()
        } else {
            startReading(from: 0)
        }
    }

    // MARK: - Import: files

    /// Import one or more files (documents and/or images). Runs extraction on
    /// the main actor (AppKit HTML/EPUB readers require it); large files still
    /// complete well within an acceptable UI pause for a personal tool.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isBusy = true
        busyMessage = "Importing…"
        Task {
            var imported = 0
            var firstDoc: Document?
            for url in urls {
                do {
                    let doc = try importOne(url)
                    if firstDoc == nil { firstDoc = doc }
                    imported += 1
                } catch {
                    errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            isBusy = false
            busyMessage = ""
            if let doc = firstDoc { select(doc) }
            if imported > 1 { infoMessage = "Imported \(imported) documents." }
        }
    }

    private func importOne(_ url: URL) throws -> Document {
        let ext = url.pathExtension.lowercased()
        if OCRService.supportedImageExtensions.contains(ext) {
            let text = try OCRService.recognizeText(imageURL: url)
            return documentStore.add(title: url.deletingPathExtension().lastPathComponent,
                                     text: text, kind: .ocr, originalPath: url.path)
        }
        if ext == "pdf" {
            // Try the text layer; fall back to OCR for scanned PDFs.
            let (title, text) = try TextExtractionService.extract(fileURL: url)
            if text.count >= 8 {
                return documentStore.add(title: title, text: text, kind: .pdf, originalPath: url.path)
            }
            let ocr = try OCRService.recognizePDF(url)
            return documentStore.add(title: title, text: ocr, kind: .ocr, originalPath: url.path)
        }
        let (title, text) = try TextExtractionService.extract(fileURL: url)
        let kind = Self.kind(forExtension: ext)
        return documentStore.add(title: title, text: text, kind: kind, originalPath: url.path)
    }

    private static func kind(forExtension ext: String) -> Document.SourceKind {
        switch ext {
        case "pdf": return .pdf
        case "epub": return .epub
        case "docx", "doc": return .docx
        case "rtf", "rtfd": return .rtf
        case "html", "htm": return .web
        default: return .plainText
        }
    }

    // MARK: - Import: pasted text

    func importPastedText(title: String, text: String) {
        let cleaned = TextExtractionService.normalize(text)
        guard !cleaned.isEmpty else { errorMessage = "Nothing to add — the text was empty."; return }
        let doc = documentStore.add(
            title: title.isEmpty ? String(cleaned.prefix(40)) : title,
            text: cleaned, kind: .plainText)
        select(doc)
    }

    // MARK: - Import: web article

    func importWebArticle(_ urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s) else { errorMessage = "That doesn't look like a web address."; return }
        isBusy = true
        busyMessage = "Fetching article…"
        Task {
            do {
                let (title, text) = try await TextExtractionService.extractWebArticle(url)
                let doc = documentStore.add(title: title, text: text, kind: .web, originalPath: url.absoluteString)
                select(doc)
            } catch {
                errorMessage = "Couldn't read that page: \(error.localizedDescription)"
            }
            isBusy = false
            busyMessage = ""
        }
    }

    // MARK: - Audio export

    func exportCurrentAudio() {
        guard let doc = selectedDocument, !currentText.isEmpty else { return }
        let s = settingsStore.settings
        isBusy = true
        busyMessage = "Rendering audio…"
        Task {
            do {
                let result = try await AudioExportService.export(
                    text: currentText,
                    title: doc.title,
                    voiceIdentifier: s.defaultVoiceIdentifier,
                    rateMultiplier: s.speechRateMultiplier,
                    pitch: s.speechPitch,
                    format: s.preferredAudioFormat,
                    to: settingsStore.resolvedOutputPath)
                isBusy = false
                busyMessage = ""
                NSWorkspace.shared.activateFileViewerSelecting([result.url])
                infoMessage = result.fellBackToM4A
                    ? "Saved \(result.url.lastPathComponent) (MP3 needs `lame` — exported M4A instead)."
                    : "Saved \(result.url.lastPathComponent)."
            } catch {
                isBusy = false
                busyMessage = ""
                errorMessage = "Audio export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Transcription (STT)

    private var sttEngine: STTEngine {
        WhisperCppEngine(modelName: settingsStore.settings.whisperModel)
    }

    func transcribe(fileURL url: URL) {
        let engine = sttEngine
        if !engine.isAvailable {
            errorMessage = engine.unavailableReason
            return
        }
        mode = .transcriber
        transcript = nil
        transcriptSourceName = url.lastPathComponent
        isBusy = true
        busyMessage = "Transcribing \(url.lastPathComponent)…"
        let lang = settingsStore.settings.transcriptionLanguage
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await engine.transcribe(audioURL: url, language: lang)
                }.value
                transcript = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
            busyMessage = ""
        }
    }

    // MARK: - Open panels & flows

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let docExts = Array(TextExtractionService.supportedExtensions)
        let imgExts = Array(OCRService.supportedImageExtensions)
        panel.allowedContentTypes = (docExts + imgExts).compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    func presentTranscribePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mp3, .wav, .aiff, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url { transcribe(fileURL: url) }
    }

    func startPasteFlow() { showPasteSheet = true }
    func startWebFlow() { showWebSheet = true }

    /// Skip the reading position forward/back by whole paragraphs and resume
    /// reading there. Uses the current spoken-word location as the anchor.
    func skip(byParagraphs delta: Int) {
        guard !currentText.isEmpty else { return }
        let offsets = Self.paragraphStartOffsets(currentText)
        guard !offsets.isEmpty else { return }
        let pos = tts.spokenWordRange?.location ?? 0
        // Index of the paragraph currently containing `pos`.
        var current = 0
        for (i, off) in offsets.enumerated() where off <= pos { current = i }
        let target = max(0, min(offsets.count - 1, current + delta))
        startReading(from: offsets[target])
    }

    /// Character offsets at which each paragraph begins. Pure + static so the
    /// skip logic is unit-testable.
    static func paragraphStartOffsets(_ text: String) -> [Int] {
        let ns = text as NSString
        var offsets: [Int] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byParagraphs) { sub, range, _, _ in
            if let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offsets.append(range.location)
            }
        }
        if offsets.isEmpty { offsets = [0] }
        return offsets
    }

    /// Save the current transcript into the library as a readable document.
    func saveTranscriptAsDocument() {
        guard let t = transcript else { return }
        let title = "Transcript — \(transcriptSourceName)"
        let doc = documentStore.add(title: title, text: t.fullText, kind: .transcript)
        select(doc)
    }

    /// Export the current transcript as .txt or .srt to the output folder.
    func exportTranscript(asSRT: Bool) {
        guard let t = transcript else { return }
        let base = AudioExportService.sanitize(transcriptSourceName.isEmpty ? "transcript" : transcriptSourceName)
        let ext = asSRT ? "srt" : "txt"
        let dir = settingsStore.resolvedOutputPath
        let url = dir.appendingPathComponent("\(base).\(ext)")
        do {
            try (asSRT ? t.srt : t.fullText).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            infoMessage = "Saved \(url.lastPathComponent)."
        } catch {
            errorMessage = "Couldn't save transcript: \(error.localizedDescription)"
        }
    }
}

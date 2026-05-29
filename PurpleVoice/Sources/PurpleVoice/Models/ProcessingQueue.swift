import Foundation
import Combine
import AppKit

/// In-memory clip queue + processing coordinator. Holds the list of
/// `Clip` objects displayed in the sidebar, drives them through the
/// `ClipProcessor` one at a time (FIFO), and exposes the currently
/// selected clip for the detail pane.
///
/// Single-clip-at-a-time processing is deliberate — ffmpeg's audio
/// filters are CPU-bound and running multiple in parallel doesn't speed
/// up a normal queue, it just makes individual clips finish later. A
/// future setting could lift this for multi-core machines.
@MainActor
final class ProcessingQueue: ObservableObject {

    @Published private(set) var clips: [Clip] = []
    @Published var selectedClipID: Clip.ID?
    @Published private(set) var isProcessing: Bool = false

    private let processor = ClipProcessor()

    /// Accept a list of dropped/imported URLs. Audio + video files pass;
    /// directories are expanded one level deep; unknown extensions are
    /// silently skipped so a drag of a mixed Finder selection works.
    func ingest(urls: [URL], settings: SettingsStore) {
        let expanded = expand(urls: urls)
        // Track URLs already accepted in *this* ingest call so duplicates
        // inside a single drop don't all create clips. Pre-seed with
        // already-queued sources for the same reason.
        var seen = Set(clips.map { $0.sourceURL })
        let added: [Clip] = expanded.compactMap { url in
            guard Self.isAcceptedExtension(url.pathExtension) else { return nil }
            if seen.contains(url) { return nil }
            seen.insert(url)
            return Clip(sourceURL: url)
        }
        guard !added.isEmpty else { return }
        clips.append(contentsOf: added)
        if selectedClipID == nil { selectedClipID = added.first?.id }
        // Auto-kick processing — the user dropped clips because they
        // want them cleaned. A future setting could gate this on a
        // "manual run" toggle.
        Task { await processPending(settings: settings) }
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        if selectedClipID == clip.id { selectedClipID = clips.first?.id }
    }

    func clearCompleted() {
        clips.removeAll { $0.status == .done }
        if let sel = selectedClipID, !clips.contains(where: { $0.id == sel }) {
            selectedClipID = clips.first?.id
        }
    }

    func retry(_ clip: Clip, settings: SettingsStore) {
        clip.status = .queued
        clip.lastError = nil
        clip.progress = 0
        clip.outputURL = nil
        Task { await processPending(settings: settings) }
    }

    /// Drains queued clips one at a time. Safe to call concurrently —
    /// the early-return on `isProcessing` keeps us serial.
    func processPending(settings: SettingsStore) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        while let next = clips.first(where: { $0.status == .queued }) {
            await run(clip: next, settings: settings)
        }
    }

    private func run(clip: Clip, settings: SettingsStore) async {
        clip.status = .processing
        clip.progress = 0
        clip.lastError = nil
        do {
            let outputURL = try settings.resolveOutputURL(for: clip.sourceURL)
            let options = ProcessingOptions(
                profile: settings.profile,
                enhancementEnabled: settings.enhancementEnabled,
                engine: settings.processingEngine,
                loudnessTarget: settings.loudnessTarget,
                deEsserEnabled: settings.deEsserEnabled,
                deClickerEnabled: settings.deClickerEnabled,
                preserveStereo: settings.preserveStereo,
                dereverbEnabled: settings.dereverbEnabled,
                outputFormat: settings.outputFormat,
                deepFilterPathOverride: settings.deepFilterPathOverride,
                trimStart: clip.trimStart,
                trimEnd: clip.trimEnd,
                tuning: settings.effectiveTuning
            )
            try await processor.process(
                clip: clip,
                options: options,
                outputURL: outputURL
            ) { p in
                Task { @MainActor in clip.progress = p }
            }
            clip.outputURL = outputURL
            clip.status = .done
            clip.progress = 1.0
            if settings.autoRevealAfterProcess {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        } catch {
            clip.status = .failed
            clip.lastError = (error as? ClipProcessorError)?.userMessage
                ?? error.localizedDescription
        }
    }

    // MARK: - URL ingestion helpers

    private func expand(urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let entries = try? fm.contentsOfDirectory(at: url,
                                                             includingPropertiesForKeys: nil) {
                    out.append(contentsOf: entries.filter {
                        Self.isAcceptedExtension($0.pathExtension)
                    })
                }
            } else {
                out.append(url)
            }
        }
        return out
    }

    nonisolated static let acceptedExtensions: Set<String> = [
        "m4a", "aac", "mp3", "wav", "aif", "aiff", "caf",
        "mp4", "m4v", "mov"
    ]

    nonisolated static func isAcceptedExtension(_ ext: String) -> Bool {
        acceptedExtensions.contains(ext.lowercased())
    }
}

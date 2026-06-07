import Foundation
import AVFoundation

/// Renders narrated text to an audio file for offline / commute listening.
///
/// Pipeline: `AVSpeechSynthesizer.write(_:toBufferCallback:)` synthesizes the
/// utterance into PCM buffers (faster than real time, no playback), which we
/// append to a temporary `.caf`, then transcode:
///   • `.m4a` (AAC) — native via `AVAssetExportSession`, plays everywhere;
///     this is the default.
///   • `.mp3` — AVFoundation has no MP3 *encoder*, so we shell out to `lame`
///     when it's on PATH; otherwise we fall back to `.m4a` and tell the caller.
@MainActor
enum AudioExportService {

    enum ExportError: Error, LocalizedError {
        case nothingRendered
        case writeFailed(String)
        case transcodeFailed(String)
        var errorDescription: String? {
            switch self {
            case .nothingRendered:       return "The synthesizer produced no audio."
            case .writeFailed(let s):    return "Couldn't write audio: \(s)"
            case .transcodeFailed(let s):return "Couldn't convert audio: \(s)"
            }
        }
    }

    struct Result {
        let url: URL
        /// True when an MP3 was requested but `lame` was unavailable, so we
        /// produced an `.m4a` instead.
        let fellBackToM4A: Bool
    }

    /// Render `text` to an audio file named after `title`, in `directory`.
    /// `format` is "m4a" or "mp3".
    static func export(text: String,
                       title: String,
                       voiceIdentifier: String?,
                       rateMultiplier: Double,
                       pitch: Double,
                       format: String,
                       to directory: URL) async throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // 1. Synthesize to a temp CAF.
        let cafURL = fm.temporaryDirectory
            .appendingPathComponent("ps-tts-\(UUID().uuidString).caf")
        defer { try? fm.removeItem(at: cafURL) }
        try await renderToCAF(text: text,
                              voiceIdentifier: voiceIdentifier,
                              rateMultiplier: rateMultiplier,
                              pitch: pitch,
                              outURL: cafURL)

        // 2. Transcode.
        let safeTitle = sanitize(title)
        if format == "mp3", let lame = lamePath() {
            let mp3URL = uniqueURL(in: directory, base: safeTitle, ext: "mp3")
            try transcodeToMP3(cafURL: cafURL, mp3URL: mp3URL, lame: lame)
            return Result(url: mp3URL, fellBackToM4A: false)
        }
        let m4aURL = uniqueURL(in: directory, base: safeTitle, ext: "m4a")
        try await transcodeToM4A(cafURL: cafURL, m4aURL: m4aURL)
        return Result(url: m4aURL, fellBackToM4A: format == "mp3")
    }

    // MARK: - Synthesis

    private static func renderToCAF(text: String,
                                    voiceIdentifier: String?,
                                    rateMultiplier: Double,
                                    pitch: Double,
                                    outURL: URL) async throws {
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if let vid = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: vid) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechTTSEngine.mappedRate(rateMultiplier)
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, pitch)))

        // `write` calls back repeatedly; an empty buffer signals completion.
        // A class box lets the @Sendable callback own the lazily-created file
        // and surface the first error without capturing `var`s.
        final class Box: @unchecked Sendable {
            var file: AVAudioFile?
            var error: Error?
            var wroteAny = false
        }
        let box = Box()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !resumed { resumed = true; cont.resume() }
                    return
                }
                do {
                    if box.file == nil {
                        box.file = try AVAudioFile(forWriting: outURL,
                                                   settings: pcm.format.settings)
                    }
                    try box.file?.write(from: pcm)
                    box.wroteAny = true
                } catch {
                    box.error = error
                    if !resumed { resumed = true; cont.resume() }
                }
            }
        }

        if let e = box.error { throw ExportError.writeFailed(e.localizedDescription) }
        guard box.wroteAny else { throw ExportError.nothingRendered }
    }

    // MARK: - Transcode

    private static func transcodeToM4A(cafURL: URL, m4aURL: URL) async throws {
        try? FileManager.default.removeItem(at: m4aURL)
        let asset = AVURLAsset(url: cafURL)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.transcodeFailed("Couldn't create the export session.")
        }
        session.outputURL = m4aURL
        session.outputFileType = .m4a
        await session.export()
        if session.status != .completed {
            throw ExportError.transcodeFailed(session.error?.localizedDescription ?? "unknown")
        }
    }

    private static func transcodeToMP3(cafURL: URL, mp3URL: URL, lame: String) throws {
        try? FileManager.default.removeItem(at: mp3URL)
        // lame can't read CAF directly; pipe through afconvert to a temp WAV.
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-tts-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16", cafURL.path, wav.path])
        try run(lame, ["-V", "2", "--silent", wav.path, mp3URL.path])
    }

    // MARK: - Helpers

    private static func lamePath() -> String? {
        for p in ["/opt/homebrew/bin/lame", "/usr/local/bin/lame"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw ExportError.transcodeFailed("\(URL(fileURLWithPath: tool).lastPathComponent) exit \(proc.terminationStatus): \(err)")
        }
    }

    static func sanitize(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.isEmpty ? "narration" : trimmed
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return String(collapsed.unicodeScalars.map { illegal.contains($0) ? "_" : Character($0) })
            .prefix(80).description
    }

    private static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

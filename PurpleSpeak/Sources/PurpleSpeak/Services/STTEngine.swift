import Foundation
import AVFoundation

/// One timestamped chunk of a transcription.
struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    var start: Double      // seconds
    var end: Double        // seconds
    var text: String
}

struct TranscriptionResult: Equatable {
    var segments: [TranscriptSegment]
    var fullText: String { segments.map(\.text).joined(separator: " ") }

    /// SubRip (.srt) rendering for export.
    var srt: String {
        var out = ""
        for (i, seg) in segments.enumerated() {
            out += "\(i + 1)\n"
            out += "\(Self.srtTime(seg.start)) --> \(Self.srtTime(seg.end))\n"
            out += "\(seg.text.trimmingCharacters(in: .whitespaces))\n\n"
        }
        return out
    }

    static func srtTime(_ t: Double) -> String {
        let ms = Int((t - floor(t)) * 1000)
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

/// A speech-to-text backend. v1 default is `WhisperCppEngine` (bundled,
/// self-contained, on-device). The protocol keeps room for an opt-in MLX
/// backend that shells out to the repo's `transcribe/` tool.
protocol STTEngine {
    /// Whether the engine can run right now (binary + model present).
    var isAvailable: Bool { get }
    /// A human-readable reason when `isAvailable` is false.
    var unavailableReason: String? { get }
    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult
}

enum STTError: Error, LocalizedError {
    case binaryMissing
    case modelMissing(String)
    case audioConversionFailed(String)
    case transcriptionFailed(String)
    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "The whisper-cli binary isn't bundled. Rebuild PurpleSpeak with whisper-cpp installed (brew install whisper-cpp)."
        case .modelMissing(let m):
            return "The Whisper model “\(m)” hasn't been downloaded yet. Open Settings → Transcription to download it."
        case .audioConversionFailed(let s):
            return "Couldn't prepare the audio: \(s)"
        case .transcriptionFailed(let s):
            return "Transcription failed: \(s)"
        }
    }
}

/// Drives the bundled `whisper-cli` (whisper.cpp). Converts any audio/video
/// input to the 16 kHz mono WAV whisper.cpp expects, runs the binary, and
/// parses its bracketed `[hh:mm:ss.mmm --> …]` stdout into segments.
final class WhisperCppEngine: STTEngine {
    let modelName: String

    init(modelName: String) {
        self.modelName = modelName
    }

    /// The bundled binary, copied into Contents/Resources by build-app.sh.
    static func bundledBinaryURL() -> URL? {
        if let url = Bundle.main.url(forResource: "whisper-cli", withExtension: nil) {
            return url
        }
        // Dev fallback: a whisper-cli on PATH (swift run, tests).
        for p in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    var modelURL: URL { SupportPaths.modelsDirectory.appendingPathComponent(modelName) }

    var isAvailable: Bool {
        Self.bundledBinaryURL() != nil && FileManager.default.fileExists(atPath: modelURL.path)
    }

    var unavailableReason: String? {
        if Self.bundledBinaryURL() == nil { return STTError.binaryMissing.localizedDescription }
        if !FileManager.default.fileExists(atPath: modelURL.path) {
            return STTError.modelMissing(modelName).localizedDescription
        }
        return nil
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        guard let binary = Self.bundledBinaryURL() else { throw STTError.binaryMissing }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw STTError.modelMissing(modelName)
        }

        // 1. Normalize to 16 kHz mono 16-bit WAV.
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-stt-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try convertTo16kWav(input: audioURL, output: wav)

        // 2. Run whisper-cli.
        var args = ["-m", modelURL.path, "-f", wav.path, "-nt"] // -nt: no extra timestamps token noise
        // whisper-cli prints bracketed timestamps by default; keep them.
        args = ["-m", modelURL.path, "-f", wav.path]
        if language != "auto" { args += ["-l", language] }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw STTError.transcriptionFailed(error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw STTError.transcriptionFailed("exit \(proc.terminationStatus): \(err)")
        }
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let segments = Self.parseWhisperOutput(stdout)
        guard !segments.isEmpty else {
            throw STTError.transcriptionFailed("No speech recognized.")
        }
        return TranscriptionResult(segments: segments)
    }

    /// Convert any decodable audio/video to whisper.cpp's required format.
    private func convertTo16kWav(input: URL, output: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        proc.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", input.path, output.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw STTError.audioConversionFailed(error.localizedDescription)
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw STTError.audioConversionFailed("afconvert exit \(proc.terminationStatus): \(err)")
        }
    }

    /// Parse whisper.cpp stdout lines like:
    ///   `[00:00:00.000 --> 00:00:04.000]   Hello there.`
    /// into segments. Pure + static for unit testing.
    static func parseWhisperOutput(_ output: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let pattern = #"\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 10 else { continue }
            func g(_ i: Int) -> Double { Double(ns.substring(with: m.range(at: i))) ?? 0 }
            let start = g(1) * 3600 + g(2) * 60 + g(3) + g(4) / 1000
            let end   = g(5) * 3600 + g(6) * 60 + g(7) + g(8) / 1000
            let text = ns.substring(with: m.range(at: 9)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                segments.append(TranscriptSegment(start: start, end: end, text: text))
            }
        }
        return segments
    }
}

/// Downloads / tracks Whisper GGML models under
/// ~/Library/Application Support/PurpleSpeak/models/. Models are large
/// (hundreds of MB) so they are fetched on demand, never bundled or committed.
@MainActor
final class WhisperModelManager: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var lastError: String?

    /// Models we offer, with their Hugging Face download URLs.
    static let catalog: [(name: String, label: String, url: String)] = [
        ("ggml-large-v3-turbo.bin", "Large v3 Turbo (best accuracy, ~1.5 GB)",
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
        ("ggml-base.en.bin", "Base English (fast, ~150 MB)",
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
        ("ggml-small.bin", "Small multilingual (~500 MB)",
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
    ]

    func isInstalled(_ name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: SupportPaths.modelsDirectory.appendingPathComponent(name).path)
    }

    func download(name: String) async {
        guard let entry = Self.catalog.first(where: { $0.name == name }),
              let url = URL(string: entry.url) else {
            lastError = "Unknown model: \(name)"
            return
        }
        isDownloading = true
        progress = 0
        lastError = nil
        defer { isDownloading = false }

        let dest = SupportPaths.modelsDirectory.appendingPathComponent(name)
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw STTError.transcriptionFailed("HTTP \(http.statusCode) downloading model")
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            progress = 1
        } catch {
            lastError = error.localizedDescription
        }
    }
}

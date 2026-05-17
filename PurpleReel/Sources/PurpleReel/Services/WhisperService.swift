import Foundation

/// One subtitle in a parsed SRT.
struct TranscriptSegment: Codable, Equatable {
    let index: Int
    let start: Double   // seconds
    let end: Double
    let text: String
}

/// Parsed transcript persisted into the `transcript` table as JSON.
struct TranscriptDocument: Codable, Equatable {
    var fullText: String
    var segments: [TranscriptSegment]
    var modelName: String
    var generatedAt: Date
}

/// Bridge to the sibling `transcribe/` MLX-Whisper project. We invoke
/// `python3 transcribe.py -i <file> -o <tmpdir> -f srt --quiet`, then
/// parse the produced SRT into a `TranscriptDocument`. No data leaves
/// the local machine.
enum WhisperService {

    enum WhisperError: Error, LocalizedError {
        case scriptMissing(String)
        case execFailed(Int32, String)
        case srtMissing(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing(let p): return "transcribe.py not found at \(p)"
            case .execFailed(let code, let log):
                return "transcribe.py exited \(code).\n\(log.suffix(800))"
            case .srtMissing(let dir): return "No .srt found in \(dir)"
            case .parseFailed(let line): return "Could not parse SRT line: \(line)"
            }
        }
    }

    /// Default path to the sibling project. Overridable by the user via
    /// `transcribePath` setting (Settings → AI).
    static var defaultScriptPath: String {
        ("~/Documents/GitHub/PhantomLives/transcribe/transcribe.py" as NSString)
            .expandingTildeInPath
    }

    /// Run transcribe.py end-to-end and return the parsed transcript.
    /// Long-running: hop off the main actor before calling.
    static func transcribe(file url: URL,
                            model: String = "turbo",
                            scriptPath: String? = nil) async throws -> TranscriptDocument {
        let script = (scriptPath ?? defaultScriptPath)
        guard FileManager.default.fileExists(atPath: script) else {
            throw WhisperError.scriptMissing(script)
        }

        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("purplereel-whisper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tmp,
                                                  withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let (code, log) = try await Task.detached(priority: .userInitiated) {
            invokePython(script: script, args: [
                "-i", url.path,
                "-o", tmp,
                "-f", "srt",
                "-m", model,
                "--quiet",
            ])
        }.value

        guard code == 0 else { throw WhisperError.execFailed(code, log) }

        // The script writes <basename>.srt into the output dir.
        let srtFiles = (try? FileManager.default.contentsOfDirectory(
            atPath: tmp).filter { $0.hasSuffix(".srt") }) ?? []
        guard let srtName = srtFiles.first else {
            throw WhisperError.srtMissing(tmp)
        }
        let srtURL = URL(fileURLWithPath: tmp).appendingPathComponent(srtName)
        let srt = try String(contentsOf: srtURL, encoding: .utf8)
        let segments = try parseSRT(srt)

        return TranscriptDocument(
            fullText: segments.map { $0.text }.joined(separator: " "),
            segments: segments,
            modelName: model,
            generatedAt: Date()
        )
    }

    /// Public for unit-testability — pure function over SRT text.
    static func parseSRT(_ text: String) throws -> [TranscriptSegment] {
        // SRT blocks separated by a blank line; each block is:
        //   <index>
        //   <hh:mm:ss,mmm> --> <hh:mm:ss,mmm>
        //   <text line 1>
        //   <text line 2>
        //   ...
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [TranscriptSegment] = []
        result.reserveCapacity(blocks.count)

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }
            let idx = Int(lines[0].trimmingCharacters(in: .whitespaces)) ?? (result.count + 1)
            let timing = lines[1]
            let parts = timing.components(separatedBy: " --> ")
            guard parts.count == 2 else {
                throw WhisperError.parseFailed(timing)
            }
            let startSec = parseSRTTimestamp(parts[0])
            let endSec = parseSRTTimestamp(parts[1])
            let body = lines.dropFirst(2).joined(separator: "\n")
            result.append(TranscriptSegment(
                index: idx, start: startSec, end: endSec, text: body
            ))
        }
        return result
    }

    private static func parseSRTTimestamp(_ s: String) -> Double {
        // hh:mm:ss,mmm
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let secMs = parts[2].replacingOccurrences(of: ",", with: ".")
        let s = Double(secMs) ?? 0
        return h * 3600 + m * 60 + s
    }

    private static func invokePython(script: String, args: [String]) -> (Int32, String) {
        let task = Process()
        // Prefer a user-installed Python over /usr/bin/python3
        // (which is Python 3.9 on macOS Sonoma and rejected by
        // transcribe.py's 3.10+ check).
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        let interpreter = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "/usr/bin/python3"
        task.executableURL = URL(fileURLWithPath: interpreter)
        task.arguments = [script] + args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (-1, "Could not exec \(interpreter): \(error.localizedDescription)")
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

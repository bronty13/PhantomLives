import Foundation

/// Generates a plain-text transcript from a clip's main MP4 by shelling out
/// to the sibling `transcribe.py` (MLX whisper, Apple Silicon only). The
/// script handles its own venv bootstrap on first run, so the only thing
/// this service does is locate it, run it, and capture stdout.
///
/// We pass `-o -` so the transcript streams to stdout instead of being
/// written to `~/Downloads/transcribe/`. We pass `-q` to suppress
/// progress output — anything on stderr is treated as diagnostic.
@MainActor
enum TranscriptionService {

    enum TranscribeError: LocalizedError {
        case sourceMissing(String)
        case scriptNotFound(checkedPaths: [String])
        case pythonNotFound
        case nonZeroExit(Int32, stderr: String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let p):
                return "Source MP4 not found: \(p)"
            case .scriptNotFound(let paths):
                return "Couldn't find transcribe.py at any of: \(paths.joined(separator: ", "))"
            case .pythonNotFound:
                return "python3 not on PATH"
            case .nonZeroExit(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "transcribe.py exited \(code)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
            case .emptyOutput:
                return "transcribe.py produced no output"
            }
        }
    }

    struct Outcome {
        let transcript: String
        let scriptPath: String
        let durationSeconds: TimeInterval
        var wordCount: Int { transcript.split(whereSeparator: \.isWhitespace).count }
    }

    /// Standard candidate paths for the sibling transcribe.py.
    /// Order matters — first hit wins.
    static let candidatePaths: [String] = [
        "\(NSHomeDirectory())/Documents/GitHub/PhantomLives/transcribe/transcribe.py",
        "\(NSHomeDirectory())/PhantomLives/transcribe/transcribe.py",
    ]

    /// Resolves which transcribe.py the service will run. Returns nil if
    /// nothing exists at any candidate path — the editor uses this to
    /// disable the button + show a hint.
    static func locateScript() -> String? {
        let fm = FileManager.default
        return candidatePaths.first { fm.isExecutableFile(atPath: $0) || fm.fileExists(atPath: $0) }
    }

    /// Runs transcribe.py against `sourcePath` and returns the captured
    /// transcript. Defaults: model = `turbo`, format = txt, output = stdout.
    /// Long clips may take many seconds — call from a Task.
    static func transcribe(sourcePath: String, model: String = "turbo") async throws -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else {
            throw TranscribeError.sourceMissing(sourcePath)
        }
        guard let script = locateScript() else {
            throw TranscribeError.scriptNotFound(checkedPaths: candidatePaths)
        }
        guard let python = resolvePython3() else {
            throw TranscribeError.pythonNotFound
        }

        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            script,
            "-i", sourcePath,
            "-o", "-",
            "-f", "txt",
            "-m", model,
            "-q",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError  = stderr
        process.standardInput  = nil

        try process.run()

        // Read pipes off-thread so giant transcripts don't deadlock.
        let outData = await Task.detached(priority: .userInitiated) {
            stdout.fileHandleForReading.readDataToEndOfFile()
        }.value
        let errData = await Task.detached(priority: .userInitiated) {
            stderr.fileHandleForReading.readDataToEndOfFile()
        }.value

        process.waitUntilExit()

        let stderrText = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw TranscribeError.nonZeroExit(process.terminationStatus, stderr: stderrText)
        }

        let raw = String(data: outData, encoding: .utf8) ?? ""
        let transcript = normalizeToParagraph(raw)
        guard !transcript.isEmpty else {
            throw TranscribeError.emptyOutput
        }

        return Outcome(
            transcript: transcript,
            scriptPath: script,
            durationSeconds: Date().timeIntervalSince(started)
        )
    }

    /// Whisper outputs `txt` as one line per segment, separated by `\n`.
    /// For our use case the transcript is meant to flow as a single
    /// paragraph (it's already a stream of speech), so collapse all
    /// CR/LF into spaces and squeeze runs of whitespace down to a single
    /// space. Final result is trimmed.
    private static func normalizeToParagraph(_ s: String) -> String {
        let withoutBreaks = s
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n",   with: " ")
            .replacingOccurrences(of: "\r",   with: " ")
            .replacingOccurrences(of: "\t",   with: " ")
        let collapsed = withoutBreaks
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    private static func resolvePython3() -> String? {
        let fm = FileManager.default
        // Standard install paths first; falls back to `which`.
        let known = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for p in known where fm.isExecutableFile(atPath: p) { return p }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty, fm.isExecutableFile(atPath: out) { return out }
        } catch {
            return nil
        }
        return nil
    }
}

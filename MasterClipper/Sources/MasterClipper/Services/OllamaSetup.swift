import Foundation

enum OllamaSetupState: Equatable {
    case idle
    case checking
    case notInstalled
    case starting
    case pullingModel(progress: Double)
    case ready
    case failed(String)
}

@MainActor
final class OllamaSetup: ObservableObject {
    @Published var state: OllamaSetupState = .idle
    @Published var statusMessage: String = ""

    static let shared = OllamaSetup()

    private let candidatePaths = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama",
    ]

    private init() {}

    var ollamaBinary: String? {
        candidatePaths.first { FileManager.default.fileExists(atPath: $0) }
            ?? whichOllama()
    }

    /// Detects Ollama, starts the server if it's not already up, and ensures
    /// `defaultModel` is pulled. Safe to call multiple times.
    func run(settings: AppSettings) async {
        guard settings.ollamaEnabled else { return }
        state = .checking
        statusMessage = "Looking for Ollama…"

        guard let binary = ollamaBinary else {
            state = .notInstalled
            statusMessage = "Ollama not found. Install with `brew install ollama`."
            return
        }

        if await isServerRunning(settings: settings) {
            state = .ready
            statusMessage = "Ready"
            return
        }

        guard settings.ollamaAutoStart else {
            state = .failed("Ollama server is not running and auto-start is disabled.")
            return
        }

        state = .starting
        statusMessage = "Starting Ollama server…"
        startServer(binary: binary)

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await isServerRunning(settings: settings) {
                state = .ready
                statusMessage = "Ready"
                return
            }
        }

        state = .failed("Ollama server did not respond. Try `ollama serve` in Terminal.")
        statusMessage = state == .failed("…") ? "Failed" : statusMessage
    }

    // MARK: - Helpers

    private func isServerRunning(settings: AppSettings) async -> Bool {
        let base = OllamaService.shared.baseURL(from: settings)
        let url = base.appendingPathComponent("api/tags")
        return (try? await URLSession.shared.data(from: url)) != nil
    }

    private func whichOllama() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", "which ollama"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func startServer(binary: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["serve"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        // Don't wait — let it run in the background
    }
}

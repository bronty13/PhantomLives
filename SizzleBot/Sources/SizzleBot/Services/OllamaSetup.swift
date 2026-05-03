import Foundation
import SwiftUI

enum SetupState: Equatable {
    case idle
    case checkingInstall
    case notInstalled
    case startingServer
    case pullingModel(progress: Double)
    case ready
    case failed(String)
}

@MainActor
class OllamaSetup: ObservableObject {
    @Published var state: SetupState = .idle
    @Published var statusMessage = ""

    private let baseURL = "http://localhost:11434"
    private let defaultModel = "dolphin-mistral"

    // Search order for the Ollama binary
    private let ollamaPaths = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama",
    ]

    var ollamaBinary: String? {
        ollamaPaths.first { FileManager.default.fileExists(atPath: $0) }
            ?? (shell("which ollama").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : shell("which ollama").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func run() async {
        state = .checkingInstall
        statusMessage = "Looking for Ollama…"

        guard let binary = ollamaBinary else {
            state = .notInstalled
            statusMessage = "Ollama is not installed."
            return
        }

        if await isServerRunning() {
            await ensureModelAvailable(binary: binary)
            return
        }

        state = .startingServer
        statusMessage = "Starting Ollama server…"
        startServer(binary: binary)

        // Poll up to 15 s
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await isServerRunning() {
                await ensureModelAvailable(binary: binary)
                return
            }
        }

        state = .failed("Ollama server did not respond. Try running `ollama serve` in Terminal.")
    }

    func installBrew() {
        // Opens Terminal with the Homebrew install command — user must approve
        let script = """
        tell application "Terminal"
            activate
            do script "/bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\" && brew install ollama && ollama serve"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private func ensureModelAvailable(binary: String) async {
        statusMessage = "Checking models…"
        let models = await listInstalledModels()

        if models.isEmpty {
            await pullModel(binary: binary, model: defaultModel)
        } else {
            state = .ready
            statusMessage = "Ready"
        }
    }

    private func pullModel(binary: String, model: String) async {
        state = .pullingModel(progress: 0)
        statusMessage = "Pulling \(model)…"

        guard let url = URL(string: "\(baseURL)/api/pull") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": model, "stream": true])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3600

        do {
            let (asyncBytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in asyncBytes.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                if let status = json["status"] as? String {
                    let total = json["total"] as? Double ?? 0
                    let completed = json["completed"] as? Double ?? 0
                    let progress = total > 0 ? completed / total : 0
                    state = .pullingModel(progress: progress)
                    statusMessage = status.hasPrefix("pulling") ? "Downloading \(model)… \(Int(progress * 100))%" : status
                }

                if let done = json["done"] as? Bool, done { break }
                if let status = json["status"] as? String, status == "success" { break }
            }
            state = .ready
            statusMessage = "Ready"
        } catch {
            state = .failed("Could not pull model '\(model)': \(error.localizedDescription)")
        }
    }

    private func isServerRunning() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        return (try? await URLSession.shared.data(from: url)) != nil
    }

    private func listInstalledModels() async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    private func startServer(binary: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["serve"]
        // Detach stdout/stderr so the process outlives its pipe
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        // Don't waitUntilExit — let it run in the background
    }

    @discardableResult
    private func shell(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

import Foundation

/// Reads the keyword vocabulary from the macOS Photos library via the `osxphotos` CLI
/// (`osxphotos keywords --json`). PhotoKit can't read keywords, so this is how PurplePeek
/// seeds its local keyword store with the ones already in Photos.
enum PhotosKeywordImporter {

    enum ImportError: Error, LocalizedError {
        case notInstalled
        case failed(Int32, String)
        case badOutput
        var errorDescription: String? {
            switch self {
            case .notInstalled:        return "osxphotos isn't installed."
            case .failed(let c, let e): return "osxphotos exited \(c): \(e)"
            case .badOutput:           return "Couldn't parse osxphotos output."
            }
        }
    }

    /// Locate the osxphotos binary (pipx installs to ~/.local/bin; Homebrew to its prefix).
    static func locate() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["\(home)/.local/bin/osxphotos", "/opt/homebrew/bin/osxphotos", "/usr/local/bin/osxphotos"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "osxphotos"]
        let pipe = Pipe(); proc.standardOutput = pipe
        try? proc.run(); proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Fetch the distinct keyword names from the Photos library. Synchronous (callers run it
    /// off the main actor).
    static func fetchKeywords(osxphotosPath: String) throws -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: osxphotosPath)
        proc.arguments = ["keywords", "--json"]
        let outPipe = Pipe(); proc.standardOutput = outPipe
        let errPipe = Pipe(); proc.standardError = errPipe
        do { try proc.run() } catch { throw ImportError.notInstalled }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImportError.failed(proc.terminationStatus, err)
        }
        // osxphotos may print a "Using last opened library…" line; isolate the JSON object.
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{") else { throw ImportError.badOutput }
        let jsonData = Data(text[start...].utf8)
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let keywords = root["keywords"] as? [String: Any] else { throw ImportError.badOutput }
        return Array(keywords.keys)
    }
}

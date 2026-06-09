import Foundation

/// Synchronous subprocess runner that streams combined stdout+stderr line-by-line to a
/// callback, so long-running osxphotos / rsync output is logged live rather than buffered
/// until exit. The engine is intentionally synchronous (a CLI doing blocking work), so this
/// blocks until the child exits and returns its termination status.
public enum ProcessRunner {

    public struct Result: Sendable {
        public let exitCode: Int32
        public let timedOut: Bool
    }

    /// Run `executable args…`, invoking `onLine` for each line of output.
    /// - Returns: the process result. Throws only if the process could not be launched.
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        environment: [String: String]? = nil,
        onLine: (String) -> Void
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let reader = pipe.fileHandleForReading
        var buffer = Data()
        let newline: UInt8 = 0x0A

        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break } // EOF
            buffer.append(chunk)
            while let idx = buffer.firstIndex(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<idx)
                buffer.removeSubrange(buffer.startIndex...idx)
                if let line = String(data: lineData, encoding: .utf8) {
                    onLine(line)
                }
            }
        }
        // Flush any trailing partial line.
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8),
           !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onLine(line)
        }

        process.waitUntilExit()
        return Result(exitCode: process.terminationStatus, timedOut: false)
    }
}

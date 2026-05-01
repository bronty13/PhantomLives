import Foundation
import Testing
@testable import MessagesExporterGUI

/// Coverage for the pure-function pieces of the GUI: argument formatting
/// (must match the CLI's accepted date grammar) and stdout-line parsing
/// (the [N/5] markers and run-folder capture). The runner's actual
/// process-spawning is integration territory — we don't test that here.

@Suite("ExportRequest")
struct ExportRequestTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ m: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = m
        c.timeZone = TimeZone.current
        return Calendar.current.date(from: c)!
    }

    @Test("argumentList includes contact, dates, output, and emoji")
    func fullArgList() {
        let req = ExportRequest(
            contact: "Sallie",
            start: date(2026, 4, 26, 15, 55),
            end:   date(2026, 4, 26, 17, 0),
            outputDir: URL(fileURLWithPath: "/Users/me/Downloads"),
            emoji: .word,
            mode: .sanitized
        )
        #expect(req.argumentList() == [
            "Sallie",
            "--start", "2026-04-26 15:55",
            "--end",   "2026-04-26 17:00",
            "--output", "/Users/me/Downloads",
            "--emoji", "word"
        ])
    }

    @Test("nil dates are omitted from the arg list")
    func openEndedRange() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil,
            end:   nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .strip,
            mode: .sanitized
        )
        let args = req.argumentList()
        #expect(args.contains("Jane"))
        #expect(!args.contains("--start"))
        #expect(!args.contains("--end"))
        #expect(args.contains("--emoji"))
        #expect(args.contains("strip"))
        #expect(!args.contains("--raw"))
    }

    @Test("raw mode appends --raw and keeps --emoji (CLI ignores it)")
    func rawMode() {
        let req = ExportRequest(
            contact: "Sallie",
            start: date(2026, 4, 26, 15, 55),
            end:   date(2026, 4, 26, 17, 0),
            outputDir: URL(fileURLWithPath: "/Users/me/Downloads"),
            emoji: .word,
            mode: .raw
        )
        let args = req.argumentList()
        #expect(args.contains("--raw"))
        #expect(args.last == "--raw") // appended last
        // Sanity: still includes the rest of the standard args.
        #expect(args.contains("Sallie"))
        #expect(args.contains("--start"))
        #expect(args.contains("--end"))
        #expect(args.contains("--output"))
        #expect(args.contains("--emoji"))
    }

    @Test("sanitized mode does not include --raw")
    func sanitizedExcludesRaw() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .keep,
            mode: .sanitized
        )
        #expect(!req.argumentList().contains("--raw"))
    }
}

@Suite("ExportRunner parsers")
struct ExportRunnerParserTests {

    @Test("stageNumber recognizes [1/5] through [5/5]")
    func stageMarkers() {
        #expect(ExportRunner.stageNumber(in: "[1/5] Handles for \"Sallie\"...") == 1)
        #expect(ExportRunner.stageNumber(in: "[2/5] Chats: [150, 15]") == 2)
        #expect(ExportRunner.stageNumber(in: "[3/5] 18 messages in range") == 3)
        #expect(ExportRunner.stageNumber(in: "[4/5] Writing to /tmp/out") == 4)
        #expect(ExportRunner.stageNumber(in: "[5/5] Done!") == 5)
    }

    @Test("stageNumber ignores non-progress lines that contain brackets")
    func nonStageBrackets() {
        // A typical sample-caption line from stage 3 contains [000] etc.
        #expect(ExportRunner.stageNumber(in: "      [000] cap='hello'") == nil)
        // Exit summary contains brackets too but no N/5.
        #expect(ExportRunner.stageNumber(in: "Handles   : [+1234567890]") == nil)
        // Out-of-range numbers are ignored — guard against future "[6/5]" garbage.
        #expect(ExportRunner.stageNumber(in: "[6/5] not a real stage") == nil)
        #expect(ExportRunner.stageNumber(in: "[0/5] also not real") == nil)
    }

    @Test("runFolderPath captures the path printed at stage 4")
    func runFolderCapture() {
        let line = "[4/5] Writing to /Users/me/Downloads/Sallie_20260426_172132"
        #expect(ExportRunner.runFolderPath(in: line) == "/Users/me/Downloads/Sallie_20260426_172132")
    }

    @Test("runFolderPath returns nil for other stages")
    func runFolderNonMatch() {
        #expect(ExportRunner.runFolderPath(in: "[1/5] Handles for \"Sallie\"...") == nil)
        #expect(ExportRunner.runFolderPath(in: "[5/5] Done!") == nil)
        #expect(ExportRunner.runFolderPath(in: "Output    : /tmp/somewhere") == nil)
    }

    @Test("runFolderPath trims trailing whitespace")
    func runFolderTrim() {
        #expect(ExportRunner.runFolderPath(in: "[4/5] Writing to /tmp/out   ") == "/tmp/out")
    }
}

@Suite("Full Disk Access probe")
struct FullDiskAccessProbeTests {

    /// Helper: make a temp file containing some bytes and return its path.
    private func tempReadableFile() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-fda-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("file.bin")
        try? Data([0x01, 0x02, 0x03]).write(to: url)
        return url.path
    }

    @Test("missingDB when the file does not exist")
    func missingDB() {
        let bogus = "/tmp/medexp-does-not-exist-\(UUID().uuidString)/chat.db"
        #expect(ExportRunner.probeReadable(path: bogus) == .missingDB)
    }

    @Test("granted when the file is readable")
    func granted() {
        let path = tempReadableFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(ExportRunner.probeReadable(path: path) == .granted)
    }

    @Test("denied when the file exists but cannot be opened")
    func denied() throws {
        // chmod 000 simulates "open will fail" the same way TCC does at the
        // syscall layer (EACCES rather than EPERM, but probeReadable
        // classifies any open/read error as .denied — that's the contract).
        let path = tempReadableFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: path)
            try? FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0],
                                              ofItemAtPath: path)
        // Skip on root — root bypasses POSIX perms and the read would still
        // succeed, breaking the assertion. CI on macOS runs as the user.
        if getuid() == 0 {
            return
        }
        #expect(ExportRunner.probeReadable(path: path) == .denied)
    }

    @Test("messagesDBPath points at ~/Library/Messages/chat.db")
    func canonicalPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ExportRunner.messagesDBPath == "\(home)/Library/Messages/chat.db")
    }

    @Test("bundle identifier matches Info.plist")
    func bundleIdentifier() {
        // If this ever drifts, `tccutil reset` on the wrong ID would
        // silently leave the user's stale entries in place.
        #expect(ExportRunner.bundleIdentifier == "com.bronty13.MessagesExporterGUI")
    }
}

import Foundation
import Testing
@testable import MessagesExporterGUI

/// Coverage for the pure-function pieces of the GUI: argument formatting
/// (must match the CLI's accepted date grammar) and stdout-line parsing
/// (the [N/5] markers and run-folder capture). The runner's actual
/// process-spawning is integration territory — we don't test that here.

@Suite("ExportRequest")
struct ExportRequestTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = m; c.second = s
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
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        #expect(req.argumentList() == [
            "Sallie",
            "--start", "2026-04-26 15:55:00",
            "--end",   "2026-04-26 17:00:00",
            "--output", "/Users/me/Downloads",
            "--emoji", "word"
        ])
    }

    @Test("handles=[] omits --handle (legacy positional path)")
    func handlesEmpty() {
        let req = ExportRequest(
            contact: "Sallie",
            handles: [],
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        #expect(!args.contains("--handle"))
        // Positional contact still goes through unchanged.
        #expect(args.first == "Sallie")
    }

    @Test("single handle is emitted as --handle <value>")
    func handlesSingle() {
        let req = ExportRequest(
            contact: "Sallie",
            handles: ["+15551234567"],
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .raw,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        let idx = args.firstIndex(of: "--handle")
        #expect(idx != nil)
        if let idx { #expect(args[args.index(after: idx)] == "+15551234567") }
        // Contact and --raw still pass through — the picker can run
        // independently of every other flag.
        #expect(args.first == "Sallie")
        #expect(args.contains("--raw"))
    }

    @Test("multiple handles are comma-joined for the CLI")
    func handlesMultiple() {
        let req = ExportRequest(
            contact: "Sallie",
            handles: ["+15551234567", "alice@example.com"],
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        if let idx = args.firstIndex(of: "--handle") {
            // No spaces in the joined value — otherwise the shell could
            // split it into adjacent argv slots and the CLI would
            // misparse the second handle as an unknown option.
            #expect(args[args.index(after: idx)] == "+15551234567,alice@example.com")
        } else {
            Issue.record("--handle missing")
        }
    }

    @Test("argumentList preserves seconds for forensic precision")
    func secondsPreserved() {
        let req = ExportRequest(
            contact: "Sallie",
            start: date(2026, 4, 26, 10, 11, 0),
            end:   date(2026, 4, 26, 10, 26, 59),
            outputDir: URL(fileURLWithPath: "/Users/me/Downloads"),
            emoji: .word,
            mode: .raw,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        // The CLI's parse() accepts HH:MM:SS; truncating these to HH:MM
        // would silently drop ~59s on each end of the range — the exact
        // bug this regression catches.
        #expect(args.contains("2026-04-26 10:11:00"))
        #expect(args.contains("2026-04-26 10:26:59"))
    }

    @Test("nil dates are omitted from the arg list")
    func openEndedRange() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil,
            end:   nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .strip,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
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
            mode: .raw,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        #expect(args.contains("--raw"))
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
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        #expect(!req.argumentList().contains("--raw"))
    }

    @Test("transcribe off omits --transcribe and --transcribe-model")
    func transcribeOff() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        #expect(!args.contains("--transcribe"))
        #expect(!args.contains("--transcribe-model"))
    }

    @Test("transcribe on appends --transcribe and the chosen model")
    func transcribeOnTurbo() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: true,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        #expect(args.contains("--transcribe"))
        // Model arg lives next to --transcribe-model in the array.
        if let idx = args.firstIndex(of: "--transcribe-model") {
            #expect(args[args.index(after: idx)] == "turbo")
        } else {
            Issue.record("--transcribe-model not present")
        }
    }

    @Test("transcribe on with non-default model passes it through")
    func transcribeOnLarge() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .raw,
            transcribe: true,
            transcribeModel: .large
        )
        let args = req.argumentList()
        #expect(args.contains("--transcribe"))
        #expect(args.contains("large"))
        #expect(args.contains("--raw"))   // raw + transcribe compose
    }

    @Test("WhisperModel rawValues match CLI choices")
    func whisperRawValues() {
        // The CLI's `WHISPER_MODELS` list is the source of truth; the
        // GUI enum mirrors it. If a value gets renamed on the CLI side,
        // this catches it locally before the CLI rejects the run.
        let expected: Set<String> = ["tiny", "base", "small",
                                     "medium", "large", "turbo"]
        let actual = Set(WhisperModel.allCases.map { $0.rawValue })
        #expect(actual == expected)
    }

    @Test("debug true appends --debug")
    func debugOn() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo,
            debug: true
        )
        #expect(req.argumentList().contains("--debug"))
    }

    @Test("debug false (default) omits --debug")
    func debugOff() {
        let req = ExportRequest(
            contact: "Jane",
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        #expect(!req.argumentList().contains("--debug"))
    }
}

@Suite("SendersService")
struct SendersServiceTests {

    @Test("normalize email lowercases without stripping characters")
    func emailLowercased() {
        #expect(SendersService.normalize(handle: "Alice@Example.COM") == "alice@example.com")
    }

    @Test("normalize phone keeps last 10 digits, drops formatting")
    func phoneTrailing10() {
        // Matches the CLI's `norm()` so a US number stored as
        // "+15551234567" lines up with an AddressBook entry written as
        // "(555) 123-4567" → both normalize to "5551234567".
        #expect(SendersService.normalize(handle: "+15551234567") == "5551234567")
        #expect(SendersService.normalize(handle: "(555) 123-4567") == "5551234567")
    }

    @Test("normalize short numbers (shortcodes) returns the digits verbatim")
    func phoneShort() {
        // 5-digit business shortcodes don't get padded; they keep their
        // length. The key won't collide with a real phone because of
        // length, but it should be deterministic.
        #expect(SendersService.normalize(handle: "62268") == "62268")
    }

    @Test("enumerate(chatDB:) returns a diagnostic when the file is missing")
    func chatDBMissing() {
        let bogus = URL(fileURLWithPath: "/tmp/medexp-nodb-\(UUID().uuidString)/chat.db")
        let result = SendersService.enumerate(chatDB: bogus)
        #expect(result.senders.isEmpty)
        #expect(result.diagnostic?.contains("chat.db") == true)
    }
}

@Suite("RangeResolver")
struct RangeResolverTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = m; c.second = s
        c.timeZone = TimeZone.current
        return Calendar.current.date(from: c)!
    }

    private func seconds(of d: Date) -> Int {
        Calendar.current.component(.second, from: d)
    }

    @Test("setSeconds replaces the second component without rolling minutes")
    func setSecondsInPlace() {
        let base = date(2026, 5, 12, 10, 12, 34)
        let zeroed  = RangeResolver.setSeconds(0,  on: base)
        let max     = RangeResolver.setSeconds(59, on: base)
        #expect(seconds(of: zeroed) == 0)
        #expect(seconds(of: max)    == 59)
        // Minute must not advance — Calendar.date(bySetting:) would have
        // jumped to the next 10:13:00 when asked for second=0; we use a
        // dateComponents-based replace specifically to avoid that.
        #expect(Calendar.current.component(.minute, from: zeroed) == 12)
        #expect(Calendar.current.component(.minute, from: max)    == 12)
    }

    @Test("setSeconds clamps out-of-range values")
    func setSecondsClamp() {
        let base = date(2026, 5, 12, 10, 12, 0)
        #expect(seconds(of: RangeResolver.setSeconds(-5,  on: base)) == 0)
        #expect(seconds(of: RangeResolver.setSeconds(120, on: base)) == 59)
    }

    @Test("resolvedStart applies the SS stepper and subtracts 60s when buffer is on")
    func resolvedStartBuffered() {
        // User picked 10:12 in the HH:MM picker, left SS at 0.
        let pick = date(2026, 5, 12, 10, 12, 0)
        let buffered = RangeResolver.resolvedStart(
            picker: pick, seconds: 0, expandStartByOneMinute: true)
        // Buffer reaches one minute earlier so Messages.app's rounded
        // display (10:11:45 → "10:12") still falls inside the window.
        #expect(buffered == date(2026, 5, 12, 10, 11, 0))
    }

    @Test("resolvedStart leaves the picker alone when buffer is off")
    func resolvedStartUnbuffered() {
        let pick = date(2026, 5, 12, 10, 12, 0)
        let raw = RangeResolver.resolvedStart(
            picker: pick, seconds: 15, expandStartByOneMinute: false)
        #expect(raw == date(2026, 5, 12, 10, 12, 15))
    }

    @Test("resolvedEnd applies the SS stepper without any forward cushion")
    func resolvedEndNoCushion() {
        let pick = date(2026, 5, 12, 10, 26, 0)
        let end = RangeResolver.resolvedEnd(picker: pick, seconds: 59)
        // No buffer on the trailing side — over-extending would pull in
        // messages from after the user's chosen window, which the user
        // can plainly see they didn't want.
        #expect(end == date(2026, 5, 12, 10, 26, 59))
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

@Suite("ExportRunner processLine")
@MainActor
struct ProcessLineTests {

    @Test("processLine appends a normal line")
    func appendsLine() {
        let runner = ExportRunner()
        runner.processLine("hello", replacesLast: false)
        runner.processLine("world", replacesLast: false)
        #expect(runner.logLines == ["hello", "world"])
    }

    @Test("processLine with replacesLast:true overwrites the previous line")
    func replacesLastLine() {
        let runner = ExportRunner()
        runner.processLine("initial", replacesLast: false)
        runner.processLine("overwrite", replacesLast: true)
        #expect(runner.logLines == ["overwrite"])
    }

    @Test("replacesLast:true on an empty log falls back to append")
    func replacesLastWhenEmpty() {
        let runner = ExportRunner()
        runner.processLine("first", replacesLast: true)
        #expect(runner.logLines == ["first"])
    }

    @Test("stage advances when the line contains [N/5]")
    func stageAdvancesViaProcessLine() {
        let runner = ExportRunner()
        runner.processLine("[3/5] Reading messages", replacesLast: false)
        #expect(runner.stage == 3)
    }
}

@Suite("RunStats parsers")
struct RunStatsTests {

    @Test("messageCount captures the integer after [3/5]")
    func messageCountStandard() {
        #expect(RunStats.messageCount(in: "[3/5] 4812 messages in range") == 4812)
        #expect(RunStats.messageCount(in: "[3/5] 0 messages in range") == 0)
    }

    @Test("messageCount returns nil for non-stage-3 lines")
    func messageCountWrongStage() {
        #expect(RunStats.messageCount(in: "[2/5] Chats: [150]") == nil)
        #expect(RunStats.messageCount(in: "      [000] cap='hello'") == nil)
        #expect(RunStats.messageCount(in: "Output    : /tmp/somewhere") == nil)
    }

    @Test("formatBytes renders nil as em-dash")
    func bytesNil() {
        #expect(RunStats.formatBytes(nil) == "—")
    }

    @Test("formatBytes renders sizes via ByteCountFormatter")
    func bytesPositive() {
        // ByteCountFormatter's exact spacing varies by macOS version
        // (regular vs. NBSP) but both contain the unit + value.
        let s = RunStats.formatBytes(1_500_000_000)
        #expect(s.contains("GB"))
        #expect(s.contains("1"))
    }

    @Test("formatSpan picks the largest unit that's >= 1")
    func spanUnits() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let plus16d = cal.date(byAdding: .day,    value: 16, to: start)!
        let plus3h  = cal.date(byAdding: .hour,   value: 3,  to: start)!
        let plus5m  = cal.date(byAdding: .minute, value: 5,  to: start)!
        #expect(RunStats.formatSpan(start: start, end: plus16d) == "16d")
        #expect(RunStats.formatSpan(start: start, end: plus3h)  == "3h")
        #expect(RunStats.formatSpan(start: start, end: plus5m)  == "5m")
    }

    @Test("formatSpan returns em-dash for missing or inverted ranges")
    func spanInvalid() {
        #expect(RunStats.formatSpan(start: nil, end: Date()) == "—")
        let d = Date()
        #expect(RunStats.formatSpan(start: d, end: d) == "—")
    }

    @Test("formatInt groups thousands; nil → em-dash")
    func intFormat() {
        #expect(RunStats.formatInt(nil) == "—")
        // Locale-dependent — but the digits show up.
        let s = RunStats.formatInt(4812)
        #expect(s.contains("4"))
        #expect(s.contains("812"))
    }

    @Test("decodeMetadata reads counts from a CLI-style payload")
    func decodeMetadata() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-meta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload: [String: Any] = [
            "summary": [
                "messages": 18,
                "photos": 4,
                "videos": 1,
                "voice":  2
            ],
            "messages": [
                ["attachments": [["x": 1], ["x": 2]]],
                ["attachments": [["x": 3]]],
                ["attachments": []]
            ]
        ]
        let url = dir.appendingPathComponent("metadata.json")
        try JSONSerialization.data(withJSONObject: payload).write(to: url)

        let stats = RunStats.decodeMetadata(at: url)
        #expect(stats?.messageCount    == 18)
        #expect(stats?.attachmentCount == 3)
        #expect(stats?.photoCount      == 4)
        #expect(stats?.videoCount      == 1)
        #expect(stats?.voiceCount      == 2)
    }

    @Test("decodeMetadata falls back to messages array length when summary absent")
    func decodeMetadataNoSummary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-meta-nosum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("metadata.json")
        let payload: [String: Any] = [
            "messages": [
                ["attachments": []],
                ["attachments": [["x": 1]]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)

        let stats = RunStats.decodeMetadata(at: url)
        #expect(stats?.messageCount == 2)
        #expect(stats?.attachmentCount == 1)
    }

    @Test("decodeMetadata returns nil for missing or junk files")
    func decodeMetadataMissing() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(RunStats.decodeMetadata(at: bogus) == nil)
    }

    @Test("computeOutputBytes sums regular file sizes under a folder")
    func outputBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-bytes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let nested = dir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1024)
            .write(to: dir.appendingPathComponent("a.bin"))
        try Data(repeating: 0xCD, count: 2048)
            .write(to: nested.appendingPathComponent("b.bin"))

        let total = RunStats.computeOutputBytes(folder: dir)
        // Allocated size rounds up to filesystem block size, so we assert
        // a lower bound rather than equality.
        #expect(total >= 3072)
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

/// Coverage for the PATH augmentation that fixes the .app-launched-from-
/// Finder bug where /opt/homebrew/bin is missing and transcribe.py's
/// `subprocess.run(["brew", ...])` calls die with FileNotFoundError.
@Suite("ExportRunner.augmentedPATH")
struct AugmentedPATHTests {

    @Test("prepends /opt/homebrew/bin even when existing PATH is the minimal LaunchServices set")
    func injectsHomebrewIntoLaunchServicesPATH() {
        let augmented = ExportRunner.augmentedPATH(
            existing: "/usr/bin:/bin:/usr/sbin:/sbin"
        )
        // The .app launched from Finder lands with this exact PATH, so the
        // augmented version MUST surface /opt/homebrew/bin or transcribe.py
        // can't find brew/ffmpeg. This is the regression-guard for the
        // reboot-broke-transcription incident.
        let parts = augmented.split(separator: ":")
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/usr/local/bin"))
        // Original entries must still survive in the same relative order
        // so a user with custom PATH tweaks doesn't lose them.
        #expect(parts.contains("/usr/bin"))
        #expect(parts.contains("/bin"))
    }

    @Test("homebrew entries appear before /usr/bin so brew python wins over CommandLineTools 3.9")
    func brewBeatsCommandLineTools() {
        let augmented = ExportRunner.augmentedPATH(
            existing: "/usr/bin:/bin"
        )
        let parts = augmented.split(separator: ":").map(String.init)
        let brewIdx = parts.firstIndex(of: "/opt/homebrew/bin")
        let usrBinIdx = parts.firstIndex(of: "/usr/bin")
        #expect(brewIdx != nil)
        #expect(usrBinIdx != nil)
        if let brewIdx, let usrBinIdx { #expect(brewIdx < usrBinIdx) }
    }

    @Test("no duplicates when /opt/homebrew/bin is already present")
    func idempotent() {
        let augmented = ExportRunner.augmentedPATH(
            existing: "/opt/homebrew/bin:/usr/bin:/bin"
        )
        let parts = augmented.split(separator: ":")
        let brewCount = parts.filter { $0 == "/opt/homebrew/bin" }.count
        #expect(brewCount == 1)
    }

    @Test("nil existing PATH still produces a usable string")
    func nilInputStillUsable() {
        let augmented = ExportRunner.augmentedPATH(existing: nil)
        let parts = augmented.split(separator: ":")
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/usr/local/bin"))
    }

    @Test("empty existing PATH still produces a usable string")
    func emptyInputStillUsable() {
        let augmented = ExportRunner.augmentedPATH(existing: "")
        let parts = augmented.split(separator: ":")
        #expect(parts.contains("/opt/homebrew/bin"))
    }
}

/// Coverage for the line-classification helpers that detect transcription
/// failures inside the CLI's stream. These predicates are what turn a
/// silent "Done" pill into the user-visible "Last run reported a problem"
/// banner — wrong classification is the bug we're guarding against.
@Suite("Transcription failure detection")
struct TranscribeFailureDetectionTests {

    @Test("recognizes a TRANSCRIBE_FAILED marker")
    func detectsMarker() {
        let line = #"2026-05-14T11:28:00 TRANSCRIBE_FAILED attachment=msg.m4a model=turbo duration_s=0.42 error="ffmpeg not found""#
        #expect(ExportRunner.lineIsTranscribeFailedMarker(line))
    }

    @Test("ignores benign lines mentioning 'transcribe' but not the marker")
    func ignoresBenignTranscribeLines() {
        #expect(!ExportRunner.lineIsTranscribeFailedMarker("[transcribe] foo.m4a (model=turbo, this may take a minute…)"))
        #expect(!ExportRunner.lineIsTranscribeFailedMarker("       [whisper] writing transcript.json"))
    }

    @Test("recognizes the Python subprocess bootstrap traceback")
    func detectsBootstrapTraceback() {
        // The exact shape transcribe.py emits when /opt/homebrew/bin is
        // missing from PATH and `subprocess.run(["brew", "install",
        // "ffmpeg"])` blows up inside `_execute_child`. This is what the
        // user saw in the screenshot.
        let line = #"      [whisper]     self._execute_child(args, executable, preexec_fn, close_fds,"#
        #expect(ExportRunner.lineIsTranscribeBootstrapTraceback(line))
    }

    @Test("recognizes a FileNotFoundError from the venv bootstrap")
    func detectsFileNotFoundError() {
        let line = "      [whisper] FileNotFoundError: [Errno 2] No such file or directory: 'brew'"
        #expect(ExportRunner.lineIsTranscribeBootstrapTraceback(line))
    }

    @Test("plain Python tracebacks without the [whisper] prefix do NOT match")
    func ignoresUnrelatedTracebacks() {
        // We only escalate when the prefix marks the line as coming from
        // transcribe.py's subprocess stream; an unrelated traceback in
        // the CLI's own log would otherwise produce a spurious banner.
        let line = "Traceback (most recent call last):"
        #expect(!ExportRunner.lineIsTranscribeBootstrapTraceback(line))
    }

    @Test("classifyTranscribeFailure extracts the error= field")
    func extractsErrorField() {
        let line = #"… TRANSCRIBE_FAILED attachment=msg.m4a model=turbo error="ffmpeg not found""#
        let classified = ExportRunner.classifyTranscribeFailure(in: line)
        #expect(classified.contains("ffmpeg not found"))
    }

    @Test("classifyTranscribeFailure returns a generic message when error= is missing")
    func genericFallback() {
        let line = "… TRANSCRIBE_FAILED attachment=msg.m4a model=turbo"
        let classified = ExportRunner.classifyTranscribeFailure(in: line)
        #expect(classified.contains("see live output"))
    }
}

/// Behavioural test that the runner's `processLine` actually mutates
/// `transcriptFailureCount` when it sees a marker. Runs on the main
/// actor because the runner is @MainActor-isolated.
@MainActor
@Suite("ExportRunner transcript failure counting")
struct TranscribeFailureCountingTests {

    @Test("processLine bumps transcriptFailureCount on each marker")
    func bumpsCount() async {
        let runner = ExportRunner(history: RunHistoryStore())
        #expect(runner.transcriptFailureCount == 0)
        runner.processLine(#"… TRANSCRIBE_FAILED attachment=a.m4a error="x""#)
        runner.processLine(#"… TRANSCRIBE_FAILED attachment=b.m4a error="y""#)
        #expect(runner.transcriptFailureCount == 2)
        #expect(runner.transcriptFailureSummary != nil)
        // Summary is "sticky" to the first failure so the banner doesn't
        // flicker between mid-stream lines.
        #expect(runner.transcriptFailureSummary?.contains("x") == true)
    }

    @Test("processLine bumps count exactly once on a bootstrap traceback line")
    func bumpsOnceForTraceback() async {
        let runner = ExportRunner(history: RunHistoryStore())
        runner.processLine("      [whisper]     self._execute_child(args, executable, preexec_fn, close_fds,")
        #expect(runner.transcriptFailureCount == 1)
        // A second traceback line should NOT double-count.
        runner.processLine("      [whisper] FileNotFoundError: [Errno 2] No such file or directory: 'brew'")
        #expect(runner.transcriptFailureCount == 1)
    }
}

/// Coverage for the per-step probes in TranscriptionPreflightService.
/// The probes shell out to real binaries, so these tests verify only the
/// pure helpers (version parser, candidate path generator) — anything
/// process-y is integration territory.
@Suite("TranscriptionPreflightService helpers")
struct TranscriptionPreflightHelperTests {

    @Test("versionMeets accepts 3.10+")
    func acceptsTenAndAbove() {
        #expect(TranscriptionPreflightService.versionMeets("3.10.0", minMajor: 3, minMinor: 10))
        #expect(TranscriptionPreflightService.versionMeets("3.12.5", minMajor: 3, minMinor: 10))
        #expect(TranscriptionPreflightService.versionMeets("3.14.5", minMajor: 3, minMinor: 10))
    }

    @Test("versionMeets rejects 3.9 (CommandLineTools)")
    func rejectsCommandLineTools() {
        #expect(!TranscriptionPreflightService.versionMeets("3.9.6", minMajor: 3, minMinor: 10))
    }

    @Test("versionMeets tolerates pre-release suffixes")
    func handlesPrereleases() {
        // Homebrew sometimes serves "3.13.0rc1" pre-final.
        #expect(TranscriptionPreflightService.versionMeets("3.13.0rc1", minMajor: 3, minMinor: 10))
    }

    @Test("versionMeets rejects malformed input")
    func rejectsGarbage() {
        #expect(!TranscriptionPreflightService.versionMeets("", minMajor: 3, minMinor: 10))
        #expect(!TranscriptionPreflightService.versionMeets("not.a.version", minMajor: 3, minMinor: 10))
    }

    @Test("transcribeScriptCandidates includes the default path")
    func defaultCandidate() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = TranscriptionPreflightService.transcribeScriptCandidates()
        #expect(candidates.contains("\(home)/Documents/GitHub/PhantomLives/transcribe/transcribe.py"))
    }

    @Test("PipeLineBuffer joins lines across chunk boundaries")
    func bufferJoinsAcrossChunks() {
        // Pip output in real life arrives as multi-line chunks where the
        // last bytes of a chunk don't end in \n. The old implementation
        // appended those partial tails as if they were full lines and
        // lost the rest — which is what made the user think their
        // working install had failed. Verify the new buffer reassembles
        // them correctly.
        let buf = PipeLineBuffer()
        let first  = "Collecting mlx-whisper>=0.4.0\nUsing cached mlx_whi".data(using: .utf8)!
        let second = "sper-0.4.3-py3-none-any.whl\nSuccessfully installed".data(using: .utf8)!

        let lines1 = buf.append(first)
        #expect(lines1 == ["Collecting mlx-whisper>=0.4.0"])

        let lines2 = buf.append(second)
        #expect(lines2 == ["Using cached mlx_whisper-0.4.3-py3-none-any.whl"])

        // The unfinished "Successfully installed" remains in the buffer
        // until drained.
        #expect(buf.drainTrailing() == "Successfully installed")
    }

    @Test("PipeLineBuffer handles CRLF as a single line terminator")
    func bufferCRLF() {
        let buf = PipeLineBuffer()
        let data = "line1\r\nline2\r\n".data(using: .utf8)!
        #expect(buf.append(data) == ["line1", "line2"])
        #expect(buf.drainTrailing() == nil)
    }

    @Test("PipeLineBuffer returns nil on empty drain")
    func bufferEmptyDrain() {
        let buf = PipeLineBuffer()
        #expect(buf.drainTrailing() == nil)
    }

    @Test("requiredPipPackages includes transcribe.py's full REQUIRED_PACKAGES list")
    func requiredPackagesMatchTranscribePy() async {
        // transcribe.py's bootstrap will re-run `pip install` (and
        // intermittently fail on PyPI flakiness) whenever any of its
        // REQUIRED_PACKAGES is missing from the venv. This test pins
        // the GUI's install list to match — drift here causes flaky
        // mid-export transcription failures even after a "successful"
        // setup wizard run.
        let pipPackageNames = TranscriptionPreflightService.requiredPipPackages
            .map { $0.split(separator: ">", omittingEmptySubsequences: true).first.map(String.init) ?? $0 }
        #expect(pipPackageNames.contains("mlx"))
        #expect(pipPackageNames.contains("mlx-whisper"))
        #expect(pipPackageNames.contains("mlx-lm"))
        #expect(pipPackageNames.contains("truststore"))
    }

    @Test("requiredImports maps 1:1 to requiredPipPackages")
    func importsMapToPipPackages() {
        // The verification probe imports each module in requiredImports.
        // If the two lists drift, we'll either install a package and not
        // verify it (silent partial install) or verify a module we never
        // installed (false negative). Both bugs have happened in this
        // project's history — this test locks the invariant down.
        let pipNames = TranscriptionPreflightService.requiredPipPackages
            .map { $0.split(separator: ">", omittingEmptySubsequences: true).first.map(String.init) ?? $0 }
            .map { $0.replacingOccurrences(of: "-", with: "_") }
        let imports = TranscriptionPreflightService.requiredImports
        #expect(Set(pipNames) == Set(imports),
                "pip names \(pipNames) and import names \(imports) don't match")
    }

    @Test("venvDir() and venvPython() agree on the canonical layout")
    func venvLayout() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = TranscriptionPreflightService.venvDir()
        #expect(dir == "\(home)/Documents/GitHub/PhantomLives/transcribe/.venv")
        // venvPython() is nil iff the binary doesn't exist on this system;
        // when it returns non-nil, it must point inside `dir`.
        if let py = TranscriptionPreflightService.venvPython() {
            #expect(py.hasPrefix(dir))
            #expect(py.hasSuffix("/bin/python"))
        }
    }
}

/// Verifies the master kill-switch path: when the master flag is off,
/// the request handed to the runner must NEVER contain `--transcribe`,
/// regardless of the per-run toggle's stored value. The check lives at
/// the ExportRequest level so the contract is tested without spinning
/// up a SwiftUI view.
@Suite("Transcription master kill switch")
struct TranscribeMasterKillSwitchTests {

    @Test("transcribe=false omits --transcribe entirely")
    func skipsFlagWhenOff() {
        let req = ExportRequest(
            contact: "Sallie",
            handles: [],
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo
        )
        let args = req.argumentList()
        #expect(!args.contains("--transcribe"))
        #expect(!args.contains("--transcribe-model"))
    }

    @Test("transcribe=true emits the flag + model")
    func emitsFlagWhenOn() {
        let req = ExportRequest(
            contact: "Sallie",
            handles: [],
            start: nil, end: nil,
            outputDir: URL(fileURLWithPath: "/tmp/out"),
            emoji: .word,
            mode: .sanitized,
            transcribe: true,
            transcribeModel: .medium
        )
        let args = req.argumentList()
        #expect(args.contains("--transcribe"))
        let modelIdx = args.firstIndex(of: "--transcribe-model")
        #expect(modelIdx != nil)
        if let modelIdx { #expect(args[args.index(after: modelIdx)] == "medium") }
    }
}

/// Coverage for the user-facing setup phase model. These tests pin
/// what the wizard shows to the user — getting captions or progress
/// fractions wrong silently is a UX regression, so we lock them down.
@Suite("PreflightSetupPhase")
struct PreflightSetupPhaseTests {

    @Test("captions are friendly (no jargon in any non-failure caption)")
    func captionsAreUserFacing() {
        let phases: [PreflightSetupPhase] = [
            .none, .checkingFfmpeg, .installingFfmpeg, .checkingVenv,
            .rebuildingVenv, .creatingVenv, .refreshingPip,
            .installingEngine, .verifying, .finishedOK
        ]
        // We can't enforce friendliness exhaustively but we CAN catch
        // accidental jargon regressions for the words we know about:
        // pip / mlx-whisper / venv leaking into the primary view is a
        // failure mode. ".finishedFailed" is allowed to mention pip
        // because we recommend rebuilding the venv in some messages.
        for phase in phases {
            let lower = phase.caption.lowercased()
            #expect(!lower.contains("pip"),
                    "phase \(phase) leaks 'pip' into the user-facing caption: \(phase.caption)")
            #expect(!lower.contains("mlx-whisper") && !lower.contains("mlx_whisper"),
                    "phase \(phase) leaks 'mlx-whisper' into the user-facing caption: \(phase.caption)")
        }
    }

    @Test("progress fractions are monotonic across the happy path")
    func progressIsMonotonic() {
        // The progress bar should always move forward through the
        // workflow — a step that goes backwards is visually jarring
        // even though the underlying probe takes longer.
        let happyPath: [PreflightSetupPhase] = [
            .checkingFfmpeg, .installingFfmpeg, .checkingVenv,
            .creatingVenv, .refreshingPip, .installingEngine,
            .verifying, .finishedOK
        ]
        var last: Double = 0
        for phase in happyPath {
            #expect(phase.progress >= last,
                    "phase \(phase) progress \(phase.progress) is lower than previous \(last)")
            last = phase.progress
        }
        #expect(happyPath.last?.progress == 1.0)
    }

    @Test("terminal states identify themselves correctly")
    func terminalDetection() {
        #expect(PreflightSetupPhase.finishedOK.isTerminal)
        #expect(PreflightSetupPhase.finishedFailed(reason: "x").isTerminal)
        #expect(!PreflightSetupPhase.installingEngine.isTerminal)
        #expect(!PreflightSetupPhase.none.isTerminal)
    }

    @Test("failure carries the user-facing reason verbatim")
    func failureCarriesReason() {
        let phase = PreflightSetupPhase.finishedFailed(
            reason: "Couldn't reach PyPI. Check your internet.")
        #expect(phase.caption.contains("Couldn't reach PyPI"))
        #expect(phase.isFailure)
    }
}

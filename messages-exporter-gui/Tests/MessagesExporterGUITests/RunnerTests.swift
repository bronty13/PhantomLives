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
            emoji: .word
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
            emoji: .strip
        )
        let args = req.argumentList()
        #expect(args.contains("Jane"))
        #expect(!args.contains("--start"))
        #expect(!args.contains("--end"))
        #expect(args.contains("--emoji"))
        #expect(args.contains("strip"))
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

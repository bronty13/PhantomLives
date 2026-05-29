import Foundation
import Testing
@testable import PurpleVoice

@Suite("CLI argument parsing")
struct CLITests {

    @Test("parseTrim accepts both-bounded form")
    func parseTrimBothBounds() {
        let r = CLI.parseTrim("1.5:30.0")
        #expect(r?.start == 1.5)
        #expect(r?.end == 30.0)
    }

    @Test("parseTrim accepts start-only and end-only forms")
    func parseTrimOneSided() {
        let onlyEnd = CLI.parseTrim(":15")
        #expect(onlyEnd?.start == nil)
        #expect(onlyEnd?.end == 15)

        let onlyStart = CLI.parseTrim("5:")
        #expect(onlyStart?.start == 5)
        #expect(onlyStart?.end == nil)
    }

    @Test("parseTrim rejects malformed input")
    func parseTrimRejectsMalformed() {
        #expect(CLI.parseTrim("foo") == nil)            // no colon
        #expect(CLI.parseTrim("abc:5") == nil)          // non-numeric start
        #expect(CLI.parseTrim("5:xyz") == nil)          // non-numeric end
        #expect(CLI.parseTrim("10:5") == nil)           // start >= end
        #expect(CLI.parseTrim("5:5") == nil)            // zero-length
    }

    @Test("AppDelegate.isCLICommand recognizes the documented subcommands")
    func isCLICommandDispatchTable() {
        for cmd in ["clean", "help", "version",
                    "-h", "--help", "-v", "--version"] {
            #expect(AppDelegate.isCLICommand(cmd),
                    "\(cmd) should route to CLI")
        }
        for other in ["", "-NSDocumentRevisionsDebugMode",
                      "/some/random/file.m4a", "launch"] {
            #expect(!AppDelegate.isCLICommand(other),
                    "\(other) should NOT route to CLI (would steal Finder launches)")
        }
    }
}

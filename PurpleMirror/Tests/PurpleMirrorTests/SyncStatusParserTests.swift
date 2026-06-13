import Testing
import Foundation
@testable import PurpleMirror

@Suite struct SyncStatusParserTests {

    @Test func parseLogLineExtractsCountAndDestination() {
        let line = "2026-06-13 14:26:22  Mirrored 442 markdown files → /Users/b/ObsidianVault/Cheetah/PhantomLives"
        let e = SyncStatusParser.parseLogLine(line)
        #expect(e.fileCount == 442)
        #expect(e.destination == "/Users/b/ObsidianVault/Cheetah/PhantomLives")
        #expect(e.date != nil)
    }

    @Test func parseLastLogLinePicksMostRecent() {
        let log = """
        2026-06-13 13:38:48  Mirrored 441 markdown files → /a/b
        some noise line
        2026-06-13 14:26:22  Mirrored 442 markdown files → /a/b
        """
        #expect(SyncStatusParser.parseLastLogLine(log)?.fileCount == 442)
    }

    @Test func parseLastLogLineNilWhenNoMirrorLine() {
        #expect(SyncStatusParser.parseLastLogLine("just some startup noise\n") == nil)
    }

    @Test func parseAgentStateReadsRunsAndExit() {
        let out = "\tstate = not running\n\truns = 7\n\tlast exit code = 0"
        let s = SyncStatusParser.parseAgentState(out, launchctlSucceeded: true)
        #expect(s.loaded)
        #expect(s.runs == 7)
        #expect(s.lastExitCode == 0)
    }

    @Test func parseAgentStateNeverExitedLeavesExitNil() {
        let out = "\truns = 1\n\tlast exit code = (never exited)"
        let s = SyncStatusParser.parseAgentState(out, launchctlSucceeded: true)
        #expect(s.runs == 1)
        #expect(s.lastExitCode == nil)
    }

    @Test func notLoadedWhenLaunchctlFails() {
        let s = SyncStatusParser.parseAgentState("Could not find service", launchctlSucceeded: false)
        #expect(!s.loaded)
    }

    @Test func humanizeInterval() {
        #expect(SyncStatusParser.humanizeInterval(900) == "15 min")
        #expect(SyncStatusParser.humanizeInterval(3600) == "1 hr")
        #expect(SyncStatusParser.humanizeInterval(9000) == "2 hr 30 min")
        #expect(SyncStatusParser.humanizeInterval(0) == "—")
    }

    @Test func relativeAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SyncStatusParser.relativeAge(of: nil, now: now) == "never")
        #expect(SyncStatusParser.relativeAge(of: now.addingTimeInterval(-120), now: now) == "2 min ago")
        #expect(SyncStatusParser.relativeAge(of: now.addingTimeInterval(-7200), now: now) == "2 hr ago")
    }

    @Test func healthClassification() {
        #expect(SyncStatusParser.health(agentLoaded: true, lastExitCode: 0, isSyncing: false) == .healthy)
        #expect(SyncStatusParser.health(agentLoaded: true, lastExitCode: 1, isSyncing: false) == .error)
        #expect(SyncStatusParser.health(agentLoaded: false, lastExitCode: 0, isSyncing: false) == .warning)
        #expect(SyncStatusParser.health(agentLoaded: true, lastExitCode: 0, isSyncing: true) == .running)
    }
}

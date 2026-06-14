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

    @Test func healthSeverityOrder() {
        #expect(SyncStatusParser.Health.error.severity > SyncStatusParser.Health.warning.severity)
        #expect(SyncStatusParser.Health.warning.severity > SyncStatusParser.Health.running.severity)
        #expect(SyncStatusParser.Health.running.severity > SyncStatusParser.Health.healthy.severity)
    }
}

/// Unified log → ``SyncStatusParser/LogSummary`` parsing across job kinds.
@Suite struct LogSummaryTests {

    @Test func obsidianSummary() {
        let log = "2026-06-13 14:26:22  Mirrored 442 markdown files → /Users/b/Vault/PhantomLives"
        let s = SyncStatusParser.summary(log, kind: .obsidian)
        #expect(s?.headline == "Mirrored 442 files")
        #expect(s?.ok == true)
        #expect(s?.detail == "PhantomLives")          // last path component of the destination
    }

    @Test func obsidianSummarySingularFile() {
        let s = SyncStatusParser.obsidianSummary("2026-06-13 14:26:22  Mirrored 1 markdown files → /a/b")
        #expect(s?.headline == "Mirrored 1 file")
    }

    @Test func purpleAtticStagedWins() {
        // The staged line comes after pull exit 0 in the same run → it wins.
        let log = """
        2026-06-13 17:25:16 pull exit: 0  — local files: 42966, size: 241G
        2026-06-13 17:25:18 staged 2 NEW file(s) for review → /x/NEW PHOTOS TO REVIEW/20260613-172517
        2026-06-13 17:25:19 === sync done ===
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Staged 2 new items")
        #expect(s?.ok == true)
        #expect(s?.detail == "42,966 files · 241G")
    }

    @Test func purpleAtticNoNewItems() {
        let log = """
        2026-06-13 16:32:02 pull exit: 0  — local files: 42964, size: 241G
        2026-06-13 16:32:09 no new items this run — nothing to stage for review
        2026-06-13 16:32:09 === sync done ===
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "No new items")
        #expect(s?.ok == true)
        #expect(s?.detail == "42,964 files · 241G")
    }

    @Test func purpleAtticSingularStaged() {
        let log = "2026-06-13 17:25:18 staged 1 NEW file(s) for review → /x/20260613-172517"
        #expect(SyncStatusParser.summary(log, kind: .purpleAtticSync)?.headline == "Staged 1 new item")
    }

    @Test func purpleAtticPullFailure() {
        let log = """
        2026-06-13 05:40:33 pulling RVK → /x
        2026-06-13 05:40:33 pull exit: 12  — local files: 0, size:
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Pull failed (exit 12)")
        #expect(s?.ok == false)
    }

    @Test func purpleAtticStagingActivated() {
        let log = "2026-06-13 11:12:47 initial sync caught up — NEW-items review staging is now ACTIVE (→ /x)"
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Caught up — staging active")
        #expect(s?.ok == true)
    }

    @Test func purpleAtticNilWhenNothingRecognized() {
        #expect(SyncStatusParser.summary("Processing albums.\nDone.\n", kind: .purpleAtticSync) == nil)
    }

    @Test func genericSummaryUsesLastLineMinusTimestamp() {
        let log = "noise\n2026-06-13 09:00:00 something happened here\n"
        let s = SyncStatusParser.summary(log, kind: .generic)
        #expect(s?.headline == "something happened here")
        #expect(s?.date != nil)
        #expect(s?.ok == nil)
    }

    @Test func genericSummaryNilWhenEmpty() {
        #expect(SyncStatusParser.summary("   \n\n", kind: .generic) == nil)
    }

    // A Tier-1 archiver (calls/mail/notes/…) prints a timestamp-less summary line
    // between timestamped "… exit: 0" / "=== sync done ===" markers. That line must
    // become the headline, with a real (non-nil) timestamp from the markers.
    @Test func purpleAtticTier1PrintedSummary() {
        let log = """
        2026-06-14 16:13:22 decrypted sidecar pulled: 404 call(s) with a number
        Call history: +0 new call(s); 404 total.
        2026-06-14 16:13:24 callhistory_archiver exit: 0
        2026-06-14 16:13:24 === sync done ===
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Call history: +0 new call(s); 404 total.")
        #expect(s?.ok == true)
        #expect(s?.date != nil)                                    // not "never"
    }

    @Test func purpleAtticTier1IgnoresRsyncNoise() {
        // Mail's run emits rsync output (timestamp-less) before the real summary;
        // the "… pulled" timestamped line must clear it so only the summary wins.
        let log = """
        2026-06-14 16:22:01 === sync start (Rachel) ===
        building file list ... done
        ./INBOX.mbox/
        2026-06-14 16:22:13 mail tree pulled (rsync rc=0): 3633 .emlx, 600M
        Mail archive: +2 new message(s); 3633 total; 342 attachment(s); 0 unparseable.
        2026-06-14 16:22:20 mail_archiver exit: 0
        2026-06-14 16:22:20 === sync done ===
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Mail archive: +2 new message(s); 3633 total; 342 attachment(s); 0 unparseable.")
        #expect(s?.ok == true)
    }

    @Test func purpleAtticTier1NonZeroExitFails() {
        let log = """
        2026-06-14 16:13:22 pulled 4 reminder store(s)
        Reminders archive: +0 new version(s); 2720 reminders across 6 list(s).
        2026-06-14 16:13:24 reminders_archiver exit: 9
        """
        let s = SyncStatusParser.summary(log, kind: .purpleAtticSync)
        #expect(s?.headline == "Sync failed (exit 9)")
        #expect(s?.ok == false)
    }
}

/// Parsing a launchd plist into an ``AgentDescriptor`` + the safe interval edit.
@Suite struct LaunchAgentPlistTests {

    private var agentDict: [String: Any] {
        [
            "Label": "com.bronty13.external-photo-sync.alpha",
            "ProgramArguments": ["/bin/bash", "/Users/b/Library/Application Support/PurpleAttic/external-photo-sync.sh", "alpha"],
            "StartInterval": 3600,
            "RunAtLoad": false,
            "StandardOutPath": "/Users/b/Library/Logs/PurpleAttic/external-photo-sync-alpha.launchd.log",
            "EnvironmentVariables": ["HOME": "/Users/b", "PATH": "/usr/bin:/bin"],
        ]
    }

    @Test func parseExtractsFields() {
        let d = LaunchAgentPlist.parse(agentDict)
        #expect(d?.label == "com.bronty13.external-photo-sync.alpha")
        #expect(d?.startInterval == 3600)
        #expect(d?.runAtLoad == false)
        #expect(d?.stdoutPath == "/Users/b/Library/Logs/PurpleAttic/external-photo-sync-alpha.launchd.log")
        #expect(d?.environment["HOME"] == "/Users/b")
    }

    @Test func scriptPathSkipsInterpreter() {
        // The first non-/bin//usr/ path is the actual script, not /bin/bash.
        #expect(LaunchAgentPlist.parse(agentDict)?.scriptPath?.hasSuffix("external-photo-sync.sh") == true)
    }

    @Test func parseNilWithoutLabel() {
        #expect(LaunchAgentPlist.parse(["StartInterval": 60]) == nil)
    }

    @Test func withStartIntervalChangesOnlyInterval() {
        let updated = LaunchAgentPlist.withStartInterval(agentDict, seconds: 7200)
        #expect(updated["StartInterval"] as? Int == 7200)
        // Everything else preserved.
        #expect((updated["ProgramArguments"] as? [String])?.count == 3)
        #expect((updated["EnvironmentVariables"] as? [String: String])?["HOME"] == "/Users/b")
        #expect(updated["StandardOutPath"] as? String == agentDict["StandardOutPath"] as? String)
    }
}

/// Job discovery filter + per-label profiles.
@Suite struct JobRegistryTests {

    @Test func shouldManageOnlyRepoNamespaces() {
        #expect(JobRegistry.shouldManage(label: "com.phantomlives.obsidian-sync"))
        #expect(JobRegistry.shouldManage(label: "com.bronty13.external-photo-sync.alpha"))
        #expect(!JobRegistry.shouldManage(label: "com.apple.something"))
        #expect(!JobRegistry.shouldManage(label: "md.obsidian.helper"))
    }

    @Test func knownProfilesAreTailored() {
        let obsidian = JobRegistry.profile(for: descriptor("com.phantomlives.obsidian-sync"))
        #expect(obsidian.displayName == "Obsidian Sync")
        #expect(obsidian.logKind == .obsidian)
        if case .script = obsidian.scheduling {} else { Issue.record("Obsidian should be script-managed") }
    }

    @Test func externalSourceProfilesAreDerivedNotHardcoded() {
        // No source NAME appears in code — display + log path come from the label id.
        let p = JobRegistry.profile(for: descriptor("com.bronty13.external-photo-sync.alpha"))
        #expect(p.displayName == "External Photo Sync — Alpha")
        #expect(p.logKind == .purpleAtticSync)
        #expect(p.scheduling == .plist)
        #expect(p.activityLogPathOverride?.hasSuffix("external-photo-sync-alpha.log") == true)

        let m = JobRegistry.profile(for: descriptor("com.bronty13.external-messages-sync.dad"))
        #expect(m.displayName == "External Messages Sync — Dad")
        #expect(m.activityLogPathOverride?.hasSuffix("external-messages-sync-dad.log") == true)
    }

    @Test func unknownAgentGetsGenericProfile() {
        let p = JobRegistry.profile(for: descriptor("com.bronty13.future-thing"))
        #expect(p.displayName == "Future Thing")
        #expect(p.logKind == .generic)
        #expect(p.scheduling == .plist)
        #expect(p.activityLogPathOverride == nil)
    }

    @Test func displayNamePrettifiesLabels() {
        #expect(JobRegistry.displayName(forLabel: "com.bronty13.disk-cleaner") == "Disk Cleaner")
        #expect(JobRegistry.displayName(forLabel: "com.phantomlives.backup_now") == "Backup Now")
    }

    private func descriptor(_ label: String) -> AgentDescriptor {
        AgentDescriptor(label: label, programArguments: ["/bin/bash", "/x/run.sh"],
                        startInterval: 3600, stdoutPath: "/x/out.log", stderrPath: nil,
                        runAtLoad: false, environment: [:])
    }
}

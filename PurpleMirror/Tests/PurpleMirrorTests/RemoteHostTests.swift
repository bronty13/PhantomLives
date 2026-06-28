import Testing
import Foundation
@testable import PurpleMirror

@Suite struct RemoteHostTests {

    // MARK: SSHCommand — shell quoting

    @Test func shQuoteWrapsAndEscapesSingleQuotes() {
        #expect(SSHCommand.shQuote("simple") == "'simple'")
        #expect(SSHCommand.shQuote("with space") == "'with space'")
        // a single quote becomes  '\''  inside the wrap
        #expect(SSHCommand.shQuote("it's") == "'it'\\''s'")
    }

    // MARK: SSHCommand — local passthrough

    @Test func argvLocalIsVerbatim() {
        let (exe, args) = SSHCommand.argv(for: .local, launchPath: "/bin/launchctl",
                                          args: ["print", "gui/501/com.x"])
        #expect(exe == "/bin/launchctl")
        #expect(args == ["print", "gui/501/com.x"])
    }

    // MARK: SSHCommand — remote wrapping

    @Test func argvRemoteWrapsInSSH() {
        let runner = MonitoredHost.remote(id: "runner", displayName: "Runner",
                                          user: "bronty", host: "10.0.0.50",
                                          identityFile: "~/.ssh/purplemirror_runner")
        let (exe, args) = SSHCommand.argv(for: runner, launchPath: "/bin/launchctl",
                                          args: ["print", "gui/501/com.x"])
        #expect(exe == "/usr/bin/ssh")
        #expect(args.contains("BatchMode=yes"))                 // never prompt
        #expect(args.contains("ConnectTimeout=6"))
        #expect(args.contains("-i"))
        #expect(args.contains("~/.ssh/purplemirror_runner"))
        #expect(args.contains("bronty@10.0.0.50"))              // ssh target
        // the remote command is the quoted launchPath + args as the last element
        #expect(args.last == "'/bin/launchctl' 'print' 'gui/501/com.x'")
        // `--` precedes the destination so a host that looks like an option is safe
        #expect(args.contains("--"))
    }

    @Test func argvRemoteAddsPortOnlyWhenNonStandard() {
        let h = MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h", port: 2222)
        let (_, args) = SSHCommand.argv(for: h, launchPath: "/bin/echo", args: ["hi"])
        #expect(args.contains("-p"))
        #expect(args.contains("2222"))

        let h22 = MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h")  // 22
        let (_, args22) = SSHCommand.argv(for: h22, launchPath: "/bin/echo", args: ["hi"])
        #expect(!args22.contains("-p"))
    }

    // MARK: SSHCommand — remoteBash (Phase 3: schedule control over ssh)

    @Test func remoteBashNoEnvJustQuotesCommand() {
        let cmd = SSHCommand.remoteBash(path: "/x/sync.sh", args: ["--install-agent", "3600"], env: [:])
        #expect(cmd == "'/bin/bash' '/x/sync.sh' '--install-agent' '3600'")
    }

    @Test func remoteBashInlinesEnvSortedAndQuoted() {
        let cmd = SSHCommand.remoteBash(path: "/x/sync.sh", args: ["--install-agent", "1800"],
                                        env: ["OBSIDIAN_VAULT": "/Vols/My Vault", "A": "b"])
        // env sorted (A before OBSIDIAN_VAULT), each value shell-quoted, then the bash command
        #expect(cmd == "A='b' OBSIDIAN_VAULT='/Vols/My Vault' '/bin/bash' '/x/sync.sh' '--install-agent' '1800'")
    }

    @Test func shellArgvLocalUsesShDashC() {
        let (exe, args) = SSHCommand.shellArgv(for: .local, command: "ls ~/Library/LaunchAgents")
        #expect(exe == "/bin/sh")
        #expect(args == ["-c", "ls ~/Library/LaunchAgents"])
    }

    // MARK: MonitoredHost

    @Test func sshTargetOmitsUserWhenEmpty() {
        #expect(MonitoredHost.remote(id: "r", displayName: "R", user: "", host: "host.local").sshTarget == "host.local")
        #expect(MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h").sshTarget == "u@h")
    }

    // MARK: Quick-connect URLs (SSH / SMB / VNC)

    @Test func connectURLsForRemoteHost() {
        let h = MonitoredHost.remote(id: "r", displayName: "R", user: "bronty", host: "10.0.0.77")
        #expect(h.sshURLString == "ssh://bronty@10.0.0.77")
        #expect(h.smbURLString == "smb://bronty@10.0.0.77")
        #expect(h.vncURLString == "vnc://bronty@10.0.0.77")
    }

    @Test func sshURLIncludesNonStandardPortOnly() {
        #expect(MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h", port: 2222)
                    .sshURLString == "ssh://u@h:2222")
        #expect(MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h")  // 22
                    .sshURLString == "ssh://u@h")
        // SMB/VNC don't carry the SSH port
        #expect(MonitoredHost.remote(id: "r", displayName: "R", user: "u", host: "h", port: 2222)
                    .smbURLString == "smb://u@h")
    }

    @Test func connectURLsOmitEmptyUser() {
        let h = MonitoredHost.remote(id: "r", displayName: "R", user: "", host: "host.local")
        #expect(h.sshURLString == "ssh://host.local")
        #expect(h.smbURLString == "smb://host.local")
    }

    @Test func localHostHasNoConnectURLs() {
        #expect(MonitoredHost.local.sshURLString == nil)
        #expect(MonitoredHost.local.smbURLString == nil)
        #expect(MonitoredHost.local.vncURLString == nil)
    }

    // MARK: HostStore

    @Test func storeNormalizationKeepsOneLocalFirst() {
        let remote = MonitoredHost.remote(id: "runner", displayName: "Runner", user: "u", host: "h")
        // even if a duplicate/extra local sneaks in, normalize → exactly one local, first
        let out = HostStore.normalized([remote, .local, .local])
        #expect(out.count == 2)
        #expect(out.first?.isLocal == true)
        #expect(out.last?.id == "runner")
    }

    @Test func hostCodableRoundTrips() throws {
        let h = MonitoredHost.remote(id: "runner", displayName: "Runner", user: "bronty",
                                     host: "10.0.0.50", port: 2200,
                                     identityFile: "~/.ssh/k", connectTimeout: 8)
        let data = try JSONEncoder().encode(h)
        let back = try JSONDecoder().decode(MonitoredHost.self, from: data)
        #expect(back == h)
    }

    // MARK: Backoff (Phase 4: don't hammer an offline host)

    @Test func backoffIntervalGrowsThenCaps() {
        #expect(Backoff.probeInterval(consecutiveFailures: 0) == 1)
        #expect(Backoff.probeInterval(consecutiveFailures: 1) == 2)
        #expect(Backoff.probeInterval(consecutiveFailures: 2) == 3)
        #expect(Backoff.probeInterval(consecutiveFailures: 5) == 6)
        #expect(Backoff.probeInterval(consecutiveFailures: 99) == 6)
    }

    @Test func healthyHostProbesEveryTick() {
        for tick in 1...10 {
            #expect(Backoff.shouldProbe(consecutiveFailures: 0, tick: tick))
        }
    }

    @Test func failingHostProbesOnlyOnItsInterval() {
        // 2 failures → interval 3 → probe on ticks divisible by 3
        #expect(!Backoff.shouldProbe(consecutiveFailures: 2, tick: 4))
        #expect(Backoff.shouldProbe(consecutiveFailures: 2, tick: 6))
        // deep failure → interval 6 → ~once a minute at a 10s tick
        #expect(!Backoff.shouldProbe(consecutiveFailures: 10, tick: 61))
        #expect(Backoff.shouldProbe(consecutiveFailures: 10, tick: 60))
    }

    // MARK: Fleet config (mesh)

    private var sampleFleet: [FleetMachine] {
        [
            FleetMachine(id: "vortex", displayName: "Vortex", computerName: "Vortex MacBook Pro",
                         sshUser: "bronty13", sshHost: "10.0.0.125", port: 22, identityFile: nil),
            FleetMachine(id: "runner", displayName: "Runner", computerName: "Archive Runner",
                         sshUser: "bronty", sshHost: "10.0.0.30", port: 22, identityFile: "~/.ssh/k"),
        ]
    }

    @Test func fleetExcludesSelfByComputerName() {
        // On Vortex, the fleet's remote hosts are everyone EXCEPT Vortex.
        let remotes = FleetStore.remoteHosts(machines: sampleFleet,
                                             localComputerName: "Vortex MacBook Pro", localNodeID: nil)
        #expect(remotes.count == 1)
        #expect(remotes.first?.id == "runner")
        #expect(remotes.first?.fromFleet == true)
        #expect(remotes.first?.sshTarget == "bronty@10.0.0.30")
    }

    @Test func fleetSelfMatchIsCaseInsensitive() {
        let remotes = FleetStore.remoteHosts(machines: sampleFleet,
                                             localComputerName: "vortex macbook pro", localNodeID: nil)
        #expect(!remotes.contains { $0.id == "vortex" })   // still excluded despite case diff
    }

    @Test func fleetNodeIDOverridesSelfMatch() {
        // node-id is the bulletproof self-id: even with a mismatched ComputerName, the entry whose
        // id == node-id is treated as self and excluded.
        let remotes = FleetStore.remoteHosts(machines: sampleFleet,
                                             localComputerName: "irrelevant", localNodeID: "runner")
        #expect(!remotes.contains { $0.id == "runner" })
        #expect(remotes.contains { $0.id == "vortex" })
    }

    @Test func fleetUnknownSelfKeepsAllAsRemote() {
        // A Mac not in the fleet (no name or id match) sees every machine as a remote host.
        let remotes = FleetStore.remoteHosts(machines: sampleFleet,
                                             localComputerName: "Some Other Mac", localNodeID: nil)
        #expect(remotes.count == 2)
        #expect(remotes.allSatisfy { $0.fromFleet })
    }

    @Test func fleetConfigCodableRoundTrips() throws {
        let cfg = FleetConfig(machines: sampleFleet)
        let data = try JSONEncoder().encode(cfg)
        #expect(try JSONDecoder().decode(FleetConfig.self, from: data) == cfg)
    }

    @Test func fleetHostFlagNotPersistedInHostsJSON() throws {
        // fromFleet is transient — it must NOT round-trip through hosts.json encoding.
        var h = MonitoredHost.remote(id: "x", displayName: "X", user: "u", host: "h")
        h.fromFleet = true
        let back = try JSONDecoder().decode(MonitoredHost.self, from: JSONEncoder().encode(h))
        #expect(back.fromFleet == false)   // default, because it's excluded from CodingKeys
    }

    // MARK: LaunchAgentPlist.parse(data:)

    @Test func parsePlistFromXMLData() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>com.bronty13.atw-repost-bot</string>
          <key>ProgramArguments</key><array><string>/bin/zsh</string><string>-lc</string><string>node repost.js</string></array>
          <key>StartInterval</key><integer>3600</integer>
          <key>StandardOutPath</key><string>/Users/x/Library/Logs/atw.log</string>
          <key>RunAtLoad</key><false/>
        </dict></plist>
        """
        let d = try #require(LaunchAgentPlist.parse(data: Data(xml.utf8)))
        #expect(d.label == "com.bronty13.atw-repost-bot")
        #expect(d.startInterval == 3600)
        #expect(d.stdoutPath == "/Users/x/Library/Logs/atw.log")
        #expect(d.programArguments.count == 3)
        #expect(d.runAtLoad == false)
    }

    @Test func parsePlistFromBinaryDataMatchesXML() throws {
        // A binary plist (what `cat` of a real LaunchAgent often returns) parses identically.
        let dict: [String: Any] = [
            "Label": "com.phantomlives.obsidian-sync",
            "ProgramArguments": ["/bin/bash", "/x/sync.sh"],
            "StartInterval": 1800,
        ]
        let bin = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        let d = try #require(LaunchAgentPlist.parse(data: bin))
        #expect(d.label == "com.phantomlives.obsidian-sync")
        #expect(d.startInterval == 1800)
    }

    @Test func parsePlistDataRejectsGarbage() {
        #expect(LaunchAgentPlist.parse(data: Data("not a plist".utf8)) == nil)
    }
}

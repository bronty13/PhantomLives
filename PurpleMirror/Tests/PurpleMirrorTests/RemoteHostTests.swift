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

import ArgumentParser
import Foundation
import PurpleAtticCore

/// `pattic agent …` — sender mode for a second Mac: capture this Mac's Photos to a staging SSD
/// and ship them to a remote PurpleAttic receiver. Export-only; never purges. Lives behind its
/// own subcommand and its own `sender.json`, fully separate from the core archive commands.
struct Agent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Sender mode: export this Mac's Photos to an SSD and ship to a remote receiver.",
        subcommands: [AgentInit.self, AgentPlan.self, AgentRun.self]
    )
}

struct ConfigOption: ParsableArguments {
    @Option(name: .long, help: "Path to a sender config JSON (default: ~/Library/Application Support/PurpleAttic/sender.json).")
    var config: String?

    var url: URL { config.map { URL(fileURLWithPath: $0) } ?? SenderConfig.defaultURL() }

    func load() throws -> SenderConfig {
        guard let c = SenderConfig.load(from: url) else {
            print("No sender config at \(url.path). Create one with `pattic agent init`.")
            throw ExitCode.failure
        }
        return c
    }
}

// MARK: - agent init

struct AgentInit: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Write a starter sender.json you then edit.")
    @OptionGroup var cfg: ConfigOption
    @Flag(name: .long, help: "Overwrite an existing sender config.") var force: Bool = false

    func run() throws {
        if FileManager.default.fileExists(atPath: cfg.url.path) && !force {
            print("Sender config already exists at \(cfg.url.path). Use --force to overwrite.")
            throw ExitCode.failure
        }
        var sample = SenderConfig(name: "Photo Sender",
                                  stagingRoot: "/Volumes/CHANGE_ME_SSD")
        sample.remote = .init(enabled: false, host: "vortex.local", user: "CHANGE_ME",
                              port: 22, identityFile: nil, remotePath: "/Volumes/CHANGE_ME/Photos Archive - Sender")
        try sample.save(to: cfg.url)
        print("Wrote starter sender config to \(cfg.url.path)")
        print("Edit it (stagingRoot = your SSD; remote.* = the receiver), then:")
        print("  pattic agent plan     # preview")
        print("  pattic agent run      # export to SSD + ship")
    }
}

// MARK: - agent plan

struct AgentPlan: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plan", abstract: "Print what the sender would do, running nothing.")
    @OptionGroup var cfg: ConfigOption

    func run() throws {
        let c = try cfg.load()
        let osxphotos = Tooling.osxphotos ?? "osxphotos"
        let rsync = Tooling.rsync ?? "rsync"
        print("Sender: \(c.name)")
        print("Library: \(c.photosLibraryPath ?? "(System Photo Library)")")
        print("Staging (SSD): \(c.stagingRoot)  → \(c.stagingArchiveRoot)")
        print("Formats: \(c.exportProfile().enabledPasses.map { $0.label }.joined(separator: ", "))")
        print("Download-missing: \(c.downloadMissingFromICloud)  (on = pull originals from iCloud)")
        if c.remote.enabled {
            print("Ship → \(c.remote.user)@\(c.remote.host):\(c.remote.remotePath) (port \(c.remote.port))")
        } else {
            print("Ship: DISABLED (export to SSD only)")
        }
        let issues = c.validationIssues()
        if !issues.isEmpty { print("\nIssues:"); issues.forEach { print("  - \($0)") } }
        print("\nosxphotos commands:")
        for pass in c.exportProfile().enabledPasses {
            print("  # \(pass.label)")
            print("  " + ExportPlan.shellCommand(osxphotos: osxphotos, profile: c.exportProfile(), pass: pass, dryRun: false))
        }
        if c.remote.enabled {
            print("\nship command:")
            print("  " + SenderAgent.shipShellCommand(config: c, rsync: rsync))
        }
    }
}

// MARK: - agent run

struct AgentRun: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Export this Mac's Photos to the SSD, then ship to the receiver.")
    @OptionGroup var cfg: ConfigOption
    @Flag(name: .long, help: "Plan the osxphotos pass and skip the ship (touches nothing remote).")
    var dryRun: Bool = false

    func run() throws {
        let c = try cfg.load()
        let logger = AtticLogger(runName: "sender_" + c.name.replacingOccurrences(of: " ", with: "_"), echo: true)
        do {
            let summary = try SenderAgent.run(config: c, logger: logger, dryRun: dryRun)
            if let report = summary.exported.writeReport() { print("\nReport: \(report.path)") }
            if !summary.ok { throw ExitCode.failure }
        } catch let e as SenderAgent.AgentError {
            FileHandle.standardError.write(Data((e.description + "\n").utf8))
            throw ExitCode.failure
        } catch let e as ExportEngine.EngineError {
            FileHandle.standardError.write(Data((e.description + "\n").utf8))
            throw ExitCode.failure
        }
    }
}

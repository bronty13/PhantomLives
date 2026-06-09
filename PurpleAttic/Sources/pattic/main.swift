import ArgumentParser
import Foundation
import PurpleAtticCore

/// `pattic` — the command-line front-end to the PurpleAttic archival engine. Runs the safe,
/// non-destructive half (export → mirror → verify → cloud) so the archive can run on Vortex
/// from a terminal with Full Disk Access before the GUI exists. Purge is intentionally NOT
/// exposed here — deletion lives only in the guarded GUI.
struct Pattic: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pattic",
        abstract: "Archive the macOS Photos library to verified plain-file copies (osxphotos engine).",
        version: "0.1.0",
        subcommands: [Doctor.self, Init.self, Plan.self, Export.self]
    )
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that osxphotos, exiftool, and rsync are installed.")

    func run() throws {
        let r = Tooling.readiness()
        func line(_ name: String, _ path: String?) {
            print("  \(path != nil ? "✓" : "✗") \(name): \(path ?? "NOT FOUND")")
        }
        print("PurpleAttic toolchain:")
        line("osxphotos", r.osxphotos)
        line("exiftool", r.exiftool)
        line("rsync", r.rsync)
        if !r.allPresent {
            print("\nInstall the missing tools:")
            if r.osxphotos == nil { print("  pipx install osxphotos   # or: brew install osxphotos") }
            if r.exiftool == nil { print("  brew install exiftool") }
            throw ExitCode.failure
        }
        print("\nAll tools present.")
    }
}

// MARK: - init

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a starter profile JSON you then edit (destinations, retention).")

    @Option(name: .long, help: "Where to write the profile (default: ~/Library/Application Support/PurpleAttic/profile.json).")
    var profile: String?

    @Flag(name: .long, help: "Overwrite an existing profile.")
    var force: Bool = false

    func run() throws {
        let url = profile.map { URL(fileURLWithPath: $0) } ?? ProfileStore.defaultProfileURL()
        if FileManager.default.fileExists(atPath: url.path) && !force {
            print("Profile already exists at \(url.path). Use --force to overwrite.")
            throw ExitCode.failure
        }
        let written = try ProfileStore.save(ProfileStore.sample(), to: url)
        print("Wrote starter profile to \(written.path)")
        print("Edit it (set primaryDestination + mirrorDestinations), then run:")
        print("  pattic plan      # preview the osxphotos commands")
        print("  pattic export    # run the archive")
    }
}

// MARK: - shared profile loading

struct ProfileOption: ParsableArguments {
    @Option(name: .long, help: "Path to a profile JSON (default: ~/Library/Application Support/PurpleAttic/profile.json).")
    var profile: String?

    func loadProfile() throws -> ArchiveProfile {
        let url = profile.map { URL(fileURLWithPath: $0) } ?? ProfileStore.defaultProfileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("No profile at \(url.path). Create one with `pattic init`.")
            throw ExitCode.failure
        }
        return try ProfileStore.load(from: url)
    }
}

// MARK: - plan

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the osxphotos commands and retention rule without running anything.")

    @OptionGroup var profileOpt: ProfileOption

    func run() throws {
        let profile = try profileOpt.loadProfile()
        let osxphotos = Tooling.osxphotos ?? "osxphotos"

        print("Profile: \(profile.name)")
        print("Library: \(profile.photosLibraryPath ?? "(System Photo Library)")")
        print("Primary: \(profile.primaryDestination)")
        print("Mirrors: \(profile.mirrorDestinations.isEmpty ? "(none)" : profile.mirrorDestinations.joined(separator: ", "))")
        print("Cloud:   \(profile.cloudVaultPath ?? "(none)")")
        print("Formats: \(profile.enabledPasses.map { $0.label }.joined(separator: ", "))")
        print("")
        print("Retention:")
        let ret = profile.retention
        print("  keep window: \(ret.keepWindowDays) days")
        print("  keep albums: \(ret.keepAlbumNames.joined(separator: ", "))")
        print("  keep keywords: \(ret.keepKeywords.joined(separator: ", "))")
        print("  keep favorites: \(ret.keepFavorites)")
        print("  purge enabled: \(profile.purgeEnabled)  (CLI never purges; GUI only)")
        print("")
        let issues = profile.validationIssues()
        if !issues.isEmpty {
            print("Issues:")
            for i in issues { print("  - \(i)") }
            print("")
        }
        print("osxphotos commands:")
        for pass in profile.enabledPasses {
            print("  # \(pass.label)")
            print("  " + ExportPlan.shellCommand(osxphotos: osxphotos, profile: profile, pass: pass, dryRun: false))
        }
    }
}

// MARK: - export

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the archive: osxphotos export → mirror → verify → cloud.")

    @OptionGroup var profileOpt: ProfileOption

    @Flag(name: .long, help: "Pass --dry-run to osxphotos and skip mirror/verify/cloud.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Deep verify with SHA-256 (slow; default is size+inventory).")
    var deep: Bool = false

    func run() throws {
        let profile = try profileOpt.loadProfile()
        let logger = AtticLogger(runName: profile.name.replacingOccurrences(of: " ", with: "_"), echo: true)
        let engine = ExportEngine(logger: logger)
        do {
            let summary = try engine.run(profile: profile, dryRun: dryRun, deepVerify: deep)
            if let report = summary.writeReport() {
                print("\nReport: \(report.path)")
            }
            if !summary.allSucceeded { throw ExitCode.failure }
        } catch let e as ExportEngine.EngineError {
            FileHandle.standardError.write(Data((e.description + "\n").utf8))
            throw ExitCode.failure
        }
    }
}

Pattic.main()

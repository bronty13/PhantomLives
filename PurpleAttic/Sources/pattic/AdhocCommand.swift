import ArgumentParser
import Foundation
import PurpleAtticCore

/// `pattic adhoc …` — drive the **ad-hoc, file-level Backblaze B2 store** (separate from the photo
/// off-site) from the command line, for scripting / scheduling. Configure it first in the app
/// (Ad-hoc B2 tab: bucket, credentials, encryption passphrase); this reuses that same profile +
/// Keychain, so no secrets are passed on the command line.
struct Adhoc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adhoc",
        abstract: "Ad-hoc Backblaze B2 file store (one-way additive backup + listing).",
        subcommands: [AdhocBackup.self, AdhocList.self, AdhocVerify.self]
    )
}

/// Load the profile and its configured ad-hoc store, or fail with a clear message.
private func loadAdhocConfig(_ profileOpt: ProfileOption) throws -> AdhocBackupConfig {
    let profile = try profileOpt.loadProfile()
    guard let cfg = profile.adhocBackup, cfg.isConfigured else {
        print("No ad-hoc B2 store is configured. Set it up in the app (Ad-hoc B2 tab) first.")
        throw ExitCode.failure
    }
    return cfg
}

// MARK: - adhoc backup

struct AdhocBackup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Upload the configured sources to B2 (one-way, additive, client-side encrypted).")
    @OptionGroup var profileOpt: ProfileOption

    @Flag(name: .long, help: "Preview what would upload (names + sizes only) without transferring any file or writing to B2 — a cheap, drive-light way to confirm only the new delta is left to send.")
    var dryRun = false

    func run() throws {
        let cfg = try loadAdhocConfig(profileOpt)
        let outcome = RcloneService.backup(config: cfg, dryRun: dryRun) { line in
            if let m = RcloneParse.logMessage(line) { print(m) }
        }
        switch outcome {
        case .ok(let d): print("OK: \(d)")
        case .skipped(let r): print("Skipped: \(r)")   // offline / missing creds = non-fatal, like the archive
        case .failed(let d):
            FileHandle.standardError.write(Data("Error: \(d)\n".utf8))
            throw ExitCode.failure
        }
    }
}

// MARK: - adhoc verify (pre-purge gate)

struct AdhocVerify: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Confirm every local source file is on B2 — the gate to run BEFORE purging local copies.")
    @OptionGroup var profileOpt: ProfileOption

    func run() throws {
        let cfg = try loadAdhocConfig(profileOpt)
        let (entries, outcome) = RcloneService.diff(config: cfg) { line in
            FileHandle.standardError.write(Data((line + "\n").utf8))   // per-source progress → stderr
        }
        if case .failed(let d) = outcome {
            FileHandle.standardError.write(Data("Error: \(d)\n".utf8))
            throw ExitCode.failure
        }
        if case .skipped(let r) = outcome {
            print("Skipped: \(r)")
            return
        }
        // A purge is safe ONLY when nothing is local-only (missing), changed, OR uncomparable —
        // a file rclone couldn't compare ('!') is an unknown, and you never delete the last local
        // copy of an unknown.
        let unsafe = entries.filter {
            $0.change == .onlyLocal || $0.change == .differ || $0.change == .error
        }
        if unsafe.isEmpty {
            print("✅ VERIFIED: every local file is present on B2 (size-matched). Safe to purge local copies.")
        } else {
            let missing = unsafe.filter { $0.change == .onlyLocal }.count
            let differ  = unsafe.filter { $0.change == .differ }.count
            let errors  = unsafe.filter { $0.change == .error }.count
            print("❌ NOT SAFE TO PURGE — \(unsafe.count) file(s) not confirmed on B2 "
                  + "(\(missing) missing, \(differ) differ, \(errors) uncomparable):")
            for e in unsafe.prefix(50) { print("   \(e.change.rawValue) \(e.path)") }
            if unsafe.count > 50 { print("   …and \(unsafe.count - 50) more") }
            print("→ Run `pattic adhoc backup` to finish uploading, then verify again.")
            throw ExitCode.failure
        }
    }
}

// MARK: - adhoc list

struct AdhocList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the (decrypted) contents of the ad-hoc B2 store.")
    @OptionGroup var profileOpt: ProfileOption

    func run() throws {
        let cfg = try loadAdhocConfig(profileOpt)
        let (files, outcome) = RcloneService.list(config: cfg)
        switch outcome {
        case .ok:
            for f in files.sorted(by: { $0.path < $1.path }) {
                print("\(f.isDir ? "-" : String(f.size))\t\(f.path)")
            }
            print("\(files.count) item(s)")
        case .skipped(let r): print("Skipped: \(r)")
        case .failed(let d):
            FileHandle.standardError.write(Data("Error: \(d)\n".utf8))
            throw ExitCode.failure
        }
    }
}

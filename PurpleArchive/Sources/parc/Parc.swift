import ArgumentParser
import ArchiveKit
import Foundation

/// `parc` — the PurpleArchive CLI. One binary, every format, the same engine as
/// the app. Designed to beat the muscle-memory grab for `bsdtar`/`unrar`/`7z`:
/// auto-detected formats, `--json` listing, integrity test, hashing, and a
/// `recommend`/`convert` surface (the latter two land with their phases).
@main
struct Parc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parc",
        abstract: "PurpleArchive — extract, create, inspect and hash any archive.",
        version: "PurpleArchive \(ArchiveKitVersions.libarchive)+zstd\(ArchiveKitVersions.zstd)",
        subcommands: [List.self, Extract.self, Add.self, Test.self, Info.self,
                      Hash.self, Convert.self, Recommend.self, Vault.self, Versions.self],
        defaultSubcommand: nil)
}

// MARK: - shared helpers

enum Format {
    static func size(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", v, units[i])
    }
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("parc: \(message)\n".utf8))
    Parc.exit(withError: ExitCode(1))
}

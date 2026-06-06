import Foundation
import ArchiveKit

// Phase 0 CLI harness. Hand-rolled arg handling for now; Phase 1 replaces this
// with swift-argument-parser and the full x/l/a/t/info/hash/convert surface.
// Its job today is to prove the whole stack links and runs: Swift → libarchive
// (→ zstd/lzma/z/bz2) → a real archive listed at runtime.

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    parc — PurpleArchive CLI (Phase 0)
    usage:
      parc l <archive>     list entries
      parc version         print engine versions
    """.utf8))
    FileHandle.standardError.write(Data("\n".utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "version":
    print("parc (PurpleArchive) — Phase 0")
    print("  libarchive \(ArchiveKitVersions.libarchive)")
    print("  zstd       \(ArchiveKitVersions.zstd)")

case "l", "list":
    guard args.count >= 2 else { usage() }
    let url = URL(fileURLWithPath: args[1])
    do {
        let entries = try LibArchiveEngine().list(url)
        for e in entries {
            let kind = e.isDirectory ? "d" : (e.isSymlink ? "l" : "-")
            let perms = e.posixPermissions.map { String(format: "%04o", $0) } ?? "----"
            print("\(kind) \(perms) \(String(format: "%12d", e.uncompressedSize))  \(e.displayPath)")
        }
        FileHandle.standardError.write(Data("\(entries.count) entries\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

default:
    usage()
}

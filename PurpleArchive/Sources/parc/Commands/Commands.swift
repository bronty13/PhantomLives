import ArgumentParser
import ArchiveKit
import Foundation

// MARK: - list

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "l", abstract: "List archive contents.", aliases: ["list"])

    @Argument(help: "Archive to list.") var archive: String
    @Flag(name: .long, help: "Emit machine-readable JSON.") var json = false
    @Option(name: .shortAndLong, help: "Password for an encrypted archive.") var password: String?
    @Option(name: .long, help: "Filename encoding: auto (default), utf8, cp437, shift-jis, gbk, euc-kr, big5, cp1251, cp1252.")
    var encoding: String = "auto"

    func run() async throws {
        let url = URL(fileURLWithPath: archive)
        let svc = ArchiveService()
        var entries: [ArchiveEntry]
        do {
            let chosen = try resolveEncoding(for: url, service: svc)
            entries = try svc.list(url, encoding: chosen)
        }
        catch { die(error.localizedDescription) }

        if json {
            struct Row: Encodable { let path: String; let size: Int64; let dir: Bool; let encrypted: Bool }
            let rows = entries.map { Row(path: $0.displayPath, size: $0.uncompressedSize,
                                         dir: $0.isDirectory, encrypted: $0.isEncrypted) }
            let data = try JSONEncoder().encode(rows)
            print(String(decoding: data, as: UTF8.self))
        } else {
            for e in entries {
                let kind = e.isDirectory ? "d" : (e.isSymlink ? "l" : "-")
                let lock = e.isEncrypted ? "🔒" : "  "
                print("\(kind)\(lock)\(String(format: "%12d", e.uncompressedSize))  \(e.displayPath)")
            }
            FileHandle.standardError.write(Data("\(entries.count) entries\n".utf8))
        }
    }

    /// Map the `--encoding` flag to an optional override (nil = UTF-8 default).
    private func resolveEncoding(for url: URL, service: ArchiveService) throws -> String.Encoding? {
        switch encoding.lowercased() {
        case "auto":
            let detected = try service.detectEncoding(url)
            return detected.encoding == .utf8 ? nil : detected.encoding
        case "utf8", "utf-8": return nil
        case "cp437": return cf(.dosLatinUS)
        case "shift-jis", "shiftjis", "sjis": return .shiftJIS
        case "cp932": return cf(.dosJapanese)
        case "euc-jp", "eucjp": return .japaneseEUC
        case "gbk", "gb2312": return cf(.dosChineseSimplif)
        case "big5": return cf(.dosChineseTrad)
        case "euc-kr", "euckr": return cf(.dosKorean)
        case "cp1251", "windows-1251": return .windowsCP1251
        case "cp1252", "windows-1252": return .windowsCP1252
        case "latin1", "iso-8859-1": return .isoLatin1
        default: die("unknown encoding “\(encoding)” (try: auto, utf8, cp437, shift-jis, gbk, euc-kr, big5, cp1251, cp1252)")
        }
    }

    private func cf(_ enc: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(enc.rawValue)))
    }
}

// MARK: - extract

struct Extract: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "x", abstract: "Extract an archive.", aliases: ["extract"])

    @Argument(help: "Archive to extract.") var archive: String
    @Option(name: .shortAndLong, help: "Output directory (default: ~/Downloads/PurpleArchive/<name>).")
    var output: String?
    @Option(name: .shortAndLong, help: "Password for an encrypted archive.") var password: String?
    @Flag(name: .long, help: "Skip files that already exist instead of overwriting.") var skipExisting = false

    func run() async throws {
        let url = URL(fileURLWithPath: archive)
        let dest: URL
        if let output { dest = URL(fileURLWithPath: output) }
        else {
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/PurpleArchive")
            dest = base.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
        }
        let opts = ExtractOptions(destination: dest, password: password,
                                  overwrite: skipExisting ? .skip : .overwrite)
        do {
            let n = try ArchiveService().extract(url, options: opts)
            print("Extracted \(n) entries → \(dest.path)")
        } catch let e as ArchiveError {
            if case .passwordRequired = e { die("password required (use -p)") }
            die(e.localizedDescription)
        } catch { die(error.localizedDescription) }
    }
}

// MARK: - add (create)

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "a",
        abstract: "Create an archive (format inferred from the output extension).",
        aliases: ["add", "create"])

    @Argument(help: "Output archive, e.g. out.zip / out.tar.zst / out.7z.") var output: String
    @Argument(help: "Files/folders to add.") var inputs: [String]
    @Option(name: .shortAndLong, help: "Compression level (codec-dependent).") var level = 6
    @Option(name: .shortAndLong, help: "Encrypt with this password (zip → AES-256).") var password: String?
    @Option(name: .long, help: "Worker threads for zstd (0 = all cores).") var threads = 0
    @Flag(name: .long, help: "Keep .DS_Store / __MACOSX (default strips them).") var keepMacMetadata = false

    func run() async throws {
        let out = URL(fileURLWithPath: output)
        let urls = inputs.map { URL(fileURLWithPath: $0) }
        let opts = CompressionOptions(level: level, password: password, threads: threads,
                                      stripMacMetadata: !keepMacMetadata)
        do {
            let n = try ArchiveService().create(out, inputs: urls, options: opts)
            let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int64) ?? nil
            let suffix = size.map { " (\(Format.size($0)))" } ?? ""
            print("Created \(out.lastPathComponent) with \(n) entries\(suffix)")
        } catch { die(error.localizedDescription) }
    }
}

// MARK: - test

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "t", abstract: "Verify archive integrity.", aliases: ["test"])

    @Argument(help: "Archive to test.") var archive: String
    @Option(name: .shortAndLong, help: "Password for an encrypted archive.") var password: String?

    func run() async throws {
        let url = URL(fileURLWithPath: archive)
        do {
            _ = try ArchiveService().test(url, password: password)
            print("OK — \(url.lastPathComponent) verified")
        } catch { die("FAILED — \(error.localizedDescription)") }
    }
}

// MARK: - info

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info", abstract: "Show archive summary (entries, size, encryption).")

    @Argument(help: "Archive to inspect.") var archive: String

    func run() async throws {
        let url = URL(fileURLWithPath: archive)
        do {
            let info = try ArchiveService().info(url)
            print("Archive:    \(url.lastPathComponent)")
            print("Entries:    \(info.entryCount) (\(info.fileCount) files)")
            print("Unpacked:   \(Format.size(info.totalUncompressedSize))")
            if let c = info.compressedSize { print("On disk:    \(Format.size(c))") }
            if let r = info.ratio { print("Ratio:      \(String(format: "%.1f%%", r * 100))") }
            print("Encrypted:  \(info.isEncrypted ? "yes" : "no")")
        } catch { die(error.localizedDescription) }
    }
}

// MARK: - hash

struct Hash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hash", abstract: "Hash a file (or archive) — md5/sha1/sha256/sha512.")

    @Argument(help: "File to hash.") var file: String
    @Option(name: .long, help: "Algorithm (md5|sha1|sha256|sha512).") var algo = "sha256"

    func run() async throws {
        guard let algorithm = HashAlgorithm(rawValue: algo.lowercased()) else {
            die("unknown algorithm “\(algo)” (md5|sha1|sha256|sha512)")
        }
        do {
            let digest = try ArchiveService().hash(URL(fileURLWithPath: file), algorithm: algorithm)
            print("\(digest)  \(file)")
        } catch { die(error.localizedDescription) }
    }
}

// MARK: - versions

struct Versions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions", abstract: "Print linked engine library versions.")
    func run() async throws {
        print("libarchive \(ArchiveKitVersions.libarchive)")
        print("zstd       \(ArchiveKitVersions.zstd)")
    }
}

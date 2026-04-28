import Foundation
import SnRCore

@main
struct SnRCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            usage(); exit(2)
        }
        do {
            switch args[0] {
            case "run":
                try await runScript(args: Array(args.dropFirst()))
            case "search", "find":
                try await runSearch(args: Array(args.dropFirst()))
            case "replace":
                try await runReplace(args: Array(args.dropFirst()))
            case "restore":
                try await runRestore(args: Array(args.dropFirst()))
            case "touch":
                try await runTouch(args: Array(args.dropFirst()))
            case "pdf":
                try await runPDF(args: Array(args.dropFirst()))
            case "-h", "--help", "help":
                usage()
            default:
                fputs("Unknown subcommand: \(args[0])\n", stderr)
                usage(); exit(2)
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func usage() {
        let text = """
        snr — MacSearchReplace command line

        Usage:
          snr run <script.snrscript>           Run a saved .snrscript pipeline.
                                               Supports v1 and v2 (per-step roots/include/exclude).
          snr search <pattern> <path...>       Search only (literal).
                       [-r] [-i] [-w] [-m] [--include 'glob'] [--exclude 'glob']
          snr replace <pattern> <repl> <path...>
                       [-r] [-i] [-m] [--no-backup] [--dry-run]
          snr restore <backup-session-dir>     Restore files from a backup session.
          snr touch <path...>                  Set mtime to now on the given files.
          snr pdf <pattern> <path...>          Search PDF text only (read-only).
                       [-r] [-i]

        Examples:
          snr search 'TODO' src/
          snr replace -r '\\bfoo\\b' bar src/
          snr run rename.snrscript
          snr pdf 'invoice' Documents/

        """
        fputs(text, stderr)
    }

    // MARK: - Subcommands

    static func runScript(args: [String]) async throws {
        guard let path = args.first else { throw CLIError("script path required") }
        let script = try SnRScript.load(from: URL(fileURLWithPath: path))
        for step in script.steps {
            let spec = script.searchSpec(forStep: step)
            let searcher = Searcher.ripgrep()
            var files: [FileMatches] = []
            for try await m in searcher.stream(spec: spec) { files.append(m) }
            print("[\(step.type)] \(step.search) → \(files.reduce(0){$0+$1.hits.count}) hits in \(files.count) files")
            if let rspec = script.replaceSpec(forStep: step) {
                let backups = try BackupManager()
                let replacer = Replacer()
                for f in files {
                    try await replacer.apply(spec: rspec, fileURL: f.url, acceptedHits: f.hits, backups: backups)
                }
                try await backups.writeManifest()
                print("  backups → \(backups.sessionRoot.path)")
            }
        }
    }

    static func runTouch(args: [String]) async throws {
        guard !args.isEmpty else { throw CLIError("need <path...>") }
        let urls = args.map { URL(fileURLWithPath: $0) }
        let changed = try FileTouch.touch(urls: urls)
        for u in changed { print("touched \(u.path)") }
    }

    static func runPDF(args: [String]) async throws {
        var (flags, rest) = parseFlags(args)
        guard rest.count >= 2 else { throw CLIError("need <pattern> <path>") }
        let pattern = rest.removeFirst()
        let kind: SearchSpec.PatternKind = flags.contains("-r") ? .regex : .literal
        let ci = flags.contains("-i")
        let pdf = PDFSearcher()
        let fm = FileManager.default
        for path in rest {
            let root = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: root.path, isDirectory: &isDir)
            let urls: [URL]
            if isDir.boolValue, let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                urls = en.compactMap { $0 as? URL }.filter(PDFSearcher.isPDF)
            } else {
                urls = [root].filter(PDFSearcher.isPDF)
            }
            for url in urls {
                if let m = try? pdf.search(url: url, pattern: pattern, kind: kind, caseInsensitive: ci) {
                    for h in m.hits {
                        let (page, lineInPage) = PDFSearcher.decodeLine(h.line)
                        print("\(url.path):p\(page):l\(lineInPage): \(h.preview)")
                    }
                }
            }
        }
    }

    static func runSearch(args: [String]) async throws {
        var (flags, rest) = parseFlags(args)
        guard rest.count >= 2 else { throw CLIError("need <pattern> <path>") }
        let pattern = rest.removeFirst()
        let roots = rest.map { URL(fileURLWithPath: $0) }
        let spec = SearchSpec(
            pattern: pattern,
            kind: flags.contains("-r") ? .regex : .literal,
            caseInsensitive: flags.contains("-i"),
            wholeWord: flags.contains("-w"),
            multiline: flags.contains("-m"),
            roots: roots,
            includeGlobs: flags.values(for: "--include"),
            excludeGlobs: flags.values(for: "--exclude")
        )
        for try await match in Searcher.ripgrep().stream(spec: spec) {
            for hit in match.hits {
                print("\(match.url.path):\(hit.line):\(hit.columnStart): \(hit.preview)")
            }
        }
    }

    static func runReplace(args: [String]) async throws {
        var (flags, rest) = parseFlags(args)
        guard rest.count >= 3 else { throw CLIError("need <pattern> <repl> <path>") }
        let pattern = rest.removeFirst()
        let replacement = rest.removeFirst()
        let roots = rest.map { URL(fileURLWithPath: $0) }
        let dryRun = flags.contains("--dry-run")
        let noBackup = flags.contains("--no-backup")

        let searchSpec = SearchSpec(
            pattern: pattern,
            kind: flags.contains("-r") ? .regex : .literal,
            caseInsensitive: flags.contains("-i"),
            multiline: flags.contains("-m"),
            roots: roots
        )
        let replaceSpec = ReplaceSpec(
            pattern: pattern,
            replacement: replacement,
            mode: flags.contains("-r") ? .regex : .literal,
            caseInsensitive: flags.contains("-i"),
            multiline: flags.contains("-m")
        )
        var matches: [FileMatches] = []
        for try await m in Searcher.ripgrep().stream(spec: searchSpec) { matches.append(m) }
        let total = matches.reduce(0) { $0 + $1.hits.count }
        print("Would replace \(total) hits in \(matches.count) files.")
        if dryRun { return }

        let backups: BackupManager? = noBackup ? nil : try BackupManager()
        let replacer = Replacer()
        for file in matches {
            try await replacer.apply(spec: replaceSpec, fileURL: file.url, acceptedHits: file.hits, backups: backups)
        }
        if let backups { try await backups.writeManifest(); print("Backups → \(backups.sessionRoot.path)") }
    }

    static func runRestore(args: [String]) async throws {
        guard let path = args.first else { throw CLIError("backup session dir required") }
        let manifest = URL(fileURLWithPath: path).appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifest)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let m = try dec.decode(BackupManager.Manifest.self, from: data)
        let fm = FileManager.default
        for entry in m.entries {
            let dst = URL(fileURLWithPath: entry.originalPath)
            let src = URL(fileURLWithPath: entry.backupPath)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            if let mtime = entry.originalMtime {
                try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: dst.path)
            }
            print("restored \(entry.originalPath)")
        }
    }
}

struct CLIError: Error, CustomStringConvertible {
    let message: String
    init(_ m: String) { message = m }
    var description: String { message }
}

private struct Flags {
    var bools: Set<String> = []
    var values: [String: [String]] = [:]
    func contains(_ flag: String) -> Bool { bools.contains(flag) }
    func values(for key: String) -> [String] { values[key] ?? [] }
}

private let booleanLongFlags: Set<String> = ["--dry-run", "--no-backup", "--help"]

private func parseFlags(_ args: [String]) -> (Flags, [String]) {
    var flags = Flags()
    var rest: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if booleanLongFlags.contains(a) {
            flags.bools.insert(a)
            i += 1
        } else if a.hasPrefix("--") && i + 1 < args.count && !args[i+1].hasPrefix("-") {
            flags.values[a, default: []].append(args[i+1])
            i += 2
        } else if a.hasPrefix("-") && a.count <= 3 {
            flags.bools.insert(a)
            i += 1
        } else {
            rest.append(a)
            i += 1
        }
    }
    return (flags, rest)
}

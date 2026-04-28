import Foundation
import SwiftUI
import AppKit
import SnRCore

/// One element in the multi-string ("String Pairs") replace sheet.
struct StringPair: Identifiable, Hashable {
    var id = UUID()
    var find: String = ""
    var replace: String = ""
}

@MainActor
final class SearchReplaceViewModel: ObservableObject {

    // MARK: - Criteria
    @Published var pattern: String = ""
    @Published var replacement: String = ""
    @Published var isRegex: Bool = false
    @Published var caseInsensitive: Bool = false
    @Published var wholeWord: Bool = false
    @Published var multiline: Bool = false
    @Published var honorGitignore: Bool = true
    @Published var includeGlobs: String = ""
    @Published var excludeGlobs: String = ""
    @Published var roots: [URL] = []

    // Filters
    @Published var useDateFilter: Bool = false
    @Published var modifiedAfter: Date = Date(timeIntervalSinceNow: -86400 * 30)
    @Published var modifiedBefore: Date = Date()
    @Published var useSizeFilter: Bool = false
    @Published var maxFileBytesMB: Int = 50

    // Archive / PDF toggles (initialized from Preferences)
    @Published var searchInsideArchives: Bool
    @Published var searchInsideOOXML: Bool
    @Published var searchInsidePDFs: Bool

    // MARK: - Results
    @Published var fileMatches: [FileMatches] = []
    @Published var selectedFile: FileMatches.ID?
    @Published var selectedHitID: Hit.ID?
    @Published var statusText: String = "Ready."
    @Published var isWorking: Bool = false
    @Published var expandedFiles: Set<FileMatches.ID> = []

    // MARK: - Favorites
    @Published var favorites: [Favorite] = FavoriteStore.list()
    @Published var showSaveFavoriteSheet: Bool = false
    @Published var newFavoriteName: String = ""

    // MARK: - String Pairs sheet
    @Published var showStringPairsSheet: Bool = false
    @Published var stringPairs: [StringPair] = [StringPair()]

    // MARK: - Ask-each prompt
    @Published var showAskEachSheet: Bool = false
    @Published var pendingAskHits: [(file: FileMatches, hit: Hit)] = []
    @Published var askIndex: Int = 0
    @Published var askMode: AskAllMode = .askEach
    enum AskAllMode { case askEach, replaceAll, skipFile }

    // MARK: - Cancellation
    private var currentSearchTask: Task<Void, Never>?

    private let prefs = Preferences.shared

    init() {
        searchInsideArchives = Preferences.shared.searchInsideArchives
        searchInsideOOXML    = Preferences.shared.searchInsideOOXML
        searchInsidePDFs     = Preferences.shared.searchInsidePDFs
    }

    // MARK: - Reset

    func reset() {
        pattern = ""; replacement = ""
        isRegex = false; caseInsensitive = false; wholeWord = false; multiline = false
        includeGlobs = ""; excludeGlobs = ""
        roots = []
        useDateFilter = false; useSizeFilter = false
        fileMatches = []
        selectedFile = nil; selectedHitID = nil
        expandedFiles.removeAll()
        statusText = "Ready."
    }

    // MARK: - Folder picker

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            roots.append(contentsOf: panel.urls)
            for url in panel.urls { prefs.pushRecentRoot(url.path) }
        }
    }

    func removeRoot(_ url: URL) { roots.removeAll { $0 == url } }

    func addRoot(path: String) {
        let url = URL(fileURLWithPath: path)
        if !roots.contains(url) { roots.append(url) }
        prefs.pushRecentRoot(url.path)
    }

    // MARK: - Build SearchSpec

    private func buildSpec() -> SearchSpec {
        SearchSpec(
            pattern: pattern,
            kind: isRegex ? .regex : .literal,
            caseInsensitive: caseInsensitive,
            wholeWord: wholeWord,
            multiline: multiline,
            roots: roots,
            includeGlobs: splitGlobs(includeGlobs),
            excludeGlobs: splitGlobs(excludeGlobs),
            honorGitignore: honorGitignore,
            followSymlinks: false,
            maxFileBytes: useSizeFilter ? maxFileBytesMB * 1_048_576 : nil,
            modifiedAfter: useDateFilter ? modifiedAfter : nil,
            modifiedBefore: useDateFilter ? modifiedBefore : nil
        )
    }

    // MARK: - Search

    func runSearch() async {
        guard !pattern.isEmpty, !roots.isEmpty else {
            statusText = "Enter a pattern and pick at least one folder."; return
        }
        currentSearchTask?.cancel()
        let spec = buildSpec()
        isWorking = true
        statusText = "Searching…"
        fileMatches = []
        selectedFile = nil; selectedHitID = nil
        expandedFiles.removeAll()

        let includeArchive = searchInsideArchives
        let includeOOXML = searchInsideOOXML
        let includePDFs = searchInsidePDFs

        let task = Task { @MainActor in
            var fileCount = 0
            var hitCount = 0
            do {
                for try await match in Searcher.ripgrep().stream(spec: spec) {
                    if Task.isCancelled { break }
                    fileMatches.append(match)
                    expandedFiles.insert(match.id)
                    fileCount += 1
                    hitCount += match.hits.count
                    statusText = "\(hitCount) hits in \(fileCount) files…"
                }
                if !Task.isCancelled && includePDFs {
                    let pdfHits = await scanPDFs(spec: spec)
                    for fm in pdfHits {
                        fileMatches.append(fm); expandedFiles.insert(fm.id)
                        fileCount += 1; hitCount += fm.hits.count
                        statusText = "\(hitCount) hits in \(fileCount) files…"
                    }
                }
                if !Task.isCancelled && (includeArchive || includeOOXML) {
                    let arHits = await scanArchives(spec: spec, zip: includeArchive, ooxml: includeOOXML)
                    for fm in arHits {
                        fileMatches.append(fm); expandedFiles.insert(fm.id)
                        fileCount += 1; hitCount += fm.hits.count
                        statusText = "\(hitCount) hits in \(fileCount) files…"
                    }
                }
                if let first = fileMatches.first, let firstHit = first.hits.first {
                    selectedFile = first.id; selectedHitID = firstHit.id
                }
                statusText = Task.isCancelled
                    ? "Stopped. \(hitCount) hits in \(fileCount) files."
                    : "Done. \(hitCount) hits in \(fileCount) files."
            } catch {
                statusText = "Search failed: \(error)"
            }
            isWorking = false
        }
        currentSearchTask = task
        await task.value
    }

    func stopSearch() {
        currentSearchTask?.cancel()
        statusText = "Stopping…"
    }

    // MARK: - PDF + archive scans (called after the rg pass)

    nonisolated private func scanPDFs(spec: SearchSpec) async -> [FileMatches] {
        var out: [FileMatches] = []
        let pdf = PDFSearcher()
        for root in spec.roots {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            while let any = en.nextObject() {
                guard let url = any as? URL, PDFSearcher.isPDF(url) else { continue }
                if let fm = try? pdf.search(url: url, pattern: spec.pattern, kind: spec.kind, caseInsensitive: spec.caseInsensitive) {
                    out.append(fm)
                }
            }
        }
        return out
    }

    nonisolated private func scanArchives(spec: SearchSpec, zip: Bool, ooxml: Bool) async -> [FileMatches] {
        var out: [FileMatches] = []
        for root in spec.roots {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            while let any = en.nextObject() {
                guard let url = any as? URL else { continue }
                let ext = url.pathExtension.lowercased()
                let isZip = (ext == "zip") && zip
                let isOOXML = ["docx","xlsx","pptx","odt","ods","odp"].contains(ext) && ooxml
                guard isZip || isOOXML else { continue }
                if let fm = await searchOneArchive(url: url, spec: spec) { out.append(fm) }
            }
        }
        return out
    }

    nonisolated private func searchOneArchive(url: URL, spec: SearchSpec) async -> FileMatches? {
        // Extract to temp, run native search over its contents, repack-as-virtual-paths.
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("snr-arch-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-oq", url.path, "-d", work.path]
        task.standardError = Pipe(); task.standardOutput = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        if task.terminationStatus != 0 { return nil }

        var subSpec = spec; subSpec.roots = [work]
        var allHits: [Hit] = []
        do {
            for try await sub in Searcher.nativeFallback.stream(spec: subSpec) {
                let entryPath = sub.url.path.replacingOccurrences(of: work.path + "/", with: "")
                for h in sub.hits {
                    let prefixed = Hit(
                        id: h.id, line: h.line,
                        columnStart: h.columnStart, columnEnd: h.columnEnd,
                        byteStart: h.byteStart, byteEnd: h.byteEnd,
                        preview: "[\(entryPath)] " + h.preview,
                        matchedText: h.matchedText,
                        replacement: h.replacement, accepted: h.accepted
                    )
                    allHits.append(prefixed)
                }
            }
        } catch { return nil }
        guard !allHits.isEmpty else { return nil }
        return FileMatches(url: url, hits: allHits)
    }

    // MARK: - Replace

    func commit() async {
        guard !replacement.isEmpty || isRegex else {
            statusText = "Enter a replacement string."; return
        }
        isWorking = true; defer { isWorking = false }
        statusText = "Committing replacements…"
        let spec = ReplaceSpec(
            pattern: pattern, replacement: replacement,
            mode: isRegex ? .regex : .literal,
            caseInsensitive: caseInsensitive, multiline: multiline
        )
        let backups: BackupManager? = prefs.backupsEnabledByDefault ? (try? BackupManager()) : nil
        let replacer = Replacer()
        var ok = 0, fail = 0
        for file in fileMatches {
            let accepted = file.hits.filter(\.accepted)
            if accepted.isEmpty { continue }
            do {
                try await replacer.apply(spec: spec, fileURL: file.url,
                                         acceptedHits: accepted, backups: backups)
                ok += 1
            } catch { fail += 1 }
        }
        try? await backups?.writeManifest()
        statusText = "Committed \(ok) files (\(fail) failed). Backups → \(backups?.sessionRoot.path ?? "disabled")"
    }

    // MARK: - String Pairs

    func runStringPairs() async {
        let pairs = stringPairs.filter { !$0.find.isEmpty }
        guard !pairs.isEmpty, !roots.isEmpty else {
            statusText = "Add at least one (find, replace) pair and pick a folder."; return
        }
        isWorking = true; defer { isWorking = false }
        let backups: BackupManager? = prefs.backupsEnabledByDefault ? (try? BackupManager()) : nil
        let replacer = Replacer()
        var pairFileTouchCount = 0
        for (idx, pair) in pairs.enumerated() {
            statusText = "Pair \(idx + 1) of \(pairs.count): '\(pair.find)' → '\(pair.replace)'…"
            let sspec = SearchSpec(
                pattern: pair.find, kind: isRegex ? .regex : .literal,
                caseInsensitive: caseInsensitive, wholeWord: wholeWord, multiline: multiline,
                roots: roots,
                includeGlobs: splitGlobs(includeGlobs),
                excludeGlobs: splitGlobs(excludeGlobs),
                honorGitignore: honorGitignore
            )
            let rspec = ReplaceSpec(
                pattern: pair.find, replacement: pair.replace,
                mode: isRegex ? .regex : .literal,
                caseInsensitive: caseInsensitive, multiline: multiline
            )
            do {
                for try await fm in Searcher.ripgrep().stream(spec: sspec) {
                    do {
                        try await replacer.apply(spec: rspec, fileURL: fm.url,
                                                 acceptedHits: nil, backups: backups)
                        pairFileTouchCount += 1
                    } catch { /* skip */ }
                }
            } catch { statusText = "Pair \(idx + 1) failed: \(error)"; return }
        }
        try? await backups?.writeManifest()
        statusText = "String Pairs: \(pairs.count) pairs, ~\(pairFileTouchCount) file rewrites. Backups → \(backups?.sessionRoot.path ?? "disabled")"
    }

    // MARK: - Ask-each

    func startAskEach() {
        pendingAskHits = []
        for file in fileMatches {
            for h in file.hits where h.accepted {
                pendingAskHits.append((file, h))
            }
        }
        guard !pendingAskHits.isEmpty else {
            statusText = "Nothing to confirm."; return
        }
        askIndex = 0
        askMode = .askEach
        showAskEachSheet = true
    }

    /// Apply the current ask-each decision.
    /// - Parameter accept: true = replace; false = skip
    func answerAsk(accept: Bool, applyToAll: Bool = false, skipRestOfFile: Bool = false, cancel: Bool = false) async {
        if cancel { showAskEachSheet = false; return }
        if applyToAll { askMode = .replaceAll }
        if skipRestOfFile { askMode = .skipFile }

        let entry = pendingAskHits[askIndex]
        if accept {
            // mark just this hit accepted in the model already (it is); apply only it
            await applySingleHit(entry.file, hit: entry.hit)
        }

        var nextIdx = askIndex + 1
        // Skip remaining hits in the same file if requested
        if askMode == .skipFile {
            while nextIdx < pendingAskHits.count, pendingAskHits[nextIdx].file.id == entry.file.id {
                nextIdx += 1
            }
            askMode = .askEach
        }
        // Replace-all: blast through the rest
        if askMode == .replaceAll {
            for i in nextIdx..<pendingAskHits.count {
                let e = pendingAskHits[i]
                await applySingleHit(e.file, hit: e.hit)
            }
            showAskEachSheet = false
            statusText = "Replaced remaining \(pendingAskHits.count - nextIdx + 1) hits."
            return
        }
        if nextIdx >= pendingAskHits.count {
            showAskEachSheet = false
            statusText = "Done — walked \(pendingAskHits.count) hits."
            return
        }
        askIndex = nextIdx
    }

    private func applySingleHit(_ file: FileMatches, hit: Hit) async {
        let spec = ReplaceSpec(
            pattern: pattern, replacement: replacement,
            mode: isRegex ? .regex : .literal,
            caseInsensitive: caseInsensitive, multiline: multiline
        )
        let backups: BackupManager? = prefs.backupsEnabledByDefault ? (try? BackupManager()) : nil
        try? await Replacer().apply(spec: spec, fileURL: file.url, acceptedHits: [hit], backups: backups)
        try? await backups?.writeManifest()
    }

    // MARK: - Open backups

    func openBackupsFolder() {
        let url = BackupManager.defaultParentRoot()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Hit toggle

    func toggleHit(fileID: FileMatches.ID, hitID: Hit.ID) {
        guard let fIdx = fileMatches.firstIndex(where: { $0.id == fileID }) else { return }
        guard let hIdx = fileMatches[fIdx].hits.firstIndex(where: { $0.id == hitID }) else { return }
        fileMatches[fIdx].hits[hIdx].accepted.toggle()
    }

    // MARK: - Selection helpers

    var selectedFileMatches: FileMatches? {
        guard let id = selectedFile else { return nil }
        return fileMatches.first(where: { $0.id == id })
    }

    var selectedHit: Hit? {
        guard let fm = selectedFileMatches, let hid = selectedHitID else { return nil }
        return fm.hits.first(where: { $0.id == hid })
    }

    func selectHit(fileID: FileMatches.ID, hitID: Hit.ID) {
        selectedFile = fileID; selectedHitID = hitID
    }

    func loadContext(for file: FileMatches, hit: Hit, around: Int? = nil) -> ([String], Int) {
        let n = around ?? prefs.contextLines
        guard let data = try? Data(contentsOf: file.url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return ([], 0) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let idx = max(0, hit.line - 1)
        let lo = max(0, idx - n)
        let hi = min(lines.count - 1, idx + n)
        return (Array(lines[lo...hi]), idx - lo)
    }

    // MARK: - File operations

    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openWithDefaultApp(_ url: URL) { NSWorkspace.shared.open(url) }
    func openInExternalEditor(_ url: URL, binary: Bool = false) {
        prefs.openInExternalEditor(url, binary: binary)
    }
    func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func touchSelectedFiles() {
        let urls = fileMatches.map(\.url)
        let changed = (try? FileTouch.touch(urls: urls)) ?? []
        statusText = "Touched \(changed.count) files."
    }

    // MARK: - Favorites

    func saveAsFavorite(name: String) {
        let fav = Favorite(
            name: name,
            pattern: pattern, replacement: replacement,
            isRegex: isRegex, caseInsensitive: caseInsensitive,
            wholeWord: wholeWord, multiline: multiline,
            includeGlobs: includeGlobs, excludeGlobs: excludeGlobs,
            honorGitignore: honorGitignore,
            rootPaths: roots.map(\.path)
        )
        do { try FavoriteStore.save(fav); favorites = FavoriteStore.list()
             statusText = "Saved favorite '\(name)'."
        } catch { statusText = "Could not save favorite: \(error)" }
    }

    func loadFavorite(_ fav: Favorite) {
        pattern = fav.pattern; replacement = fav.replacement
        isRegex = fav.isRegex; caseInsensitive = fav.caseInsensitive
        wholeWord = fav.wholeWord; multiline = fav.multiline
        includeGlobs = fav.includeGlobs; excludeGlobs = fav.excludeGlobs
        honorGitignore = fav.honorGitignore
        roots = fav.rootPaths.map { URL(fileURLWithPath: $0) }
        statusText = "Loaded favorite '\(fav.name)'."
    }

    func deleteFavorite(_ fav: Favorite) {
        FavoriteStore.delete(fav); favorites = FavoriteStore.list()
    }

    // MARK: - Export results

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV", json = "JSON", html = "HTML", txt = "Plain text"
        var id: String { rawValue }
        var fileExtension: String {
            switch self { case .csv: "csv"; case .json: "json"; case .html: "html"; case .txt: "txt" }
        }
    }

    func exportResults(format: ExportFormat) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let defaultDir = downloads.appendingPathComponent("MacSearchReplace", isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)

        let panel = NSSavePanel()
        panel.directoryURL = defaultDir
        panel.nameFieldStringValue = "results.\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body: String
        switch format {
        case .csv:  body = csvBody()
        case .json: body = jsonBody()
        case .html: body = htmlBody()
        case .txt:  body = txtBody()
        }
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
        statusText = "Exported \(format.rawValue) → \(url.lastPathComponent)"
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private func csvBody() -> String {
        var s = "path,line,column,matched,preview\n"
        for f in fileMatches {
            for h in f.hits {
                s += "\(csvEscape(f.url.path)),\(h.line),\(h.columnStart),\(csvEscape(h.matchedText)),\(csvEscape(h.preview))\n"
            }
        }
        return s
    }

    private func txtBody() -> String {
        var s = ""
        for f in fileMatches {
            s += "\(f.url.path)\n"
            for h in f.hits {
                s += "  L\(h.line),\(h.columnStart): \(h.preview)\n"
            }
        }
        return s
    }

    private func jsonBody() -> String {
        struct Row: Codable { let path: String; let line: Int; let column: Int; let matched: String; let preview: String }
        let rows = fileMatches.flatMap { f in
            f.hits.map { Row(path: f.url.path, line: $0.line, column: $0.columnStart, matched: $0.matchedText, preview: $0.preview) }
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        return String(data: (try? enc.encode(rows)) ?? Data(), encoding: .utf8) ?? "[]"
    }

    private func htmlBody() -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        var s = """
        <!doctype html><html><head><meta charset="utf-8"><title>Search Results</title>
        <style>body{font-family:-apple-system;font-size:13px}
        .file{font-weight:600;margin-top:8px}
        .hit{font-family:Menlo,monospace;white-space:pre}
        mark{background:#ffe066;padding:0 1px}
        .ln{color:#888;display:inline-block;width:48px;text-align:right;padding-right:6px}
        </style></head><body>
        <h2>Search results — \(esc(pattern))</h2>
        """
        for f in fileMatches {
            s += "<div class='file'>\(esc(f.url.path)) (\(f.hits.count))</div>\n"
            for h in f.hits {
                let preview = esc(h.preview).replacingOccurrences(of: esc(h.matchedText),
                                                                 with: "<mark>\(esc(h.matchedText))</mark>")
                s += "<div class='hit'><span class='ln'>\(h.line)</span>\(preview)</div>\n"
            }
        }
        s += "</body></html>"
        return s
    }

    // MARK: - Helpers

    private func splitGlobs(_ s: String) -> [String] {
        s.split(whereSeparator: { ";, ".contains($0) })
            .map(String.init).filter { !$0.isEmpty }
    }
}

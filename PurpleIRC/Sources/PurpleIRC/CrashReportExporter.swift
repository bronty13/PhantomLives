import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Gathers this app's macOS crash reports so a user can hand them over in one
/// click.
///
/// Why this exists: PurpleIRC's crashes on macOS-26 software-rendered VMs are
/// **signal-based** (SIGSEGV / SIGTRAP / SIGABRT inside SwiftUI / AppKit / the
/// Swift runtime), not Objective-C `NSException`s — so the `ExceptionLogger`
/// breadcrumb (which only catches exceptions routed through AppKit's
/// `reportException:` / the uncaught handler) never fires for them and
/// `last-exception.log` stays empty. The actionable artifact is the OS crash
/// report at `~/Library/Logs/DiagnosticReports/PurpleIRC-*.ips`, whose
/// "Exception Type" + faulting-thread backtrace pinpoint the fault. This copies
/// those out to `~/Downloads` and reveals them in Finder so a reporting user
/// doesn't have to dig through `~/Library` by hand (PurpleIRC isn't sandboxed,
/// so it can read DiagnosticReports directly).
enum CrashReportExporter {

    /// Per-user crash-report directory. (PurpleIRC is not sandboxed, so this is
    /// the real `~/Library`, not a container redirect.)
    static var diagnosticReportsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// `~/Downloads` — the export destination root (per the repo-wide
    /// default-output-location rule).
    static var defaultDownloadsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    /// All PurpleIRC crash reports in this Mac's DiagnosticReports, newest first.
    static func reports() -> [URL] { reports(in: diagnosticReportsDir) }

    /// Scan `dir` for PurpleIRC crash reports, newest first. Matches both the
    /// modern `.ips` JSON reports and the legacy `.crash` text format.
    /// Parameterized for testing.
    static func reports(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        let mine = items.filter {
            let n = $0.lastPathComponent
            return n.hasPrefix("PurpleIRC-") && (n.hasSuffix(".ips") || n.hasSuffix(".crash"))
        }
        func mtime(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return mine.sorted { mtime($0) > mtime($1) }
    }

    enum ExportResult: Equatable {
        case exported(folder: URL, count: Int)
        case none
    }

    /// Copy every PurpleIRC crash report into a timestamped folder under
    /// `~/Downloads/PurpleIRC crash-reports/` and reveal it in Finder. If there
    /// are no reports it tells the user (and never throws).
    @MainActor @discardableResult
    static func exportAndReveal() -> ExportResult {
        let result = export()
        #if canImport(AppKit)
        switch result {
        case .exported(let folder, _):
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        case .none:
            presentNoReportsAlert()
        }
        #endif
        return result
    }

    /// Convenience: export this Mac's reports to `~/Downloads`.
    @discardableResult
    static func export(now: Date = Date()) -> ExportResult {
        export(from: reports(), toDownloads: defaultDownloadsDir, now: now)
    }

    /// The pure copy step (no Finder / alert), parameterized for testing.
    /// Copies `sources` into `<downloadsDir>/PurpleIRC crash-reports/<stamp>/`
    /// alongside a README, and returns the destination + count.
    @discardableResult
    static func export(from sources: [URL], toDownloads downloadsDir: URL, now: Date) -> ExportResult {
        guard !sources.isEmpty else { return .none }
        let fm = FileManager.default
        let dest = downloadsDir
            .appendingPathComponent("PurpleIRC crash-reports/\(timestamp(now))", isDirectory: true)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var copied = 0
        for src in sources {
            let out = dest.appendingPathComponent(src.lastPathComponent)
            do { try fm.copyItem(at: src, to: out); copied += 1 } catch { /* skip unreadable */ }
        }
        writeReadme(in: dest, count: copied)
        return .exported(folder: dest, count: copied)
    }

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func writeReadme(in dir: URL, count: Int) {
        let text = """
        PurpleIRC crash reports
        =======================
        \(count) report(s) copied from ~/Library/Logs/DiagnosticReports/.

        These ".ips" files are macOS crash reports. To help diagnose a crash,
        send the newest one (or zip this whole folder). The most useful parts
        are the "Exception Type" line near the top and the backtrace of the
        crashing thread. They contain no message contents or passwords — only
        the app's own stack and system state.
        """
        try? text.data(using: .utf8)?.write(to: dir.appendingPathComponent("README.txt"))
    }

    #if canImport(AppKit)
    @MainActor private static func presentNoReportsAlert() {
        let alert = NSAlert()
        alert.messageText = "No crash reports found"
        alert.informativeText = "PurpleIRC hasn’t recorded any crash reports on this Mac. "
            + "macOS writes them to ~/Library/Logs/DiagnosticReports/ after a crash — "
            + "try again after a crash occurs."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    #endif
}

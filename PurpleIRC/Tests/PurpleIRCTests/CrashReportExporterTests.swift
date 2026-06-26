import Foundation
import Testing
@testable import PurpleIRC

/// Coverage for `CrashReportExporter` — the in-app "Export Crash Reports…"
/// helper. The Finder-reveal / NSAlert side is UI and skipped; the testable
/// seams are (1) filtering DiagnosticReports down to PurpleIRC's own `.ips` /
/// `.crash` files newest-first, and (2) copying them into a timestamped
/// `~/Downloads/PurpleIRC crash-reports/` folder with a README.
@Suite struct CrashReportExporterTests {

    /// Make a throwaway directory under the system temp area.
    private func tempDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashExportTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in dir: URL, mtime: Date) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("crash".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }

    @Test func reportsFiltersToPurpleIRCNewestFirst() throws {
        let src = try tempDir("src")
        defer { try? FileManager.default.removeItem(at: src) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try write("PurpleIRC-2026-06-20-120616.ips", in: src, mtime: base)
        let newest = try write("PurpleIRC-2026-06-25-203146.ips", in: src, mtime: base.addingTimeInterval(500))
        let legacy = try write("PurpleIRC-old.crash", in: src, mtime: base.addingTimeInterval(100))
        // Decoys that must be excluded:
        _ = try write("OtherApp-2026-06-25-000000.ips", in: src, mtime: base.addingTimeInterval(900))
        _ = try write("PurpleIRC-notes.txt", in: src, mtime: base.addingTimeInterval(900))

        let found = CrashReportExporter.reports(in: src)
        #expect(found.count == 3)
        #expect(found.allSatisfy { $0.lastPathComponent.hasPrefix("PurpleIRC-") })
        #expect(found.allSatisfy { $0.pathExtension == "ips" || $0.pathExtension == "crash" })
        // Newest first.
        #expect(found.first?.lastPathComponent == newest.lastPathComponent)
        #expect(found.contains { $0.lastPathComponent == legacy.lastPathComponent })
    }

    @Test func reportsEmptyForMissingOrEmptyDirectory() throws {
        let empty = try tempDir("empty")
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(CrashReportExporter.reports(in: empty).isEmpty)

        let missing = empty.appendingPathComponent("does-not-exist", isDirectory: true)
        #expect(CrashReportExporter.reports(in: missing).isEmpty)
    }

    @Test func exportCopiesReportsAndWritesReadme() throws {
        let src = try tempDir("src")
        let downloads = try tempDir("downloads")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: downloads) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try write("PurpleIRC-a.ips", in: src, mtime: now)
        let b = try write("PurpleIRC-b.ips", in: src, mtime: now.addingTimeInterval(10))

        let result = CrashReportExporter.export(from: [b, a], toDownloads: downloads, now: now)

        guard case let .exported(folder, count) = result else {
            Issue.record("expected .exported, got \(result)")
            return
        }
        #expect(count == 2)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("PurpleIRC-a.ips").path))
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("PurpleIRC-b.ips").path))
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("README.txt").path))
        // Landed under "~/Downloads"/PurpleIRC crash-reports/<stamp>/
        #expect(folder.deletingLastPathComponent().lastPathComponent == "PurpleIRC crash-reports")
    }

    @Test func exportWithNoReportsReturnsNone() throws {
        let downloads = try tempDir("downloads")
        defer { try? FileManager.default.removeItem(at: downloads) }
        #expect(CrashReportExporter.export(from: [], toDownloads: downloads, now: Date()) == .none)
        // Nothing should have been created.
        #expect(!FileManager.default.fileExists(
            atPath: downloads.appendingPathComponent("PurpleIRC crash-reports").path))
    }
}

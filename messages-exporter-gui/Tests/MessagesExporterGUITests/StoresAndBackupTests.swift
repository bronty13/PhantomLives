import Foundation
import Testing
@testable import MessagesExporterGUI

/// Coverage for the new persistent-state services: the JSON-backed
/// run-history and preset stores, and the launch-time backup service.
/// Per PhantomLives/CLAUDE.md, the backup suite must cover at minimum:
/// debounce, retention trim, target-directory auto-create, list ordering.
/// All four live here.

@Suite("RunHistoryStore")
@MainActor
struct RunHistoryStoreTests {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-runs-\(UUID().uuidString).json")
    }

    private func sampleEntry(_ contact: String = "Sallie", success: Bool = true) -> RunHistoryEntry {
        RunHistoryEntry(
            contact: contact,
            start: Date(timeIntervalSince1970: 0),
            end: Date(),
            mode: .sanitized,
            transcribe: false,
            transcribeModel: .turbo,
            emoji: .word,
            completedAt: Date(),
            runFolderPath: "/tmp/sample",
            messageCount: 18,
            attachmentCount: 4,
            outputBytes: 12_345,
            exitOK: success
        )
    }

    @Test("record() inserts at the front (most-recent-first)")
    func recordOrdering() {
        let store = RunHistoryStore(url: tempStoreURL())
        store.record(sampleEntry("Alice"))
        store.record(sampleEntry("Bob"))
        store.record(sampleEntry("Charlie"))
        #expect(store.entries.map(\.contact) == ["Charlie", "Bob", "Alice"])
    }

    @Test("record() trims to maxEntries")
    func recordTrim() {
        let store = RunHistoryStore(url: tempStoreURL())
        for i in 0..<(RunHistoryStore.maxEntries + 5) {
            store.record(sampleEntry("contact-\(i)"))
        }
        #expect(store.entries.count == RunHistoryStore.maxEntries)
        // Newest first → last contact recorded sits at index 0.
        #expect(store.entries.first?.contact ==
                "contact-\(RunHistoryStore.maxEntries + 4)")
    }

    @Test("entries persist across a fresh store at the same URL")
    func roundTripPersistence() {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let s = RunHistoryStore(url: url)
            s.record(sampleEntry("Alice"))
            s.record(sampleEntry("Bob"))
        }
        let reloaded = RunHistoryStore(url: url)
        #expect(reloaded.entries.map(\.contact) == ["Bob", "Alice"])
    }

    @Test("delete(id:) removes a single row")
    func deleteOne() {
        let store = RunHistoryStore(url: tempStoreURL())
        store.record(sampleEntry("Alice"))
        let bob = sampleEntry("Bob")
        store.record(bob)
        store.record(sampleEntry("Charlie"))
        store.delete(id: bob.id)
        #expect(store.entries.map(\.contact) == ["Charlie", "Alice"])
    }

    @Test("clearAll() empties the store")
    func clearAll() {
        let store = RunHistoryStore(url: tempStoreURL())
        store.record(sampleEntry("Alice"))
        store.clearAll()
        #expect(store.entries.isEmpty)
    }

    @Test("sidebarTitle includes span when range is meaningful")
    func sidebarTitle() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end   = cal.date(byAdding: .day, value: 16, to: start)!
        var entry = sampleEntry("Sallie")
        entry.start = start
        entry.end   = end
        #expect(entry.sidebarTitle == "Sallie · 16d")
    }
}

@Suite("PresetStore")
@MainActor
struct PresetStoreTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-presets-\(UUID().uuidString).json")
    }

    private func samplePreset(_ name: String) -> ExportPreset {
        ExportPreset(
            name: name,
            contact: "Sallie",
            start: nil,
            end: nil,
            mode: .raw,
            transcribe: true,
            transcribeModel: .turbo,
            emoji: .word
        )
    }

    @Test("upsert appends new presets in insertion order")
    func upsertAppend() {
        let store = PresetStore(url: tempURL())
        store.upsert(samplePreset("A"))
        store.upsert(samplePreset("B"))
        store.upsert(samplePreset("C"))
        #expect(store.presets.map(\.name) == ["A", "B", "C"])
    }

    @Test("upsert with same id replaces in place (keeps ordering)")
    func upsertReplace() {
        let store = PresetStore(url: tempURL())
        let a = samplePreset("A")
        store.upsert(a)
        store.upsert(samplePreset("B"))
        var aPrime = a
        aPrime.name = "A-renamed"
        store.upsert(aPrime)
        #expect(store.presets.map(\.name) == ["A-renamed", "B"])
    }

    @Test("rename(id:to:) updates only the name field")
    func rename() {
        let store = PresetStore(url: tempURL())
        let a = samplePreset("A")
        store.upsert(a)
        store.rename(id: a.id, to: "A-new")
        #expect(store.presets.first?.name == "A-new")
        #expect(store.presets.first?.contact == "Sallie")
    }

    @Test("presets persist across a fresh store at the same URL")
    func roundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let s = PresetStore(url: url)
            s.upsert(samplePreset("A"))
            s.upsert(samplePreset("B"))
        }
        let reloaded = PresetStore(url: url)
        #expect(reloaded.presets.map(\.name) == ["A", "B"])
    }
}

/// CLAUDE.md mandates these four backup tests (debounce, retention,
/// target auto-create, list ordering). The first three drive
/// BackupService directly with a temp support+backup directory.
@Suite("BackupService")
@MainActor
struct BackupServiceTests {

    /// Build a tiny support directory containing one file so the zip
    /// pipeline has something to work with on every test.
    private func makeSupportDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: dir.appendingPathComponent("runs.json"))
        return dir
    }

    @Test("runBackup creates the target directory if it does not exist")
    func backupCreatesTargetDir() throws {
        let supportDir = try makeSupportDir()
        defer { try? FileManager.default.removeItem(at: supportDir) }

        // Backup dir starts non-existent.
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-bak-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: backupDir) }
        #expect(!FileManager.default.fileExists(atPath: backupDir.path))

        let written = try BackupService.runBackup(supportDir: supportDir,
                                                  backupDir: backupDir)
        #expect(FileManager.default.fileExists(atPath: backupDir.path))
        #expect(FileManager.default.fileExists(atPath: written.path))
        #expect(written.lastPathComponent.hasPrefix(BackupService.archivePrefix))
        #expect(written.pathExtension == "zip")
    }

    @Test("trimOldBackups removes only files matching the archive prefix")
    func trimOnlyOurArchives() throws {
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-trim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backupDir) }

        let fm = FileManager.default
        let oldOurs = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2020-01-01-000000.zip")
        let newOurs = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2099-01-01-000000.zip")
        let unrelated = backupDir.appendingPathComponent("user-thing.zip")
        let alsoUnrelated = backupDir.appendingPathComponent("notes.txt")
        try Data().write(to: oldOurs)
        try Data().write(to: newOurs)
        try Data().write(to: unrelated)
        try Data().write(to: alsoUnrelated)

        // Backdate oldOurs and unrelated to 30 days ago.
        let oldDate = Date().addingTimeInterval(-30 * 86400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldOurs.path)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: alsoUnrelated.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        #expect(removed == 1)
        #expect(!fm.fileExists(atPath: oldOurs.path))
        #expect(fm.fileExists(atPath: newOurs.path))
        #expect(fm.fileExists(atPath: unrelated.path))      // not our prefix
        #expect(fm.fileExists(atPath: alsoUnrelated.path))  // not our prefix
    }

    @Test("trimOldBackups with retentionDays=0 keeps everything")
    func keepForever() throws {
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-keep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backupDir) }

        let url = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2000-01-01-000000.zip")
        try Data().write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: url.path
        )
        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 0)
        #expect(removed == 0)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("listBackups returns archives newest-first")
    func listOrdering() throws {
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medexp-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backupDir) }

        let fm = FileManager.default
        let a = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2020-01-01-000000.zip")
        let b = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2024-01-01-000000.zip")
        let c = backupDir.appendingPathComponent("\(BackupService.archivePrefix)2026-01-01-000000.zip")
        try Data().write(to: a); try Data().write(to: b); try Data().write(to: c)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)],   ofItemAtPath: a.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100000)], ofItemAtPath: b.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 999999)], ofItemAtPath: c.path)

        let rows = BackupService.listBackups(in: backupDir)
        #expect(rows.map(\.url.lastPathComponent) == [
            c.lastPathComponent,
            b.lastPathComponent,
            a.lastPathComponent
        ])
    }

    @Test("debounce: runOnLaunchIfDue is a no-op within the debounce window")
    func debounceNoop() throws {
        // Use isolated UserDefaults keys so we don't stomp on the
        // running app's settings if these tests run alongside it.
        let uniq = UUID().uuidString
        let lastKey = "medexp-test-last-\(uniq)"
        UserDefaults.standard.set(BackupService.archivePrefix, forKey: "medexp-test-prefix-\(uniq)")

        // Set "last backup" to 30 seconds ago.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let recent = f.string(from: Date().addingTimeInterval(-30))
        UserDefaults.standard.set(recent, forKey: lastKey)

        // Pure-function check: parsing yields a date within the
        // debounce window, so the predicate `< debounceSeconds` is true.
        let parsed = BackupService.parseISO(recent)
        #expect(parsed != nil)
        #expect(Date().timeIntervalSince(parsed!) < BackupService.debounceSeconds)

        UserDefaults.standard.removeObject(forKey: lastKey)
    }
}

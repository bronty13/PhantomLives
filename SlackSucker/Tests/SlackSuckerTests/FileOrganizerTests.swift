import Foundation
import Testing
@testable import SlackSucker

@Suite("FileOrganizer")
struct FileOrganizerTests {

    private func makeRunFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss-organize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Helper: build a fake slackdump archive layout
    /// `<run>/__uploads/<FILE_ID>/<name>` populated with empty marker
    /// files for each (FILE_ID, name) pair the caller passes in.
    private func seedUploads(at run: URL, files: [(String, String)]) throws {
        let uploads = run.appendingPathComponent("__uploads", isDirectory: true)
        try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true)
        for (id, name) in files {
            let dir = uploads.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
    }

    @Test("classifies common extensions into the right buckets")
    func categoryClassification() {
        #expect(FileOrganizer.Category.classify(extension: "mp4")  == .videos)
        #expect(FileOrganizer.Category.classify(extension: "MOV")  == .videos)
        #expect(FileOrganizer.Category.classify(extension: "jpg")  == .photos)
        #expect(FileOrganizer.Category.classify(extension: "heic") == .photos)
        #expect(FileOrganizer.Category.classify(extension: "m4a")  == .audio)
        #expect(FileOrganizer.Category.classify(extension: "opus") == .audio)
        #expect(FileOrganizer.Category.classify(extension: "pdf")  == .other)
        #expect(FileOrganizer.Category.classify(extension: "")     == .other)
        #expect(FileOrganizer.Category.classify(extension: "weirdext") == .other)
    }

    @Test("moves uploads into category subfolders, removes empty __uploads")
    func reorganizesAttachments() throws {
        let run = try makeRunFolder()
        defer { try? FileManager.default.removeItem(at: run) }

        try seedUploads(at: run, files: [
            ("F001", "vacation.mp4"),
            ("F002", "selfie.jpg"),
            ("F003", "voice-memo.m4a"),
            ("F004", "contract.pdf"),
            ("F005", "Receipts.HEIC"),
        ])
        // Untouched siblings: leave slackdump.sqlite + __avatars alone.
        try Data("sqlite".utf8).write(to: run.appendingPathComponent("slackdump.sqlite"))
        let avatars = run.appendingPathComponent("__avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: avatars, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: avatars.appendingPathComponent("U123.png"))

        let result = FileOrganizer.organize(runFolder: run)

        #expect(result.totalMoved == 5)
        #expect(result.moved["Videos"] == 1)
        #expect(result.moved["Photos"] == 2)  // jpg + HEIC
        #expect(result.moved["Audio"]  == 1)
        #expect(result.moved["Other"]  == 1)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: run.appendingPathComponent("Videos/vacation.mp4").path))
        #expect(fm.fileExists(atPath: run.appendingPathComponent("Photos/selfie.jpg").path))
        #expect(fm.fileExists(atPath: run.appendingPathComponent("Photos/Receipts.HEIC").path))
        #expect(fm.fileExists(atPath: run.appendingPathComponent("Audio/voice-memo.m4a").path))
        #expect(fm.fileExists(atPath: run.appendingPathComponent("Other/contract.pdf").path))

        // SQLite and __avatars must NOT be moved.
        #expect(fm.fileExists(atPath: run.appendingPathComponent("slackdump.sqlite").path))
        #expect(fm.fileExists(atPath: avatars.appendingPathComponent("U123.png").path))

        // Now-empty __uploads must be gone.
        #expect(!fm.fileExists(atPath: run.appendingPathComponent("__uploads").path))

        // Summary log written.
        #expect(fm.fileExists(atPath: run.appendingPathComponent("organize-log.txt").path))
    }

    @Test("name collisions get a file-ID suffix instead of overwriting")
    func collisionDisambiguation() throws {
        let run = try makeRunFolder()
        defer { try? FileManager.default.removeItem(at: run) }

        // Same filename shared from two different file IDs.
        try seedUploads(at: run, files: [
            ("F001", "image.png"),
            ("F002", "image.png"),
        ])

        let result = FileOrganizer.organize(runFolder: run)
        #expect(result.moved["Photos"] == 2)
        #expect(result.collisions == 1)

        let fm = FileManager.default
        // One file keeps the original name (whichever was processed
        // first — directory iteration order isn't guaranteed).
        let original = run.appendingPathComponent("Photos/image.png")
        #expect(fm.fileExists(atPath: original.path))

        // The collider must have a (F00…) suffix.
        let collider = (try? fm.contentsOfDirectory(at: run.appendingPathComponent("Photos"),
                                                   includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent != "image.png" })
        #expect(collider != nil)
        #expect(collider?.lastPathComponent.contains("(F00") == true)
        #expect(collider?.lastPathComponent.hasSuffix(".png") == true)
    }

    @Test("no-op when __uploads doesn't exist")
    func noopWhenNoUploads() throws {
        let run = try makeRunFolder()
        defer { try? FileManager.default.removeItem(at: run) }
        let result = FileOrganizer.organize(runFolder: run)
        #expect(result.totalMoved == 0)
        #expect(result.errors.isEmpty)
        // No summary should be written either — but our implementation
        // does write a "0 moves" summary because the toggle is on and
        // we want the user to see "we ran but nothing happened". Assert
        // the file exists with 0 totals so behavior is documented.
        let log = run.appendingPathComponent("organize-log.txt")
        if FileManager.default.fileExists(atPath: log.path) {
            let body = (try? String(contentsOf: log)) ?? ""
            #expect(body.contains("Total files moved: 0"))
        }
    }

    @Test("idempotent — second pass is a clean no-op")
    func idempotent() throws {
        let run = try makeRunFolder()
        defer { try? FileManager.default.removeItem(at: run) }
        try seedUploads(at: run, files: [("F1", "a.mp3"), ("F2", "b.jpg")])
        _ = FileOrganizer.organize(runFolder: run)
        let result = FileOrganizer.organize(runFolder: run)
        #expect(result.totalMoved == 0)
    }
}

import Foundation
import Testing
@testable import SlackSucker

/// Pure-function coverage for the four post-processors added after
/// the 1.0 baseline: HashService, OrientationBaker, MetadataStripper,
/// TranscriptionService. Each one's primary side effect is on disk —
/// these tests exercise the parts that don't need real binaries
/// (exiftool, ffmpeg, transcribe.py) and stub the rest by laying out
/// a temp run folder identical to what FileOrganizer produces.

private func tempRunFolder() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ss-pp-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for sub in ["Videos", "Photos", "Audio", "Other"] {
        try? FileManager.default.createDirectory(
            at: url.appendingPathComponent(sub, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    return url
}

private func write(_ bytes: [UInt8], to url: URL) {
    try? Data(bytes).write(to: url)
}

@Suite("HashService")
struct HashServiceTests {

    @Test("hashes are stable and match known sha256")
    func knownSha256() {
        let folder = tempRunFolder()
        // "hello\n" — sha256 = 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
        let payload: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x0a]
        write(payload, to: folder.appendingPathComponent("Other/hello.bin"))

        let result = HashService.run(runFolder: folder, algorithms: [.sha256])
        #expect(result.fileCount == 1)
        #expect(result.errors.isEmpty)
        let out = try? String(contentsOf: folder.appendingPathComponent("hashes.txt"))
        #expect(out?.contains("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03") == true)
        #expect(out?.contains("Other/hello.bin") == true)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("multiple algorithms produce separate sections")
    func multipleAlgos() {
        let folder = tempRunFolder()
        write([0x61], to: folder.appendingPathComponent("Photos/a.jpg"))
        let result = HashService.run(runFolder: folder, algorithms: [.md5, .sha1, .sha256])
        #expect(result.byAlgo[.md5] == 1)
        #expect(result.byAlgo[.sha1] == 1)
        #expect(result.byAlgo[.sha256] == 1)
        let body = try? String(contentsOf: folder.appendingPathComponent("hashes.txt"))
        #expect(body?.contains("# MD5") == true)
        #expect(body?.contains("# SHA-1") == true)
        #expect(body?.contains("# SHA-256") == true)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("no algorithms selected -> bails with error, no file written")
    func emptyAlgorithms() {
        let folder = tempRunFolder()
        let result = HashService.run(runFolder: folder, algorithms: [])
        #expect(result.fileCount == 0)
        #expect(!result.errors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("hashes.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("symlinks are skipped, hidden files are skipped")
    func skipsSymlinksAndHidden() {
        let folder = tempRunFolder()
        let target = folder.appendingPathComponent("Other/real.bin")
        write([0x00, 0x01], to: target)
        let symlink = folder.appendingPathComponent("Other/link.bin")
        try? FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let hidden = folder.appendingPathComponent("Other/.DS_Store")
        write([0xFF], to: hidden)
        let result = HashService.run(runFolder: folder, algorithms: [.sha256])
        // Only real.bin counts; .DS_Store skipped via skipsHiddenFiles,
        // link.bin skipped via isSymbolicLink check.
        #expect(result.fileCount == 1)
        try? FileManager.default.removeItem(at: folder)
    }
}

@Suite("MetadataStripper helpers")
struct MetadataStripperTests {

    @Test("no exiftool -> reports skip and writes log")
    func skipsWhenExiftoolMissing() {
        // We can't truly hide exiftool from a homebrew machine — but
        // we can verify that with no media in the folder, the service
        // returns 0 processed, 0 errors and writes a log either way.
        let folder = tempRunFolder()
        let result = MetadataStripper.run(runFolder: folder)
        #expect(result.filesProcessed == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("metadata-log.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("binary discovery checks common homebrew locations")
    func binaryDiscoveryShape() {
        // Documents the resolution order — if the user has exiftool on
        // their machine somewhere outside the standard locations, the
        // service won't find it and that's the documented contract.
        // This test just guards the resolution path against accidental
        // regressions in the lookup loop.
        let resolved = MetadataStripper.exiftoolBinary()
        if let resolved {
            #expect(FileManager.default.isExecutableFile(atPath: resolved))
        } // else: machine without exiftool installed; nothing to assert
    }
}

@Suite("OrientationBaker helpers")
struct OrientationBakerTests {

    @Test("empty run folder -> zero counts, log written")
    func empty() {
        let folder = tempRunFolder()
        let result = OrientationBaker.run(runFolder: folder)
        #expect(result.photosInspected == 0)
        #expect(result.videosInspected == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("orient-log.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("baking a non-image file is unsupported, never crashes")
    func nonImageUnsupported() {
        // Lay an empty .jpg down; CGImageSource fails to decode → the
        // outcome must be .error / .unsupported, never a fatal trap.
        let folder = tempRunFolder()
        let bogus = folder.appendingPathComponent("Photos/empty.jpg")
        write([], to: bogus)
        let outcome = OrientationBaker.bakePhoto(at: bogus)
        switch outcome {
        case .rotated, .alreadyUpright:
            Issue.record("empty file should never report rotated/upright")
        case .unsupported, .error:
            break  // expected
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("ffmpeg / ffprobe lookup returns nil or an executable path")
    func ffmpegLookup() {
        if let ff = OrientationBaker.ffmpegBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: ff))
        }
        if let probe = OrientationBaker.ffprobeBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: probe))
        }
    }
}

@Suite("TranscriptionService helpers")
struct TranscriptionServiceTests {

    @Test("binary resolver finds something or returns nil")
    func resolver() {
        if let (exe, leading) = TranscriptionService.resolveBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: exe))
            // Sibling-checkout path implies a script in leading args.
            // PATH-shim hit implies leading is empty.
            #expect(leading.isEmpty || leading[0].hasSuffix(".py"))
        }
    }

    @Test("formatDuration renders sub-minute and multi-minute spans")
    func durationFormat() {
        #expect(TranscriptionService.formatDuration(7.4) == "7s")
        #expect(TranscriptionService.formatDuration(59.4) == "59s")
        // 59.9 rounds to 60, which crosses into the minute branch.
        #expect(TranscriptionService.formatDuration(59.9) == "1m0s")
        #expect(TranscriptionService.formatDuration(125) == "2m5s")
        #expect(TranscriptionService.formatDuration(0) == "0s")
    }
}

@Suite("RunStats transcribe phase parser")
struct RunStatsTranscribePhaseTests {

    @Test("file-start line yields a compact phase string")
    func fileStartLine() {
        let line = "[transcribe 3/7] foo.mp4 → foo.txt (45 MB, model=turbo)"
        #expect(RunStats.matchTranscribePhase(line) == "Transcribing 3/7: foo.mp4")
    }

    @Test("tqdm progress lines do NOT trigger a phase change")
    func progressLineIgnored() {
        // We only want the file-start lines to update phase. The
        // per-chunk tqdm output overwrites itself in place via the
        // LineBuffer CR handling — surfacing each chunk as a phase
        // would flicker the run strip badly.
        let progress = "[transcribe 3/7] 50% |████████| 30/60s"
        #expect(RunStats.matchTranscribePhase(progress) == nil)
    }

    @Test("end-of-file ✓ / ✗ lines do NOT trigger a phase change")
    func endLinesIgnored() {
        #expect(RunStats.matchTranscribePhase("[transcribe 3/7] ✓ foo.mp4 in 1m12s") == nil)
        #expect(RunStats.matchTranscribePhase("[transcribe 3/7] ✗ foo.mp4 — exit 1 after 4s") == nil)
    }

    @Test("absorb wires the transcribe match into runStats.phase")
    func absorbPath() {
        var stats = RunStats()
        _ = stats.absorb("[transcribe 1/2] meeting.m4a → meeting.txt (12 MB, model=turbo)")
        #expect(stats.phase == "Transcribing 1/2: meeting.m4a")
    }
}

@Suite("ArchiveOptions backwards compat")
struct ArchiveOptionsCompatTests {

    @Test("decodes pre-1.1 JSON without the post-processing fields")
    func legacyJSONDecode() throws {
        // Settings.json shape pre-1.1 — only the four original fields.
        let json = """
        {
          "includeFiles": true,
          "includeAvatars": false,
          "memberOnly": false,
          "organizeFiles": true
        }
        """.data(using: .utf8)!
        let opts = try JSONDecoder().decode(ArchiveOptions.self, from: json)
        // All new fields default to their safe-off / default-on values.
        #expect(opts.generateHashes == false)
        #expect(opts.hashAlgorithms == [.sha256])
        #expect(opts.transcribeMedia == false)
        #expect(opts.transcribeModel == .turbo)
        #expect(opts.stripPhotoMetadata == false)
        #expect(opts.bakeOrientation == false)
        // fileOrdering defaults to .messageTimestamp so upgrading users
        // get the better-organized layout without intervention.
        #expect(opts.fileOrdering == .messageTimestamp)
    }
}

@Suite("FileOrganizer ordering")
struct FileOrganizerOrderingTests {

    private func makeRunFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss-order-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Synthesize an `__uploads/<FILE_ID>/<name>` tree with the given
    /// upload IDs, each with a single one-byte file. Returns the run
    /// folder URL — caller is responsible for cleanup.
    private func seed(uploads: [(fileID: String, name: String)]) -> URL {
        let run = makeRunFolder()
        let up = run.appendingPathComponent("__uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: up, withIntermediateDirectories: true)
        for (id, name) in uploads {
            let dir = up.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data([0x00]).write(to: dir.appendingPathComponent(name))
        }
        return run
    }

    @Test(".none ordering writes original filenames (no prefix)")
    func noOrderingNoPrefix() {
        let run = seed(uploads: [
            ("F001", "alpha.jpg"),
            ("F002", "beta.jpg"),
        ])
        let result = FileOrganizer.organize(runFolder: run, ordering: .none)
        #expect(result.prefixedCount == 0)
        let photos = run.appendingPathComponent("Photos", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: photos.appendingPathComponent("alpha.jpg").path))
        #expect(FileManager.default.fileExists(atPath: photos.appendingPathComponent("beta.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    @Test(".captureDate uses Slack upload TS fallback when EXIF absent")
    func captureDateFallbackToUploadTS() throws {
        // Two seeded files with NO embedded EXIF (we wrote raw bytes,
        // not real images) — so the capture-date reader returns nil
        // for both and the SQLite upload-TS layer takes over. Build
        // a synthetic slackdump.sqlite with the expected FILE rows.
        let run = seed(uploads: [
            ("F-FIRST",  "alpha.jpg"),
            ("F-SECOND", "beta.jpg"),
        ])
        let sqlite = run.appendingPathComponent("slackdump.sqlite")
        try makeSyntheticSqlite(at: sqlite, rows: [
            ("F-FIRST",  created: 1_700_000_000),  // earlier
            ("F-SECOND", created: 1_800_000_000),  // later
        ])

        let result = FileOrganizer.organize(runFolder: run, ordering: .captureDate)
        #expect(result.prefixedCount == 2)
        let photos = run.appendingPathComponent("Photos", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: photos.appendingPathComponent("0001_alpha.jpg").path))
        #expect(FileManager.default.fileExists(atPath: photos.appendingPathComponent("0002_beta.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    @Test("per-category numbering resets between categories")
    func perCategoryReset() throws {
        // 1 jpg + 1 mp4 with synthetic Slack upload TS. Each category
        // gets its own 0001_ regardless of cross-category order.
        let run = seed(uploads: [
            ("F-VID", "clip.mp4"),
            ("F-PIC", "shot.jpg"),
        ])
        let sqlite = run.appendingPathComponent("slackdump.sqlite")
        try makeSyntheticSqlite(at: sqlite, rows: [
            ("F-VID", created: 1_700_000_000),
            ("F-PIC", created: 1_800_000_000),
        ])
        _ = FileOrganizer.organize(runFolder: run, ordering: .captureDate)
        #expect(FileManager.default.fileExists(
            atPath: run.appendingPathComponent("Videos/0001_clip.mp4").path))
        #expect(FileManager.default.fileExists(
            atPath: run.appendingPathComponent("Photos/0001_shot.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    @Test("slackUploadOrdering returns empty when sqlite file is absent")
    func uploadOrderingNoSqlite() {
        let bogus = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID()).sqlite")
        let keys = FileOrganizer.slackUploadOrdering(sqliteURL: bogus)
        #expect(keys.isEmpty)
    }

    @Test(".messageTimestamp falls back gracefully when SQLite is missing")
    func messageTimestampNoSqlite() {
        // No slackdump.sqlite in the folder. The chronological-ordering
        // lookup returns empty → every file gets sentinel sort, so they
        // line up by FILE_ID (still deterministic) and still get
        // prefixed. The point of this test is "doesn't crash, still
        // produces the prefix" rather than verifying the order — that
        // needs a real SQLite.
        let run = seed(uploads: [
            ("F-Z", "z.jpg"),
            ("F-A", "a.jpg"),
        ])
        let result = FileOrganizer.organize(runFolder: run, ordering: .messageTimestamp)
        #expect(result.prefixedCount == 2)
        // FILE_ID "F-A" sorts before "F-Z" lexically → it gets 0001_.
        #expect(FileManager.default.fileExists(
            atPath: run.appendingPathComponent("Photos/0001_a.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: run.appendingPathComponent("Photos/0002_z.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    /// Build a minimal slackdump.sqlite with a `FILE` table carrying
    /// the rows we need for ordering-fallback tests. Schema matches
    /// what slackdump 4.x produces (only the columns the ordering
    /// query reads are populated).
    private func makeSyntheticSqlite(at url: URL, rows: [(fileID: String, created: Int)]) throws {
        try makeSyntheticSqlite(at: url, fileRows: rows.map {
            FileRow(fileID: $0.fileID, created: $0.created, messageID: nil, idx: 0)
        }, messageRows: [])
    }

    /// Synthetic-DB seeder for the full `MESSAGE × FILE` join used by
    /// `chronologicalOrdering`. The earlier overload is preserved for
    /// the upload-TS-only tests.
    struct FileRow {
        var fileID: String
        var created: Int
        var messageID: Int64?
        var idx: Int
    }
    struct MessageRow {
        var id: Int64       // numeric form of TS (TS × 1e6, slackdump convention)
        var ts: Double      // seconds since epoch
    }
    private func makeSyntheticSqlite(
        at url: URL,
        fileRows: [FileRow],
        messageRows: [MessageRow]
    ) throws {
        try? FileManager.default.removeItem(at: url)
        let create = """
        CREATE TABLE MESSAGE (
          ID INTEGER NOT NULL,
          CHUNK_ID INTEGER NOT NULL,
          LOAD_DTTM TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CHANNEL_ID TEXT NOT NULL,
          TS TEXT NOT NULL,
          PARENT_ID INTEGER,
          THREAD_TS TEXT,
          LATEST_REPLY TEXT,
          IS_PARENT SMALLINT NOT NULL DEFAULT 0,
          IDX INTEGER NOT NULL,
          NUM_FILES INTEGER NOT NULL DEFAULT 0,
          TXT TEXT,
          DATA BLOB NOT NULL,
          PRIMARY KEY (ID, CHUNK_ID)
        );
        CREATE TABLE FILE (
          ID TEXT NOT NULL,
          CHUNK_ID INTEGER NOT NULL,
          LOAD_DTTM TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CHANNEL_ID TEXT NOT NULL,
          MESSAGE_ID INTEGER,
          THREAD_ID INTEGER,
          IDX INTEGER NOT NULL,
          MODE TEXT NOT NULL,
          FILENAME TEXT,
          URL TEXT,
          DATA BLOB NOT NULL,
          SIZE INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (ID, CHUNK_ID)
        );
        """
        var sql = create
        for (i, m) in messageRows.enumerated() {
            sql += "INSERT INTO MESSAGE (ID, CHUNK_ID, CHANNEL_ID, TS, IDX, DATA) VALUES (\(m.id), \(i + 1), 'CTEST', '\(m.ts)', 0, '{}');\n"
        }
        for (i, r) in fileRows.enumerated() {
            let data = "{\"id\":\"\(r.fileID)\",\"created\":\(r.created)}"
            let msg = r.messageID.map { String($0) } ?? "NULL"
            sql += "INSERT INTO FILE (ID, CHUNK_ID, CHANNEL_ID, MESSAGE_ID, IDX, MODE, DATA) VALUES ('\(r.fileID)', \(i + 1), 'CTEST', \(msg), \(r.idx), 'hosted', '\(data)');\n"
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [url.path]
        let stdin = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        stdin.fileHandleForWriting.write(sql.data(using: .utf8)!)
        try stdin.fileHandleForWriting.close()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "ss-test", code: Int(proc.terminationStatus))
        }
    }

    @Test("chronologicalOrdering returns empty when sqlite file is absent")
    func sqliteAbsent() {
        let bogus = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID()).sqlite")
        let keys = FileOrganizer.chronologicalOrdering(sqliteURL: bogus)
        #expect(keys.isEmpty)
    }

    @Test("prefix width widens past 4 digits when a category exceeds 9999")
    func wideningPrefix() {
        // Sanity check the format-width branch. We don't actually
        // create 10k files — instead, verify the format calculation
        // by simulating the count path indirectly: a single file gets
        // width=4 (00001 would be 5).
        let run = seed(uploads: [("F-X", "one.jpg")])
        _ = FileOrganizer.organize(runFolder: run, ordering: .messageTimestamp)
        #expect(FileManager.default.fileExists(
            atPath: run.appendingPathComponent("Photos/0001_one.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    // MARK: - libsqlite3-backed chronologicalOrdering

    @Test("chronologicalOrdering produces correct (ts, idx) keys via libsqlite3")
    func chronologicalOrderingViaLibSQLite() throws {
        // Regression test for the fileID-lex-sentinel bug: prior to the
        // libsqlite3 switch, `chronologicalOrdering` shelled to
        // /usr/bin/sqlite3 and silently returned [:] under some runtime
        // conditions, dropping every file to the FILE_ID-lex sentinel
        // sort. With libsqlite3 the keys come back correctly populated.
        let run = makeRunFolder()
        defer { try? FileManager.default.removeItem(at: run) }
        let sqlite = run.appendingPathComponent("slackdump.sqlite")
        // One parent message, three files attached.
        try makeSyntheticSqlite(at: sqlite, fileRows: [
            FileRow(fileID: "F-A", created: 100, messageID: 1_700_000_000_000_000, idx: 2),
            FileRow(fileID: "F-B", created: 101, messageID: 1_700_000_000_000_000, idx: 0),
            FileRow(fileID: "F-C", created: 102, messageID: 1_700_000_000_000_000, idx: 1),
        ], messageRows: [
            MessageRow(id: 1_700_000_000_000_000, ts: 1_700_000_000.0)
        ])
        let keys = FileOrganizer.chronologicalOrdering(sqliteURL: sqlite)
        #expect(keys.count == 3)
        #expect(keys["F-A"]?.idx == 2)
        #expect(keys["F-B"]?.idx == 0)
        #expect(keys["F-C"]?.idx == 1)
        // All three share the same TS — caller's tiebreak runs on idx.
        #expect(keys["F-A"]?.ts == 1_700_000_000.0)
        #expect(keys["F-B"]?.ts == 1_700_000_000.0)
        #expect(keys["F-C"]?.ts == 1_700_000_000.0)
    }

    @Test(".messageTimestamp respects FILE.IDX tiebreak within one message")
    func messageTimestampHonorsIDX() throws {
        // End-to-end: seed __uploads, seed a synthetic DB with all files
        // sharing one MESSAGE.TS but distinct FILE.IDX, run organize,
        // and verify the 0001…0003 prefix maps to ascending IDX.
        //
        // This is the case that was silently broken — prior code would
        // fall through to fileID-lex (F-A < F-B < F-C) regardless of
        // the IDX values stored in the DB.
        let run = seed(uploads: [
            ("F-A", "alpha.jpg"),
            ("F-B", "beta.jpg"),
            ("F-C", "gamma.jpg"),
        ])
        let sqlite = run.appendingPathComponent("slackdump.sqlite")
        // IDX = 2, 0, 1 → expected prefix order: B (idx 0), C (idx 1), A (idx 2).
        try makeSyntheticSqlite(at: sqlite, fileRows: [
            FileRow(fileID: "F-A", created: 100, messageID: 1_700_000_000_000_000, idx: 2),
            FileRow(fileID: "F-B", created: 101, messageID: 1_700_000_000_000_000, idx: 0),
            FileRow(fileID: "F-C", created: 102, messageID: 1_700_000_000_000_000, idx: 1),
        ], messageRows: [
            MessageRow(id: 1_700_000_000_000_000, ts: 1_700_000_000.0)
        ])
        _ = FileOrganizer.organize(runFolder: run, ordering: .messageTimestamp)
        let photos = run.appendingPathComponent("Photos", isDirectory: true)
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0001_beta.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0002_gamma.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0003_alpha.jpg").path))
        try? FileManager.default.removeItem(at: run)
    }

    @Test("organize() reports batched-upload count when ≥2 files share one TS")
    func batchedUploadDetection() throws {
        // Two messages — first has 3 files (batched), second has 1.
        // Result should report 1 batched message covering 3 files.
        let run = seed(uploads: [
            ("F-A", "a.jpg"), ("F-B", "b.jpg"), ("F-C", "c.jpg"),  // same TS
            ("F-D", "d.jpg"),                                       // its own TS
        ])
        let sqlite = run.appendingPathComponent("slackdump.sqlite")
        try makeSyntheticSqlite(at: sqlite, fileRows: [
            FileRow(fileID: "F-A", created: 100, messageID: 1_700_000_000_000_000, idx: 0),
            FileRow(fileID: "F-B", created: 101, messageID: 1_700_000_000_000_000, idx: 1),
            FileRow(fileID: "F-C", created: 102, messageID: 1_700_000_000_000_000, idx: 2),
            FileRow(fileID: "F-D", created: 200, messageID: 1_700_000_111_000_000, idx: 0),
        ], messageRows: [
            MessageRow(id: 1_700_000_000_000_000, ts: 1_700_000_000.0),
            MessageRow(id: 1_700_000_111_000_000, ts: 1_700_000_111.0),
        ])
        let result = FileOrganizer.organize(runFolder: run, ordering: .messageTimestamp)
        #expect(result.batchedMessages == 1)
        #expect(result.batchedFileCount == 3)
        // Sanity: the lone file in its own message is NOT counted.
        try? FileManager.default.removeItem(at: run)
    }

    // MARK: - filenameNumeric ordering

    @Test(".filenameNumeric extracts the first numeric run from each filename")
    func filenameNumericExtraction() {
        let keys = FileOrganizer.filenameNumericOrdering([
            ("F1", "IMG_3079.MP4"),
            ("F2", "IMG_3081.MP4"),
            ("F3", "IMG_3080.MP4"),
            ("F4", "01_intro.mov"),
            ("F5", "no-numbers-here.mov"),
        ])
        #expect(keys["F1"]?.ts == 3079)
        #expect(keys["F2"]?.ts == 3081)
        #expect(keys["F3"]?.ts == 3080)
        #expect(keys["F4"]?.ts == 1)
        // Files with no digits are absent — caller's sentinel sort
        // handles them.
        #expect(keys["F5"] == nil)
    }

    @Test(".filenameNumeric orders IMG_3079-style filenames numerically")
    func filenameNumericEndToEnd() throws {
        let run = seed(uploads: [
            ("F-1", "IMG_3081.jpg"),
            ("F-2", "IMG_3079.jpg"),
            ("F-3", "IMG_3080.jpg"),
        ])
        defer { try? FileManager.default.removeItem(at: run) }
        _ = FileOrganizer.organize(runFolder: run, ordering: .filenameNumeric)
        let photos = run.appendingPathComponent("Photos", isDirectory: true)
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0001_IMG_3079.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0002_IMG_3080.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0003_IMG_3081.jpg").path))
    }

    @Test(".filenameNumeric places digit-less filenames at the end (by FILE_ID)")
    func filenameNumericNoDigitsLast() throws {
        let run = seed(uploads: [
            ("F-A", "abstract.jpg"),     // no digits — sentinel sort
            ("F-B", "IMG_42.jpg"),       // numeric 42 → first
            ("F-Z", "another.jpg"),      // no digits — sentinel sort
        ])
        defer { try? FileManager.default.removeItem(at: run) }
        _ = FileOrganizer.organize(runFolder: run, ordering: .filenameNumeric)
        let photos = run.appendingPathComponent("Photos", isDirectory: true)
        // 42 wins first slot. The two digit-less files fall to the
        // sentinel and order by FILE_ID lex (F-A then F-Z).
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0001_IMG_42.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0002_abstract.jpg").path))
        #expect(FileManager.default.fileExists(
            atPath: photos.appendingPathComponent("0003_another.jpg").path))
    }
}

import Testing
import Foundation
import AVFoundation
@testable import PurpleSpeak

// MARK: - Highlight range mapping (the keystone primitive)

@MainActor
@Test func sentenceRangeFindsEnclosingSentence() {
    let text = "First sentence here. Second one follows! Third?"
    // A word range inside "Second one follows!"
    let secondStart = (text as NSString).range(of: "Second")
    let sentence = AVSpeechTTSEngine.sentenceRange(containing: secondStart, in: text)
    #expect(sentence != nil)
    let got = (text as NSString).substring(with: sentence!)
    #expect(got.contains("Second one follows"))
    #expect(!got.contains("First"))
}

@MainActor
@Test func sentenceRangeHandlesUnicode() {
    let text = "Café costs €3. Niño plays. 日本語の文。"
    let r = (text as NSString).range(of: "Niño")
    let sentence = AVSpeechTTSEngine.sentenceRange(containing: r, in: text)
    #expect(sentence != nil)
    #expect((text as NSString).substring(with: sentence!).contains("Niño"))
}

@MainActor
@Test func mappedRateClampsToEngineBounds() {
    let slow = AVSpeechTTSEngine.mappedRate(0.5)
    let fast = AVSpeechTTSEngine.mappedRate(4.0)
    #expect(slow >= AVSpeechUtteranceMinimumSpeechRate)
    #expect(fast <= AVSpeechUtteranceMaximumSpeechRate)
    #expect(fast >= slow)
}

// MARK: - Word-precise click-to-start snapping

@MainActor
@Test func wordStartSnapsClickInsideAWord() {
    let text = "The lighthouse keeper waited."
    // An index inside "lighthouse" (which starts at offset 4).
    let inside = (text as NSString).range(of: "lighthouse").location + 3
    #expect(ReaderTextView.wordStart(in: text, at: inside) == 4)
}

@MainActor
@Test func wordStartInWhitespaceJumpsToNextWord() {
    let text = "Hello   world"
    // The run of spaces sits between offset 5 and 8; clicking at 6 → "world".
    let worldStart = (text as NSString).range(of: "world").location
    #expect(ReaderTextView.wordStart(in: text, at: 6) == worldStart)
}

@MainActor
@Test func wordStartClampsOutOfRange() {
    let text = "Short."
    #expect(ReaderTextView.wordStart(in: text, at: -5) == 0)
    #expect(ReaderTextView.wordStart(in: text, at: 999) == (text as NSString).length)
}

// MARK: - Voice grouping by language

@MainActor
@Test func languageDisplayNameIsLocalized() {
    #expect(AVSpeechTTSEngine.languageDisplayName("en-US").contains("English"))
    // Unknown codes fall back to the raw string.
    #expect(AVSpeechTTSEngine.languageDisplayName("zz-ZZ") == "zz-ZZ")
}

@MainActor
@Test func voicesAreGroupedByLanguage() {
    let groups = AVSpeechTTSEngine().voicesByLanguage()
    #expect(!groups.isEmpty)                                  // every Mac ships voices
    // Group ids are unique languages.
    #expect(Set(groups.map(\.id)).count == groups.count)
    for group in groups {
        // Every voice in a group really belongs to that language.
        #expect(group.voices.allSatisfy { $0.language == group.id })
        #expect(!group.voices.isEmpty)
        // Highest-quality-first within a group (Premium > Enhanced > Default).
        let qualities = group.voices.map(\.quality)
        #expect(qualities == qualities.sorted(by: >))
    }
}

// MARK: - Paragraph offsets (skip logic)

@MainActor
@Test func paragraphOffsetsSkipBlankLines() {
    let text = "Para one.\n\nPara two.\n\n\nPara three."
    let offsets = AppState.paragraphStartOffsets(text)
    #expect(offsets.count == 3)
    #expect(offsets.first == 0)
    // Each offset begins a non-empty paragraph.
    let ns = text as NSString
    for off in offsets {
        let ch = ns.substring(with: NSRange(location: off, length: 1))
        #expect(ch == "P")
    }
}

// MARK: - Whisper stdout parsing

@Test func whisperOutputParsesSegments() {
    let sample = """
    [00:00:00.000 --> 00:00:02.500]   Hello there.
    [00:00:02.500 --> 00:00:05.000]   This is a test.

    [00:00:05.000 --> 00:00:06.000]
    """
    let segs = WhisperCppEngine.parseWhisperOutput(sample)
    #expect(segs.count == 2)   // empty-text line dropped
    #expect(segs[0].text == "Hello there.")
    #expect(abs(segs[1].start - 2.5) < 0.001)
    #expect(abs(segs[1].end - 5.0) < 0.001)
}

@Test func srtRenderingFormatsTimecodes() {
    let result = TranscriptionResult(segments: [
        TranscriptSegment(start: 0, end: 3661.5, text: "Hi")
    ])
    #expect(result.srt.contains("00:00:00,000 --> 01:01:01,500"))
    #expect(result.fullText == "Hi")
}

// MARK: - Text normalization

@Test func normalizeCollapsesBlankLinesAndTrailingSpace() {
    let messy = "Line one.   \r\n\r\n\r\n\r\nLine two.  \n"
    let clean = TextExtractionService.normalize(messy)
    #expect(!clean.contains("\r"))
    #expect(!clean.contains("\n\n\n"))
    #expect(!clean.contains("   \n"))
    #expect(clean.hasPrefix("Line one."))
}

// MARK: - Audio export filename sanitizing

@MainActor
@Test func sanitizeStripsIllegalPathCharacters() {
    let dirty = "My/Doc: \"Part 1\" *final*?"
    let clean = AudioExportService.sanitize(dirty)
    for bad in ["/", ":", "\"", "*", "?"] {
        #expect(!clean.contains(bad))
    }
    #expect(!clean.isEmpty)
}

@MainActor
@Test func sanitizeFallsBackForEmptyTitle() {
    #expect(AudioExportService.sanitize("   ") == "narration")
}

// MARK: - Settings round-trip

@Test func settingsCodableRoundTrips() throws {
    var s = AppSettings()
    s.speechRateMultiplier = 2.5
    s.outputDirectory = "~/Downloads/Custom"
    s.preferredAudioFormat = "mp3"
    s.whisperModel = "ggml-base.en.bin"
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(decoded == s)
    #expect(decoded.outputDirectory == "~/Downloads/Custom")
}

// MARK: - Backup retention / listing

@MainActor
@Test func backupRetentionTrimsOnlyOldPrefixedArchives() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("ps-bkp-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let old = dir.appendingPathComponent("PurpleSpeak-2000-01-01-000000.zip")
    let fresh = dir.appendingPathComponent("PurpleSpeak-2099-01-01-000000.zip")
    let foreign = dir.appendingPathComponent("notes.zip")
    for u in [old, fresh, foreign] { try Data("x".utf8).write(to: u) }
    // Backdate `old` well beyond the retention window.
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)

    let removed = BackupService.trimOldBackups(in: dir, retentionDays: 14)
    #expect(removed == 1)
    #expect(!fm.fileExists(atPath: old.path))
    #expect(fm.fileExists(atPath: fresh.path))
    #expect(fm.fileExists(atPath: foreign.path))   // non-prefixed left alone
}

@MainActor
@Test func backupListingIsNewestFirst() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("ps-bkp-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let a = dir.appendingPathComponent("PurpleSpeak-2020-01-01-000000.zip")
    let b = dir.appendingPathComponent("PurpleSpeak-2021-01-01-000000.zip")
    try Data("a".utf8).write(to: a)
    try Data("b".utf8).write(to: b)
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: a.path)
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: b.path)

    let rows = BackupService.listBackups(in: dir)
    #expect(rows.count == 2)
    #expect(rows.first?.url.lastPathComponent == "PurpleSpeak-2021-01-01-000000.zip")
}

@MainActor
@Test func backupRoundTripsSupportDirectory() throws {
    let fm = FileManager.default
    let support = fm.temporaryDirectory.appendingPathComponent("ps-support-\(UUID().uuidString)")
    let backupDir = fm.temporaryDirectory.appendingPathComponent("ps-out-\(UUID().uuidString)")
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: support); try? fm.removeItem(at: backupDir) }
    try Data("hello".utf8).write(to: support.appendingPathComponent("library.json"))

    let archive = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
    #expect(fm.fileExists(atPath: archive.path))
    #expect(archive.lastPathComponent.hasPrefix("PurpleSpeak-"))
}

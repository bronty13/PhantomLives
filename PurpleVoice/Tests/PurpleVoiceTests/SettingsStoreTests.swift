import Foundation
import Testing
@testable import PurpleVoice

@Suite("SettingsStore")
struct SettingsStoreTests {

    @Test("Default output directory lives under ~/Downloads/PurpleVoice")
    func defaultOutputDirectoryIsInsideDownloads() {
        let dir = SettingsStore.defaultOutputDirectory
        #expect(dir.path.contains("/Downloads/PurpleVoice"),
                "CLAUDE.md requires `~/Downloads/<project>/` default; got \(dir.path)")
    }

    @Test("resolveOutputURL applies _clean suffix and chosen extension")
    func resolveOutputURLAppliesCleanSuffixAndExtension() throws {
        let store = SettingsStore()
        store.outputFormat = .m4a

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PurpleVoiceTests-\(UUID().uuidString)",
                                    isDirectory: true)
        store.outputDirectory = tempDir

        let source = URL(fileURLWithPath: "/tmp/memo.m4a")
        let out = try store.resolveOutputURL(for: source)

        #expect(out.deletingLastPathComponent().path == tempDir.path)
        #expect(out.lastPathComponent == "memo_clean.m4a")
        #expect(FileManager.default.fileExists(atPath: tempDir.path),
                "resolveOutputURL must create the output directory")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("resolveOutputURL avoids collisions with existing files")
    func resolveOutputURLAvoidsCollisionsWithExistingFiles() throws {
        let store = SettingsStore()
        store.outputFormat = .wav

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PurpleVoiceTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                withIntermediateDirectories: true)
        store.outputDirectory = tempDir

        // Pre-create the natural target name; resolver should bump.
        let first = tempDir.appendingPathComponent("voicememo_clean.wav")
        FileManager.default.createFile(atPath: first.path, contents: nil)

        let source = URL(fileURLWithPath: "/tmp/voicememo.wav")
        let out = try store.resolveOutputURL(for: source)
        #expect(out.lastPathComponent == "voicememo_clean_2.wav")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("OutputFormat extension matches raw value")
    func outputFormatExtensionMatchesRawValue() {
        #expect(OutputFormat.m4a.fileExtension == "m4a")
        #expect(OutputFormat.mp3.fileExtension == "mp3")
        #expect(OutputFormat.wav.fileExtension == "wav")
    }
}

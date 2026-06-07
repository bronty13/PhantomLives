import Testing
import Foundation
@testable import PurpleSpeak

/// End-to-end exercise of AudioExportService: render TTS to audio and transcode.
/// Runs the real AVSpeechSynthesizer offline-render pipeline, so it also covers
/// the M4A path and the MP3/lame path (or its documented M4A fallback).
@MainActor
struct AudioExportTests {

    private static var lameAvailable: Bool {
        ["/opt/homebrew/bin/lame", "/usr/local/bin/lame"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func exportsM4A() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try await AudioExportService.export(
            text: "Hello there. This is a short export test.",
            title: "unit-m4a", voiceIdentifier: nil,
            rateMultiplier: 1.0, pitch: 1.0, format: "m4a", to: dir)
        #expect(result.url.pathExtension == "m4a")
        #expect(!result.fellBackToM4A)
        let size = (try? result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        #expect(size > 1_000)
        // M4A magic: "....ftyp" at byte 4.
        let head = try Data(contentsOf: result.url).prefix(12)
        #expect(head.count == 12)
        #expect(Array(head[4..<8]) == Array("ftyp".utf8))
    }

    @Test func exportsMP3WhenLameAvailableElseFallsBack() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try await AudioExportService.export(
            text: "Hello there. This is a short export test.",
            title: "unit-mp3", voiceIdentifier: nil,
            rateMultiplier: 1.0, pitch: 1.0, format: "mp3", to: dir)
        let size = (try? result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        #expect(size > 1_000)

        if Self.lameAvailable {
            #expect(result.url.pathExtension == "mp3")
            #expect(!result.fellBackToM4A)
            // MP3 magic: an ID3 tag ("ID3") or an MPEG frame sync (0xFF Ex).
            let head = try Data(contentsOf: result.url).prefix(3)
            let isID3 = Array(head) == Array("ID3".utf8)
            let isFrameSync = head.first == 0xFF && (head.count > 1 && (head[head.startIndex.advanced(by: 1)] & 0xE0) == 0xE0)
            #expect(isID3 || isFrameSync)
        } else {
            // Documented fallback: no lame → M4A, flagged so the UI can tell.
            #expect(result.url.pathExtension == "m4a")
            #expect(result.fellBackToM4A)
        }
    }

    @Test func sequentialExportsGetUniqueNames() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try await AudioExportService.export(
            text: "First.", title: "dupe", voiceIdentifier: nil,
            rateMultiplier: 1.0, pitch: 1.0, format: "m4a", to: dir)
        let b = try await AudioExportService.export(
            text: "Second.", title: "dupe", voiceIdentifier: nil,
            rateMultiplier: 1.0, pitch: 1.0, format: "m4a", to: dir)
        #expect(a.url != b.url)
        #expect(FileManager.default.fileExists(atPath: a.url.path))
        #expect(FileManager.default.fileExists(atPath: b.url.path))
    }
}

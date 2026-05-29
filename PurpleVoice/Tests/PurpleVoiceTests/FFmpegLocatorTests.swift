import Foundation
import Testing
@testable import PurpleVoice

@Suite("FFmpegLocator")
struct FFmpegLocatorTests {

    @Test("Override env var takes priority when executable")
    func overrideEnvVarTakesPriorityWhenExecutable() throws {
        let tempBin = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-ffmpeg-\(UUID().uuidString)")
        // A real, executable file — locator must reject non-executables.
        try "#!/bin/sh\necho fake\n".write(to: tempBin,
                                            atomically: true,
                                            encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: tempBin.path)
        defer { try? FileManager.default.removeItem(at: tempBin) }

        let found = FFmpegLocator.find(
            environment: ["PURPLE_VOICE_FFMPEG": tempBin.path]
        )
        #expect(found?.path == tempBin.path)
    }

    @Test("Override is ignored when path is not executable")
    func overrideIgnoredWhenNonExecutable() throws {
        let nonExec = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-runnable-\(UUID().uuidString).txt")
        try "noop".write(to: nonExec,
                          atomically: true,
                          encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: nonExec) }

        // With PATH cleared, this should not resolve via the
        // fallback either — proving the override fell through.
        let found = FFmpegLocator.find(
            environment: [
                "PURPLE_VOICE_FFMPEG": nonExec.path,
                "PATH": "/nonexistent"
            ]
        )
        // On a dev machine ffmpeg often lives at the well-known
        // Homebrew paths the locator probes; that's fine. The key is
        // that when found, it is NOT the bogus override.
        if let found {
            #expect(found.path != nonExec.path)
        }
    }

    @Test("Finds ffmpeg on a dev Mac where Homebrew is installed")
    func findsHomebrewFFmpegOnDevelopmentMachine() {
        // Smoke test against the verified location from CLAUDE.md.
        // Skips silently if the binary isn't where we expect so the
        // test passes on machines without Homebrew ffmpeg installed.
        let candidate = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath: candidate) else {
            return
        }
        #expect(FFmpegLocator.find() != nil)
    }
}

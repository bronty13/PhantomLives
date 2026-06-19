import Foundation
import Testing
import IRCKit
@testable import Ircle

/// CTCP SOUND: safe sound-file resolution (no path escape), the receive path
/// (text shown like an action), and the persisted toggle.
@MainActor
@Suite("CTCP sound")
struct SoundTests {

    private func tempSoundService() -> (SoundService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-sounds-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let svc = SoundService()
        svc.directory = dir
        return (svc, dir)
    }

    @Test func resolvesExistingClipOnly() {
        let (svc, dir) = tempSoundService()
        FileManager.default.createFile(atPath: dir.appendingPathComponent("beep.wav").path, contents: Data([0]))
        #expect(svc.soundURL(for: "beep.wav")?.lastPathComponent == "beep.wav")
        #expect(svc.soundURL(for: "missing.wav") == nil)
    }

    @Test func soundNameCannotEscapeFolder() {
        let (svc, dir) = tempSoundService()
        // A traversal name is sanitized; even if it resolved, it stays in `dir`.
        if let url = svc.soundURL(for: "../../etc/passwd") {
            #expect(url.deletingLastPathComponent().path == dir.path)
        }
        #expect(svc.soundURL(for: "../../etc/passwd") == nil)   // no such file in the folder
    }

    @Test func receivingSoundShowsTextLikeAnAction() {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        let s = IrcleSession(config: cfg, displayName: "Example")
        s.ingest(":bob!u@h PRIVMSG #x :\u{01}SOUND beep.wav hello there\u{01}")
        let line = s.buffers.first { $0.name == "#x" }?.lines.first { $0.kind == .action }
        #expect(line?.sender == "bob")
        #expect(line?.text.contains("hello there") == true)
    }

    @Test func eventSoundNameRespectsEnableAndMapping() {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        let s = IrcleSession(config: cfg, displayName: "Example")
        s.eventSounds = ["mention": "ding.wav"]
        s.eventSoundsEnabled = false
        #expect(s.eventSoundName(for: "mention") == nil)        // disabled → nil
        s.eventSoundsEnabled = true
        #expect(s.eventSoundName(for: "mention") == "ding.wav") // enabled + mapped
        #expect(s.eventSoundName(for: "join") == nil)           // unmapped → nil
    }

    @Test func eventSoundsDefaultOffAndRoundTrip() throws {
        var a = AppSettings()
        #expect(a.eventSoundsEnabled == false)
        #expect(a.eventSounds.isEmpty)
        a.eventSoundsEnabled = true
        a.eventSounds = ["mention": "x.wav", "join": "j.aiff"]
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back.eventSoundsEnabled)
        #expect(back.eventSounds == ["mention": "x.wav", "join": "j.aiff"])
    }

    @Test func ctcpSoundsEnabledDefaultsTrueAndRoundTrips() throws {
        #expect(AppSettings().ctcpSoundsEnabled)
        var s = AppSettings()
        s.ctcpSoundsEnabled = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).ctcpSoundsEnabled == false)
    }
}

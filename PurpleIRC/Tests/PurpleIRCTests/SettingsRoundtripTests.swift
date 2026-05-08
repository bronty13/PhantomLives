import Foundation
import Testing
@testable import PurpleIRC

/// Cover `AppSettings` Codable end-to-end. The clobber-on-launch data-loss
/// bug we hit in `d0cc021` lived along this path; a single field rename
/// or a missing `decodeIfPresent` fallback can silently zero out user
/// state. These tests are paranoid by design — every field that the
/// custom `init(from:)` reads gets a roundtrip check, plus a "this
/// minimal payload still decodes" test for forward compatibility.
@Suite("AppSettings Codable")
struct SettingsRoundtripTests {

    private func roundtrip(_ s: AppSettings) -> AppSettings? {
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    // MARK: - Defaults preserved

    @Test func defaultSettingsRoundtripPreservesEverything() {
        let original = AppSettings()
        let roundtripped = roundtrip(original)
        #expect(roundtripped != nil)
        // Spot-check: every field that has a non-empty default.
        #expect(roundtripped?.servers.isEmpty == false)            // bundled defaults
        #expect(roundtripped?.playSoundOnWatchHit == true)
        #expect(roundtripped?.bounceDockOnWatchHit == true)
        #expect(roundtripped?.systemNotificationsOnWatchHit == true)
        #expect(roundtripped?.highlightOnOwnNick == true)
        #expect(roundtripped?.ctcpRepliesEnabled == true)
        #expect(roundtripped?.autoReplyWhenAway == true)
        #expect(roundtripped?.themeID == "classic")
        #expect(roundtripped?.timestampFormat == "HH:mm:ss")
        #expect(roundtripped?.collapseJoinPart == true)
        #expect(roundtripped?.restoreOpenBuffersOnLaunch == true)
    }

    // MARK: - Forward compatibility — minimal payload still decodes

    @Test func decodesEmptyJSONObject() throws {
        // A `{}` settings file (think: brand new install where nothing has
        // been written yet) must decode into something usable. Every field
        // should fall through to its `decodeIfPresent ?? default` path.
        let data = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.collapseJoinPart == true)
        #expect(settings.restoreOpenBuffersOnLaunch == true)
        #expect(settings.lastSession.isEmpty)
        #expect(settings.timestampFormat == "HH:mm:ss")
        #expect(settings.themeID == "classic")
        #expect(!settings.servers.isEmpty)            // bundled defaults
    }

    @Test func decodesPayloadMissingFutureFields() throws {
        // Construct a payload that has a few fields and not others — the
        // shape that *previous* versions of the app would have written.
        // Every missing field must fall through to its default.
        let json = """
        {
          "servers": [],
          "themeID": "midnight",
          "timestampFormat": "h:mm a"
        }
        """
        let data = json.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(s.themeID == "midnight")
        #expect(s.timestampFormat == "h:mm a")
        #expect(s.collapseJoinPart == true)               // default
        #expect(s.restoreOpenBuffersOnLaunch == true)     // default
    }

    // MARK: - Mutated fields survive

    @Test func mutatedSimpleScalarsSurviveRoundtrip() {
        var s = AppSettings()
        s.themeID = "candy"
        s.timestampFormat = "yyyy-MM-dd HH:mm"
        s.collapseJoinPart = false
        s.restoreOpenBuffersOnLaunch = false
        s.highlightOnOwnNick = false
        s.enablePersistentLogs = true
        s.purgeLogsAfterDays = 30
        let r = roundtrip(s)
        #expect(r?.themeID == "candy")
        #expect(r?.timestampFormat == "yyyy-MM-dd HH:mm")
        #expect(r?.collapseJoinPart == false)
        #expect(r?.restoreOpenBuffersOnLaunch == false)
        #expect(r?.highlightOnOwnNick == false)
        #expect(r?.enablePersistentLogs == true)
        #expect(r?.purgeLogsAfterDays == 30)
    }

    @Test func ignoreListSurvivesRoundtrip() {
        var s = AppSettings()
        s.ignoreList = [
            IgnoreEntry(mask: "*!*@spammer.example",
                        ignoreCTCP: true, ignoreNotices: false),
            IgnoreEntry(mask: "alice!*@*",
                        ignoreCTCP: false, ignoreNotices: true)
        ]
        let r = roundtrip(s)
        #expect(r?.ignoreList.count == 2)
        #expect(r?.ignoreList[0].mask == "*!*@spammer.example")
        #expect(r?.ignoreList[0].ignoreCTCP == true)
        #expect(r?.ignoreList[1].ignoreNotices == true)
    }

    @Test func addressBookSurvivesRoundtrip() {
        var s = AppSettings()
        var entry = AddressEntry()
        entry.nick = "alice"
        entry.watch = true
        entry.note = "good friend"
        entry.richNotes = "Met at WWDC 2025."
        s.addressBook = [entry]
        let r = roundtrip(s)
        #expect(r?.addressBook.count == 1)
        #expect(r?.addressBook.first?.nick == "alice")
        #expect(r?.addressBook.first?.watch == true)
        #expect(r?.addressBook.first?.richNotes == "Met at WWDC 2025.")
    }

    @Test func savedChannelsSurviveRoundtrip() {
        var s = AppSettings()
        let pid = UUID()
        s.savedChannels = [
            SavedChannel(name: "#swift", note: "weekly meetup", serverID: pid),
            SavedChannel(name: "#offtopic", note: "", serverID: nil)
        ]
        let r = roundtrip(s)
        #expect(r?.savedChannels.count == 2)
        #expect(r?.savedChannels[0].name == "#swift")
        #expect(r?.savedChannels[0].serverID == pid)
        #expect(r?.savedChannels[1].serverID == nil)
    }

    @Test func highlightRulesSurviveRoundtrip() {
        var s = AppSettings()
        s.highlightRules = [
            HighlightRule(name: "deploys", pattern: "deploy",
                          isRegex: false, caseSensitive: false,
                          colorHex: "#FF8800",
                          playSound: true, bounceDock: true,
                          systemNotify: true, networks: [], enabled: true)
        ]
        let r = roundtrip(s)
        #expect(r?.highlightRules.count == 1)
        #expect(r?.highlightRules.first?.pattern == "deploy")
        #expect(r?.highlightRules.first?.colorHex == "#FF8800")
        #expect(r?.highlightRules.first?.enabled == true)
    }

    @Test func eventSoundsSurviveRoundtrip() {
        var s = AppSettings()
        s.eventSounds["mention"] = "Hero"
        s.eventSounds["highlight"] = "Funk"
        let r = roundtrip(s)
        #expect(r?.eventSounds["mention"] == "Hero")
        #expect(r?.eventSounds["highlight"] == "Funk")
    }

    // MARK: - lastSession

    @Test func lastSessionRoundtripsForBufferRestore() {
        var s = AppSettings()
        let pid = UUID().uuidString
        s.lastSession[pid] = SessionSnapshot(
            channels: ["#swift", "#offtopic"],
            queries: ["alice", "bob"],
            selected: "#swift")
        let r = roundtrip(s)
        let snap = r?.lastSession[pid]
        #expect(snap?.channels == ["#swift", "#offtopic"])
        #expect(snap?.queries == ["alice", "bob"])
        #expect(snap?.selected == "#swift")
    }

    @Test func lastSessionMultipleNetworks() {
        var s = AppSettings()
        let p1 = UUID().uuidString
        let p2 = UUID().uuidString
        s.lastSession[p1] = SessionSnapshot(channels: ["#a"], queries: [], selected: nil)
        s.lastSession[p2] = SessionSnapshot(channels: ["#b"], queries: ["carol"], selected: "carol")
        let r = roundtrip(s)
        #expect(r?.lastSession.count == 2)
        #expect(r?.lastSession[p1]?.channels == ["#a"])
        #expect(r?.lastSession[p2]?.queries == ["carol"])
        #expect(r?.lastSession[p2]?.selected == "carol")
    }

    @Test func lastSessionDecodeMissingFieldFallback() throws {
        // Old payloads without lastSession should still decode cleanly.
        let json = """
        {"servers":[],"themeID":"classic"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        #expect(s.lastSession.isEmpty)
    }
}

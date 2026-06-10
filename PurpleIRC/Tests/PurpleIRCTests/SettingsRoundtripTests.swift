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

    // MARK: - Regression: fields the decoder used to drop (2026-06-09)

    /// Eight persisted fields were written by the synthesized encoder but
    /// never read back in `init(from:)` — every relaunch silently reset
    /// user aliases, custom themes, chat density, zoom, and all four
    /// per-element font overrides to factory defaults. This pins the fix:
    /// a customized value of each must survive a roundtrip.
    @Test func decoderCoversEveryPersistedField() throws {
        var original = AppSettings()
        original.userAliases = ["greet": "/msg $1 hello"]
        original.chatDensity = .compact
        original.viewZoom = 1.4
        original.userThemes = [UserTheme.duplicate(of: Theme.all[0], name: "Test Theme")]
        original.chatBodyFont = FontStyle(family: "Menlo", size: 15)
        original.nickFont = FontStyle(family: "Avenir", size: 12)
        original.timestampFont = FontStyle(family: "Monaco", size: 10)
        original.systemLineFont = FontStyle(family: "Helvetica", size: 11)

        let r = try #require(roundtrip(original))
        #expect(r.userAliases == ["greet": "/msg $1 hello"])
        #expect(r.chatDensity == .compact)
        #expect(r.viewZoom == 1.4)
        #expect(r.userThemes.count == 1)
        #expect(r.userThemes.first?.name == "Test Theme")
        #expect(r.chatBodyFont.family == "Menlo")
        #expect(r.nickFont.family == "Avenir")
        #expect(r.timestampFont.family == "Monaco")
        #expect(r.systemLineFont.family == "Helvetica")
    }

    @Test func quietWhenBufferVisibleDefaultsOnAndRoundtrips() throws {
        // Default ON for both fresh installs and pre-existing settings
        // files that don't carry the key.
        let fromEmpty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(fromEmpty.quietWhenBufferVisible == true)

        var s = AppSettings()
        s.quietWhenBufferVisible = false
        #expect(roundtrip(s)?.quietWhenBufferVisible == false)
    }

    @Test func viewZoomIsClampedOnDecode() throws {
        let data = Data(#"{"viewZoom": 99.0}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(s.viewZoom == 2.0)   // /zoom's documented 0.5–2.0 range
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
        // The decoder fallback must match the struct default exactly — it
        // used to omit "highlight" (and "privateMessage"), so a settings
        // file without the key decoded to a different sound map than a
        // fresh install.
        #expect(settings.eventSounds == AppSettings.defaultEventSounds)
        #expect(settings.eventSounds["highlight"] == "Funk")
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

    // MARK: - Person model (1.0.242)
    //
    // The Person-model refactor added LinkedNick + ContactAlertOverride
    // to AddressEntry. These tests pin the on-disk wire format so:
    //  • old PurpleIRC builds keep reading new settings.json files,
    //  • the auto-backup-on-launch zip round-trips unchanged for any
    //    user who hasn't touched the new feature,
    //  • the migration "every old entry's nick becomes one LinkedNick"
    //    runs idempotently inside the AppSettings decoder.

    @Test func linkedNicksSurviveRoundtrip() throws {
        var s = AppSettings()
        var entry = AddressEntry(nick: "alice", watch: true)
        entry.linkedNicks = [
            LinkedNick(networkSlug: "libera",   nick: "alice",  source: .manual),
            LinkedNick(networkSlug: "oftc",     nick: "alice_", source: .hostmask),
            LinkedNick(networkSlug: "undernet", nick: "ali",    source: .accountTag),
        ]
        s.addressBook = [entry]
        let r = roundtrip(s)
        #expect(r?.addressBook.count == 1)
        #expect(r?.addressBook.first?.linkedNicks.count == 3)
        #expect(r?.addressBook.first?.linkedNicks[0].nick == "alice")
        #expect(r?.addressBook.first?.linkedNicks[1].networkSlug == "oftc")
        #expect(r?.addressBook.first?.linkedNicks[2].source == .accountTag)
    }

    @Test func legacyEntryMigratesToOneLinkedNick() throws {
        // Pre-1.0.242 JSON: AddressEntry with no linkedNicks key.
        let id = UUID().uuidString
        let json = """
        {"servers":[],"addressBook":[
            {"id":"\(id)","nick":"alice","note":"","watch":true,
             "richNotes":"","attachments":[],"tagIDs":[]}
        ]}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        #expect(s.addressBook.count == 1)
        let entry = s.addressBook[0]
        #expect(entry.linkedNicks.count == 1)
        #expect(entry.linkedNicks[0].networkSlug == "")  // any-network sentinel
        #expect(entry.linkedNicks[0].nick == "alice")
        #expect(entry.linkedNicks[0].source == .migrated)
    }

    @Test func migrationIsIdempotentAcrossDecodes() throws {
        // After one decode, linkedNicks is populated. Encoding then
        // re-decoding must NOT add a second migrated entry.
        let id = UUID().uuidString
        let originalJSON = """
        {"servers":[],"addressBook":[
            {"id":"\(id)","nick":"bob","note":"","watch":true,
             "richNotes":"","attachments":[],"tagIDs":[]}
        ]}
        """
        let first = try JSONDecoder().decode(AppSettings.self,
                                              from: originalJSON.data(using: .utf8)!)
        let reencoded = try JSONEncoder().encode(first)
        let second = try JSONDecoder().decode(AppSettings.self, from: reencoded)
        #expect(second.addressBook[0].linkedNicks.count == 1)
        #expect(second.addressBook[0].linkedNicks[0].source == .migrated)
    }

    @Test func unlinkedEntryEncodesWithoutLinkedNicksKey() throws {
        // Wire-format invariant: a default AddressEntry (no manual
        // linked-nick edits) MUST encode without a "linkedNicks" key
        // so settings.json round-tripped by the new build stays
        // compatible with pre-1.0.242 PurpleIRC reading the same file.
        let entry = AddressEntry(nick: "default", watch: true)
        let data = try JSONEncoder().encode(entry)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object != nil)
        #expect(object?["linkedNicks"] == nil,
                "Default AddressEntry must NOT serialize linkedNicks key")
        #expect(object?["alertOverride"] == nil,
                "Default AddressEntry must NOT serialize alertOverride key")
    }

    @Test func entryWithLinksDoesSerializeKey() throws {
        // The inverse pin — once the user adds a link, the key emits.
        var entry = AddressEntry(nick: "linked", watch: true)
        entry.linkedNicks = [LinkedNick(networkSlug: "libera", nick: "linked")]
        let data = try JSONEncoder().encode(entry)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["linkedNicks"] != nil)
    }

    @Test func alertOverrideDefaultsDoNotSerialize() throws {
        let entry = AddressEntry(nick: "x", watch: false)
        let data = try JSONEncoder().encode(entry)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["alertOverride"] == nil)
    }

    @Test func customAlertOverrideDoesSerialize() throws {
        var entry = AddressEntry(nick: "y", watch: true)
        entry.alertOverride = ContactAlertOverride(playSound: false)
        let data = try JSONEncoder().encode(entry)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["alertOverride"] != nil)
    }
}

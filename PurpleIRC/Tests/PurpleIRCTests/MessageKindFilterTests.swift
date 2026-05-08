import Foundation
import Testing
@testable import PurpleIRC

/// Behavior of `MessageKindFilter` and the per-buffer override path on
/// `SettingsStore`. The filter feeds `BufferView.renderedRows`; if a kind
/// toggle gets the wrong default or fails to round-trip, the user
/// silently loses messages — same data-loss class as the d0cc021 bug,
/// just on the rendering side.
@Suite("Message-kind filter")
struct MessageKindFilterTests {

    // MARK: - includes(_:)

    @Test func includesPrivmsgAlwaysReturnsTrue() {
        // PRIVMSG is the user's actual chat. If a filter could hide it
        // we'd be violating the "this is a footgun" promise printed in
        // the popover.
        var f = MessageKindFilter()
        f.info = false
        f.error = false
        f.notice = false
        #expect(f.includes(.privmsg(nick: "alice", isSelf: false)) == true)
        #expect(f.includes(.action(nick: "alice")) == true)
        #expect(f.includes(.raw) == true)
    }

    @Test func togglesGateTheirKind() {
        var f = MessageKindFilter()
        f.join = false
        #expect(f.includes(.join(nick: "alice")) == false)
        #expect(f.includes(.part(nick: "alice", reason: nil)) == true)
    }

    @Test func defaultFilterShowsEverything() {
        let f = MessageKindFilter()
        #expect(f.includes(.info))
        #expect(f.includes(.error))
        #expect(f.includes(.motd))
        #expect(f.includes(.notice(from: "ChanServ")))
        #expect(f.includes(.join(nick: "alice")))
        #expect(f.includes(.part(nick: "alice", reason: nil)))
        #expect(f.includes(.quit(nick: "alice", reason: nil)))
        #expect(f.includes(.nick(old: "alice", new: "alice2")))
        #expect(f.includes(.topic(setter: "alice")))
    }

    // MARK: - Codable forward-compat

    @Test func decodesEmptyJSONObject() throws {
        // An old payload missing every field decodes as "show everything"
        // — the same shape AppSettings's `decodeIfPresent` paths use.
        let data = "{}".data(using: .utf8)!
        let f = try JSONDecoder().decode(MessageKindFilter.self, from: data)
        #expect(f == MessageKindFilter())
    }

    @Test func roundtripsPreservesEveryField() throws {
        let original = MessageKindFilter(
            info: false, error: true, motd: false, notice: true,
            join: false, part: false, quit: false,
            nickChange: false, topic: false)
        let data = try JSONEncoder().encode(original)
        let r = try JSONDecoder().decode(MessageKindFilter.self, from: data)
        #expect(r == original)
    }

    // MARK: - Per-buffer key

    @Test func keyIsCaseInsensitiveOnBufferName() {
        let a = MessageKindFilter.key(networkSlug: "libera", bufferName: "#Swift")
        let b = MessageKindFilter.key(networkSlug: "libera", bufferName: "#swift")
        #expect(a == b)
    }

    @Test func keySeparatesNetworks() {
        let a = MessageKindFilter.key(networkSlug: "libera",   bufferName: "#swift")
        let b = MessageKindFilter.key(networkSlug: "undernet", bufferName: "#swift")
        #expect(a != b)
    }

    // MARK: - SettingsStore CRUD

    @MainActor
    private func makeStore() -> SettingsStore {
        let store = SettingsStore()
        store.settings = AppSettings()
        return store
    }

    @MainActor
    @Test func filterFallsBackToDefaultsWhenNoOverride() {
        let store = makeStore()
        var defaults = MessageKindFilter()
        defaults.join = false
        store.settings.messageFilterDefaults = defaults
        let f = store.messageFilter(networkSlug: "libera", bufferName: "#swift")
        #expect(f.join == false)
    }

    @MainActor
    @Test func setOverrideShadowsDefaults() {
        let store = makeStore()
        // Defaults: show joins. Override #swift to hide them.
        var override = MessageKindFilter()
        override.join = false
        store.setMessageFilter(override, networkSlug: "libera", bufferName: "#swift")
        let f = store.messageFilter(networkSlug: "libera", bufferName: "#swift")
        #expect(f.join == false)
        // A different buffer still falls back to defaults.
        let other = store.messageFilter(networkSlug: "libera", bufferName: "#other")
        #expect(other.join == true)
    }

    @MainActor
    @Test func clearOverrideRevertsToDefaults() {
        let store = makeStore()
        var override = MessageKindFilter()
        override.join = false
        store.setMessageFilter(override, networkSlug: "libera", bufferName: "#swift")
        #expect(store.hasMessageFilterOverride(networkSlug: "libera", bufferName: "#swift"))
        store.clearMessageFilter(networkSlug: "libera", bufferName: "#swift")
        #expect(!store.hasMessageFilterOverride(networkSlug: "libera", bufferName: "#swift"))
        // Now resolves to defaults again.
        let f = store.messageFilter(networkSlug: "libera", bufferName: "#swift")
        #expect(f.join == true)
    }

    @MainActor
    @Test func overrideKeyIsCaseInsensitive() {
        let store = makeStore()
        var override = MessageKindFilter()
        override.notice = false
        store.setMessageFilter(override, networkSlug: "libera", bufferName: "#Swift")
        // Read back with a different case — should still hit the override.
        let f = store.messageFilter(networkSlug: "libera", bufferName: "#swift")
        #expect(f.notice == false)
    }

    // MARK: - AppSettings roundtrip

    @MainActor
    @Test func appSettingsRoundtripsFilterDefaultsAndOverrides() throws {
        var s = AppSettings()
        s.messageFilterDefaults.join = false
        s.messageFilterDefaults.part = false
        s.messageFiltersByBuffer["libera/#swift"] = MessageKindFilter(
            info: false, error: true, motd: true, notice: false,
            join: true, part: true, quit: true, nickChange: true, topic: true)
        let data = try JSONEncoder().encode(s)
        let r = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(r.messageFilterDefaults.join == false)
        #expect(r.messageFilterDefaults.part == false)
        #expect(r.messageFilterDefaults.notice == true)
        #expect(r.messageFiltersByBuffer["libera/#swift"]?.notice == false)
    }

    @MainActor
    @Test func appSettingsMissingFiltersFallsBackToDefaultEverythingShown() throws {
        // Old payload predates the field — decode must yield the
        // permissive baseline so existing users don't lose lines.
        let json = """
        {"servers":[],"themeID":"classic"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        #expect(s.messageFilterDefaults == MessageKindFilter())
        #expect(s.messageFiltersByBuffer.isEmpty)
    }

    // MARK: - Toggle metadata

    @Test func togglesCoverEveryFilterField() {
        // If we add a new field to MessageKindFilter without adding a
        // matching MessageKindToggle case, the buffer popover and Setup
        // section silently lose access to it. Counting the toggles
        // catches the regression.
        #expect(MessageKindToggle.allCases.count == 9)
    }

    @Test func toggleGetSetRoundtrips() {
        var f = MessageKindFilter()
        for toggle in MessageKindToggle.allCases {
            // Flip every toggle off, then on, asserting both directions
            // bind to the right field.
            toggle.set(false, on: &f)
            #expect(toggle.get(from: f) == false)
            toggle.set(true, on: &f)
            #expect(toggle.get(from: f) == true)
        }
    }
}

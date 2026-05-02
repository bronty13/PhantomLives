import Foundation
import SwiftUI
import Testing
@testable import PurpleIRC

/// Cover the address-book / contact-tag helpers added in 1.0.108–1.0.110:
/// the ContactTag model itself, the auto-naming + auto-color helpers, the
/// duplicate-detection helpers, the SettingsStore CRUD that cascades tag
/// deletion across address-book entries, and the Codable forward-compat
/// path. These are paranoid by design — the manager UI relies on every
/// one of these being honest, and a regression here would either crash
/// (captured-index class) or silently allow duplicates / orphan tagIDs.
@Suite("Contact tags + address book helpers")
struct ContactTagTests {

    // MARK: - Codable

    @Test func contactTagRoundtrips() throws {
        let tag = ContactTag(name: "Friend", detail: "good people", colorHex: "#42A5F5")
        let data = try JSONEncoder().encode(tag)
        let decoded = try JSONDecoder().decode(ContactTag.self, from: data)
        #expect(decoded.name == "Friend")
        #expect(decoded.detail == "good people")
        #expect(decoded.colorHex == "#42A5F5")
        #expect(decoded.id == tag.id)
    }

    @Test func contactTagDecodesEmptyJSON() throws {
        // Forward-compat: a tag persisted by some hypothetical future
        // version that drops every field must still parse — every key
        // is decodeIfPresent. Specifically: a {} payload yields a tag
        // with a fresh UUID and empty strings.
        let data = "{}".data(using: .utf8)!
        let tag = try JSONDecoder().decode(ContactTag.self, from: data)
        #expect(tag.name.isEmpty)
        #expect(tag.detail.isEmpty)
        #expect(tag.colorHex == nil)
    }

    @Test func contactTagDecodesPayloadMissingColorHex() throws {
        // A tag persisted by 1.0.108 (no colorHex field yet). Must
        // decode with colorHex == nil so it falls back to the default
        // purple chip everywhere.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Coworker","detail":""}
        """
        let data = json.data(using: .utf8)!
        let tag = try JSONDecoder().decode(ContactTag.self, from: data)
        #expect(tag.name == "Coworker")
        #expect(tag.colorHex == nil)
    }

    @Test func appSettingsContactTagsRoundtrip() throws {
        var s = AppSettings()
        s.contactTags = [
            ContactTag(name: "Friend", colorHex: "#7E57C2"),
            ContactTag(name: "Work", detail: "$dayjob", colorHex: "#42A5F5"),
            ContactTag(name: "Channel-op")
        ]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.contactTags.count == 3)
        #expect(decoded.contactTags[0].name == "Friend")
        #expect(decoded.contactTags[1].colorHex == "#42A5F5")
        #expect(decoded.contactTags[2].colorHex == nil)
    }

    @Test func addressEntryTagIDsRoundtrip() throws {
        let tagA = UUID()
        let tagB = UUID()
        var entry = AddressEntry(nick: "alice")
        entry.tagIDs = [tagA, tagB]
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AddressEntry.self, from: data)
        #expect(decoded.tagIDs == [tagA, tagB])
    }

    @Test func addressEntryDecodesPre108JSON() throws {
        // An entry persisted by a version before tagIDs existed must
        // still decode with an empty tagIDs array.
        let json = """
        {"id":"\(UUID().uuidString)","nick":"alice","note":"","watch":true}
        """
        let entry = try JSONDecoder().decode(AddressEntry.self, from: json.data(using: .utf8)!)
        #expect(entry.nick == "alice")
        #expect(entry.tagIDs.isEmpty)
    }

    // MARK: - Auto-naming

    @Test func nextDefaultTagNameStartsAtOneOnEmpty() {
        #expect(ContactTag.nextDefaultName(existing: []) == "New Tag 1")
    }

    @Test func nextDefaultTagNameSkipsTakenSlots() {
        let existing = [
            ContactTag(name: "New Tag 1"),
            ContactTag(name: "New Tag 2")
        ]
        #expect(ContactTag.nextDefaultName(existing: existing) == "New Tag 3")
    }

    @Test func nextDefaultTagNameFillsGaps() {
        // After the user renames the middle slot, the next + click
        // should reuse the freed number rather than blindly counting
        // up — that's what "stops at the first gap" means.
        let existing = [
            ContactTag(name: "New Tag 1"),
            ContactTag(name: "Friend"),     // was "New Tag 2", renamed
            ContactTag(name: "New Tag 3")
        ]
        #expect(ContactTag.nextDefaultName(existing: existing) == "New Tag 2")
    }

    @Test func nextDefaultTagNameIsCaseInsensitive() {
        // Existing "new tag 1" (lowercased) must still count as taken.
        let existing = [ContactTag(name: "new tag 1")]
        #expect(ContactTag.nextDefaultName(existing: existing) == "New Tag 2")
    }

    @Test func nextDefaultNickStartsAtOneOnEmpty() {
        #expect(AddressEntry.nextDefaultNick(existing: []) == "New Contact 1")
    }

    @Test func nextDefaultNickSkipsTakenSlots() {
        let existing = [
            AddressEntry(nick: "New Contact 1"),
            AddressEntry(nick: "alice"),
            AddressEntry(nick: "New Contact 3")
        ]
        // First gap is 2.
        #expect(AddressEntry.nextDefaultNick(existing: existing) == "New Contact 2")
    }

    // MARK: - Duplicate detection

    @Test func tagNameClashesIsCaseInsensitive() {
        let other = UUID()
        let existing = [
            ContactTag(id: UUID(), name: "Friend"),
            ContactTag(id: other, name: "Coworker")
        ]
        // Case-insensitive match against another tag's name → clash.
        #expect(ContactTag.nameClashes("FRIEND", in: existing, excluding: UUID()))
        #expect(ContactTag.nameClashes("friend", in: existing, excluding: UUID()))
        // Excluding the matching tag's own id → no clash (renaming
        // yourself to your current name shouldn't warn).
        #expect(!ContactTag.nameClashes("coworker", in: existing, excluding: other))
        // Whitespace is trimmed.
        #expect(ContactTag.nameClashes("  Friend  ", in: existing, excluding: UUID()))
    }

    @Test func tagNameClashesHandlesEmpty() {
        let existing = [ContactTag(name: "Friend")]
        // Empty name never clashes — caller would otherwise get a
        // bogus warning the moment they cleared the field.
        #expect(!ContactTag.nameClashes("", in: existing, excluding: UUID()))
        #expect(!ContactTag.nameClashes("   ", in: existing, excluding: UUID()))
    }

    @Test func nickClashesIsCaseInsensitive() {
        let other = UUID()
        let existing = [
            AddressEntry(id: UUID(), nick: "alice"),
            AddressEntry(id: other, nick: "BOB")
        ]
        #expect(AddressEntry.nickClashes("ALICE", in: existing, excluding: UUID()))
        #expect(AddressEntry.nickClashes("bob",   in: existing, excluding: UUID()))
        #expect(!AddressEntry.nickClashes("bob",  in: existing, excluding: other))
        #expect(!AddressEntry.nickClashes("",     in: existing, excluding: UUID()))
    }

    // MARK: - Auto-color

    @Test func nextDefaultColorIsFirstWhenEmpty() {
        // No tags yet → first slot in the palette (purple).
        let hex = ContactTag.nextDefaultColorHex(existing: [])
        #expect(hex == ContactTag.defaultPalette[0])
    }

    @Test func nextDefaultColorRotatesThroughPalette() {
        // Adding tags one at a time should cycle through the palette
        // until every slot has been used once before any repeats start.
        var existing: [ContactTag] = []
        var used: [String] = []
        for _ in 0..<ContactTag.defaultPalette.count {
            let next = ContactTag.nextDefaultColorHex(existing: existing)
            used.append(next)
            existing.append(ContactTag(name: "_", colorHex: next))
        }
        #expect(Set(used) == Set(ContactTag.defaultPalette))
    }

    @Test func nextDefaultColorPicksLeastUsedAfterFullCycle() {
        // Once the palette has been exhausted, the next pick should
        // fall on the entry that's been used the fewest times. With
        // every entry used exactly once, palette order tie-breaks →
        // the first entry wins.
        let existing = ContactTag.defaultPalette.map {
            ContactTag(name: "_", colorHex: $0)
        }
        let next = ContactTag.nextDefaultColorHex(existing: existing)
        #expect(next == ContactTag.defaultPalette[0])
    }

    @Test func nextDefaultColorIgnoresTagsWithoutColor() {
        // Tags with colorHex == nil don't count as using any palette
        // entry — they're on the "default purple" fallback.
        let existing = [
            ContactTag(name: "_", colorHex: nil),
            ContactTag(name: "_", colorHex: nil)
        ]
        let next = ContactTag.nextDefaultColorHex(existing: existing)
        #expect(next == ContactTag.defaultPalette[0])
    }

    @Test func defaultPaletteHasExpectedShape() {
        // 12 distinct hex strings, every entry in the #RRGGBB shape.
        // Specifically guards against a careless edit dropping below
        // the count or leaving a duplicate (which would defeat the
        // "least-used" tie-breaker in nextDefaultColorHex).
        #expect(ContactTag.defaultPalette.count == 12)
        #expect(Set(ContactTag.defaultPalette).count == 12)
        for hex in ContactTag.defaultPalette {
            #expect(hex.count == 7)
            #expect(hex.first == "#")
            #expect(Color(hex: hex) != nil)
        }
    }

    // MARK: - SettingsStore tag CRUD + cascade

    /// Build a fresh in-memory SettingsStore. Sidesteps the on-disk
    /// reload path so the tests don't depend on Application Support
    /// state. SettingsStore.init populates settings from disk if the
    /// file exists; on a clean machine this is a no-op and we get the
    /// AppSettings defaults.
    @MainActor
    private func makeStore() -> SettingsStore {
        let store = SettingsStore()
        // Drop anything that came in off disk so the tests run on a
        // known shape regardless of the developer's local state.
        store.settings = AppSettings()
        return store
    }

    @MainActor
    @Test func upsertAddsThenUpdatesSameId() {
        let store = makeStore()
        let id = UUID()
        store.upsertTag(ContactTag(id: id, name: "Friend"))
        #expect(store.settings.contactTags.count == 1)
        store.upsertTag(ContactTag(id: id, name: "Friends", detail: "renamed"))
        #expect(store.settings.contactTags.count == 1)
        #expect(store.settings.contactTags.first?.name == "Friends")
        #expect(store.settings.contactTags.first?.detail == "renamed")
    }

    @MainActor
    @Test func deleteTagCascadesAcrossEveryContact() {
        // The whole point of the cascading delete: deleting a tag must
        // strip its id from every entry's tagIDs so we never end up
        // with dangling references in settings.json.
        let store = makeStore()
        let tagFriend = UUID()
        let tagWork = UUID()
        store.settings.contactTags = [
            ContactTag(id: tagFriend, name: "Friend"),
            ContactTag(id: tagWork,   name: "Work")
        ]
        store.settings.addressBook = [
            AddressEntry(id: UUID(), nick: "alice", tagIDs: [tagFriend, tagWork]),
            AddressEntry(id: UUID(), nick: "bob",   tagIDs: [tagFriend]),
            AddressEntry(id: UUID(), nick: "carol", tagIDs: []),
            AddressEntry(id: UUID(), nick: "dave",  tagIDs: [tagWork])
        ]
        store.deleteTag(id: tagFriend)
        // Tag definition gone.
        #expect(store.settings.contactTags.count == 1)
        #expect(store.settings.contactTags.first?.id == tagWork)
        // Tag id stripped from every contact that had it.
        #expect(store.settings.addressBook[0].tagIDs == [tagWork])
        #expect(store.settings.addressBook[1].tagIDs == [])
        #expect(store.settings.addressBook[2].tagIDs == [])
        #expect(store.settings.addressBook[3].tagIDs == [tagWork])
    }

    @MainActor
    @Test func deleteUnknownTagIsHarmlessNoOp() {
        // Defensive: deleting a tag that's already gone shouldn't
        // throw or wipe other state. Same shape as the no-op write
        // path in the id-based binding helpers — we want delete to be
        // idempotent so a stale-ID double-fire can't corrupt anything.
        let store = makeStore()
        let tagA = UUID()
        store.settings.contactTags = [ContactTag(id: tagA, name: "Friend")]
        store.deleteTag(id: UUID())
        #expect(store.settings.contactTags.count == 1)
        #expect(store.settings.contactTags.first?.id == tagA)
    }
}

import Foundation
import Testing
@testable import PurpleIRC

/// Tests for the Person-model layer (1.0.242):
/// • `AddressEntry.matches(networkSlug:nick:)` semantics
/// • `AddressEntry.matchesAnyNetwork(nick:)` semantics
/// • `SettingsStore.watchedFromAddressBook` flattening across linkedNicks
/// • `SettingsStore.linkNick` / `unlinkNick` idempotency + invariants
/// • The "every saved entry has ≥1 linked nick" invariant
@Suite("Person model — linked nicks")
struct ContactLinkedNickTests {

    // MARK: - matches(...)

    @Test func matchesIsCaseInsensitive() {
        var e = AddressEntry(nick: "Alice")
        e.linkedNicks = [LinkedNick(networkSlug: "libera", nick: "Alice")]
        #expect(e.matches(networkSlug: "libera", nick: "alice"))
        #expect(e.matches(networkSlug: "libera", nick: "ALICE"))
        #expect(!e.matches(networkSlug: "libera", nick: "bob"))
    }

    @Test func matchesHonoursNetworkScoping() {
        // A specific-slug binding does NOT match the same nick on a
        // different network — that's the whole point of the Person
        // model (one contact, distinct bindings).
        var e = AddressEntry(nick: "alice")
        e.linkedNicks = [LinkedNick(networkSlug: "libera", nick: "alice")]
        #expect(e.matches(networkSlug: "libera", nick: "alice"))
        #expect(!e.matches(networkSlug: "oftc", nick: "alice"))
    }

    @Test func matchesAnyNetworkSentinel() {
        // The "" slug means "any network" — preserves legacy behaviour
        // for entries the migration touches.
        var e = AddressEntry(nick: "alice")
        e.linkedNicks = [LinkedNick(networkSlug: "", nick: "alice", source: .migrated)]
        #expect(e.matches(networkSlug: "libera", nick: "alice"))
        #expect(e.matches(networkSlug: "oftc",   nick: "alice"))
        #expect(e.matches(networkSlug: "",        nick: "alice"))
    }

    @Test func matchesWalksMultipleLinkedNicks() {
        var e = AddressEntry(nick: "alice")
        e.linkedNicks = [
            LinkedNick(networkSlug: "libera",   nick: "alice"),
            LinkedNick(networkSlug: "oftc",     nick: "alice_"),
            LinkedNick(networkSlug: "undernet", nick: "ali"),
        ]
        #expect(e.matches(networkSlug: "libera",   nick: "alice"))
        #expect(e.matches(networkSlug: "oftc",     nick: "alice_"))
        #expect(e.matches(networkSlug: "undernet", nick: "ali"))
        #expect(!e.matches(networkSlug: "libera",  nick: "alice_"))  // wrong network for that alt
    }

    @Test func matchesAnyNetworkHelperIsPermissive() {
        var e = AddressEntry(nick: "alice")
        e.linkedNicks = [LinkedNick(networkSlug: "libera", nick: "alice_")]
        #expect(e.matchesAnyNetwork(nick: "alice_"))
        #expect(e.matchesAnyNetwork(nick: "ALICE_"))
        #expect(!e.matchesAnyNetwork(nick: "bob"))
    }

    @Test func allLinkedNicksLowercasedDedupes() {
        var e = AddressEntry(nick: "alice")
        e.linkedNicks = [
            LinkedNick(networkSlug: "libera", nick: "Alice"),
            LinkedNick(networkSlug: "oftc",   nick: "alice"),       // same nick lower-cased
            LinkedNick(networkSlug: "undernet", nick: "alice_"),
        ]
        let nicks = e.allLinkedNicksLowercased()
        #expect(nicks == ["alice", "alice_"])
    }

    // MARK: - SettingsStore mutators

    @MainActor
    private func freshStore() -> SettingsStore {
        let store = SettingsStore()
        store.settings = AppSettings()
        return store
    }

    @MainActor
    @Test func upsertSeedsLinkedNickWhenEmpty() {
        let store = freshStore()
        let entry = AddressEntry(nick: "alice", watch: true)
        #expect(entry.linkedNicks.isEmpty)
        store.upsertAddress(entry)
        #expect(store.settings.addressBook.count == 1)
        let stored = store.settings.addressBook[0]
        #expect(stored.linkedNicks.count == 1)
        #expect(stored.linkedNicks[0].nick == "alice")
        #expect(stored.linkedNicks[0].networkSlug == "")  // any-network sentinel
    }

    @MainActor
    @Test func linkNickIsIdempotent() {
        let store = freshStore()
        let entry = AddressEntry(nick: "alice", watch: true)
        store.upsertAddress(entry)
        let id = store.settings.addressBook[0].id
        store.linkNick(addressID: id, networkSlug: "libera", nick: "alice_")
        store.linkNick(addressID: id, networkSlug: "libera", nick: "alice_")
        store.linkNick(addressID: id, networkSlug: "libera", nick: "ALICE_")  // case-insensitive
        #expect(store.settings.addressBook[0].linkedNicks.count == 2)
    }

    @MainActor
    @Test func cannotRemoveLastLinkedNick() {
        let store = freshStore()
        let entry = AddressEntry(nick: "alice", watch: true)
        store.upsertAddress(entry)
        let id = store.settings.addressBook[0].id
        let lastLinkedID = store.settings.addressBook[0].linkedNicks[0].id
        let removed = store.unlinkNick(addressID: id, linkedNickID: lastLinkedID)
        #expect(removed == false)
        #expect(store.settings.addressBook[0].linkedNicks.count == 1)
    }

    @MainActor
    @Test func unlinkNickRemovesNonLast() {
        let store = freshStore()
        let entry = AddressEntry(nick: "alice", watch: true)
        store.upsertAddress(entry)
        let id = store.settings.addressBook[0].id
        store.linkNick(addressID: id, networkSlug: "oftc", nick: "alice_")
        let secondID = store.settings.addressBook[0].linkedNicks[1].id
        #expect(store.unlinkNick(addressID: id, linkedNickID: secondID))
        #expect(store.settings.addressBook[0].linkedNicks.count == 1)
    }

    // MARK: - watchedFromAddressBook

    @MainActor
    @Test func watchedFromAddressBookFlattensLinkedNicks() {
        let store = freshStore()
        var entry = AddressEntry(nick: "alice", watch: true)
        entry.linkedNicks = [
            LinkedNick(networkSlug: "libera", nick: "alice"),
            LinkedNick(networkSlug: "oftc",   nick: "alice_"),
        ]
        store.settings.addressBook = [entry]
        let watched = store.watchedFromAddressBook
        #expect(Set(watched.map { $0.lowercased() }) == Set(["alice", "alice_"]))
    }

    @MainActor
    @Test func unwatchedContactContributesNoNicks() {
        let store = freshStore()
        var entry = AddressEntry(nick: "alice", watch: false)
        entry.linkedNicks = [
            LinkedNick(networkSlug: "libera", nick: "alice"),
            LinkedNick(networkSlug: "oftc",   nick: "alice_"),
        ]
        store.settings.addressBook = [entry]
        #expect(store.watchedFromAddressBook.isEmpty)
    }

    @MainActor
    @Test func watchedFromAddressBookDedupesAcrossContacts() {
        // Two contacts both linked to "alice" (different slugs) — the
        // watch list should still see just one "alice", not two.
        let store = freshStore()
        var a = AddressEntry(nick: "alice", watch: true)
        a.linkedNicks = [LinkedNick(networkSlug: "libera", nick: "alice")]
        var b = AddressEntry(nick: "Alice", watch: true)        // case-insensitive dedupe
        b.linkedNicks = [LinkedNick(networkSlug: "oftc",   nick: "alice")]
        store.settings.addressBook = [a, b]
        #expect(store.watchedFromAddressBook.count == 1)
    }
}

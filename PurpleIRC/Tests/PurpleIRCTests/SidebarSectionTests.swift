import Foundation
import Testing
@testable import PurpleIRC

/// Behavior of the sidebar's per-section drag-to-reorder. Each section
/// (Networks, Channels, Private, Saved, Contacts) wires its `ForEach` to
/// `.onMove`; the underlying mutators all rely on the `Array.moveFiltered`
/// helper to keep non-moving rows where they were.
@Suite("Sidebar item reorder + launch-time server-buffer purge")
struct SidebarSectionTests {

    @MainActor
    private func makeStore() -> SettingsStore {
        let store = SettingsStore()
        store.settings = AppSettings()
        return store
    }

    // MARK: - Array.moveFiltered

    @Test func moveFilteredReordersOnlyMatchingElements() {
        // Mixed-kind array with two channels at indices 1 and 3 and a
        // server / query interleaved. Moving the second channel to be
        // first must leave the non-channel rows where they were.
        var arr = ["server", "#a", "alice", "#b", "bob"]
        arr.moveFiltered(from: IndexSet(integer: 1), to: 0) { $0.hasPrefix("#") }
        // Filtered view was [#a, #b]; moving filtered[1] (#b) to position 0
        // should produce filtered [#b, #a]. Underlying array preserves the
        // relative order of non-channel rows.
        #expect(arr == ["server", "#b", "alice", "#a", "bob"])
    }

    @Test func moveFilteredAppendingPastEnd() {
        // Destination = filtered.count means "drop after the last match."
        var arr = ["server", "#a", "alice", "#b", "#c"]
        arr.moveFiltered(from: IndexSet(integer: 0), to: 3) { $0.hasPrefix("#") }
        // Filtered was [#a, #b, #c]; moving filtered[0] (#a) to end →
        // filtered [#b, #c, #a]. Non-channels stay in place.
        #expect(arr == ["server", "#b", "alice", "#c", "#a"])
    }

    @Test func moveFilteredOnEmptyMatchIsNoOp() {
        var arr = ["alice", "bob", "carol"]
        arr.moveFiltered(from: IndexSet(integer: 0), to: 0) { $0.hasPrefix("#") }
        #expect(arr == ["alice", "bob", "carol"])
    }

    @Test func moveFilteredHandlesMultiSelect() {
        // Moving two filtered indices at once.
        var arr = ["x", "#a", "y", "#b", "#c"]
        arr.moveFiltered(from: IndexSet([0, 2]), to: 1) { $0.hasPrefix("#") }
        // Filtered [#a, #b, #c]; pulling out [#a, #c] and inserting before
        // filtered[1] (#b) → filtered [#a, #c, #b]. Underlying x/y stay.
        #expect(arr == ["x", "#a", "y", "#c", "#b"])
    }

    // MARK: - Saved-channel filtered move

    @MainActor
    @Test func moveSavedChannelsRespectsServerFilter() {
        let store = makeStore()
        let pid = UUID()
        let other = UUID()
        // Two saved channels under `pid`, one under `other`. Sidebar
        // filter shows both pid-scoped channels (and any nil-scoped); the
        // `other`-scoped one stays put when the user reorders the visible
        // pair.
        store.settings.savedChannels = [
            SavedChannel(name: "#alpha", note: "", serverID: pid),
            SavedChannel(name: "#beta",  note: "", serverID: other),
            SavedChannel(name: "#gamma", note: "", serverID: pid)
        ]
        store.moveSavedChannels(from: IndexSet(integer: 1), to: 0,
                                selectedServerID: pid)
        // Filtered list was [#alpha, #gamma]; moving filtered[1] to 0 →
        // [#gamma, #alpha]. The other-scoped #beta keeps its underlying
        // position.
        #expect(store.settings.savedChannels.map(\.name) ==
                ["#gamma", "#beta", "#alpha"])
    }

    @MainActor
    @Test func moveSavedChannelsIncludesNilScopedRows() {
        let store = makeStore()
        let pid = UUID()
        store.settings.savedChannels = [
            SavedChannel(name: "#shared", note: "", serverID: nil),
            SavedChannel(name: "#scoped", note: "", serverID: pid)
        ]
        store.moveSavedChannels(from: IndexSet(integer: 1), to: 0,
                                selectedServerID: pid)
        // The nil-scoped row counts as visible, so the filtered list is
        // [#shared, #scoped]; reorder swaps them.
        #expect(store.settings.savedChannels.map(\.name) ==
                ["#scoped", "#shared"])
    }

    // MARK: - Address-book reorder

    @MainActor
    @Test func moveAddressBookSimpleReorder() {
        let store = makeStore()
        store.settings.addressBook = [
            AddressEntry(id: UUID(), nick: "alice"),
            AddressEntry(id: UUID(), nick: "bob"),
            AddressEntry(id: UUID(), nick: "carol")
        ]
        store.moveAddressBook(from: IndexSet(integer: 2), to: 0)
        #expect(store.settings.addressBook.map(\.nick) == ["carol", "alice", "bob"])
    }

    // IRCConnection.moveBuffers / ChatModel.moveConnection / IRCConnection.purgeServerBuffer
    // are intentionally not unit-tested here: constructing an IRCConnection
    // pulls in WatchlistService.init, which calls
    // UNUserNotificationCenter.currentNotificationCenter and crashes outside
    // an .app bundle. Each of those methods is a thin wrapper around the
    // helpers exercised above (Array.moveFiltered for buffers,
    // Array.move(fromOffsets:toOffset:) for connections, a `buffers.removeAll
    // { $0.kind == .server }` for the purge).
}

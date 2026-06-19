import Foundation
import Testing
@testable import Ircle

/// Regression guard for the multi-server Settings crash (0.4.0): the editor's
/// `Binding<ServerProfile>` must resolve the profile by **id**, never by a
/// captured array index. A captured index goes out of range the moment a server
/// is removed while SwiftUI still holds the old binding — "Index out of range",
/// EXC_BREAKPOINT. Looking up by id stays safe across mutation.
@MainActor
@Suite("Settings server binding safety")
struct SettingsServerBindingTests {

    /// Mirrors the view's id-based getter/setter exactly.
    private func get(_ store: SettingsStore, _ id: UUID) -> ServerProfile {
        store.settings.servers.first(where: { $0.id == id }) ?? ServerProfile()
    }
    private func set(_ store: SettingsStore, _ id: UUID, _ value: ServerProfile) {
        if let idx = store.settings.servers.firstIndex(where: { $0.id == id }) {
            store.settings.servers[idx] = value
        }
    }

    private func tempStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-settings-\(UUID().uuidString)", isDirectory: true)
        return SettingsStore(directory: dir, secretStore: InMemorySecretStore())
    }

    @Test func idLookupSurvivesRemovalOfEarlierServer() {
        let store = tempStore()
        var a = ServerProfile(); a.name = "A"
        var b = ServerProfile(); b.name = "B"
        store.settings.servers = [a, b]

        // Remove the FIRST server: B's index shifts from 1 → 0.
        store.settings.servers.removeAll { $0.id == a.id }
        // An id-based getter still finds B at its new position — no crash, right value.
        #expect(get(store, b.id).name == "B")

        // Writing through the id-based setter still targets B.
        var edited = b; edited.name = "B-edited"
        set(store, b.id, edited)
        #expect(get(store, b.id).name == "B-edited")
    }

    @Test func idLookupReturnsDefaultWhenServerGone() {
        let store = tempStore()
        var a = ServerProfile(); a.name = "A"
        store.settings.servers = [a]
        let goneID = a.id
        store.settings.servers.removeAll { $0.id == goneID }
        // The crash scenario: binding read after removal. Must degrade, not trap.
        #expect(store.settings.servers.isEmpty)
        #expect(get(store, goneID).name == ServerProfile().name)  // default, no crash
        set(store, goneID, a)                                     // no-op, no crash
        #expect(store.settings.servers.isEmpty)
    }
}

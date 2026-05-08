import Foundation
import Testing
@testable import PurpleIRC

/// Behavior of the user-orderable sidebar section list and the launch-time
/// server-buffer purge. Both ship as a pair: the reorder feature is
/// observable in the UI, the purge is observable as "Private starts
/// empty every launch instead of showing yesterday's *server* row."
@Suite("Sidebar section reorder + server-buffer purge")
struct SidebarSectionTests {

    @MainActor
    private func makeStore() -> SettingsStore {
        let store = SettingsStore()
        store.settings = AppSettings()
        return store
    }

    // MARK: - moveSidebarSection

    @MainActor
    @Test func moveSectionInsertsBeforeTarget() {
        let store = makeStore()
        // Default: networks, channels, private, saved, contacts.
        store.moveSidebarSection(.contacts, before: .networks)
        #expect(store.settings.sidebarSectionOrder ==
                [.contacts, .networks, .channels, .privateBuffers, .saved])
    }

    @MainActor
    @Test func moveSectionToMiddleSlot() {
        let store = makeStore()
        store.moveSidebarSection(.saved, before: .channels)
        #expect(store.settings.sidebarSectionOrder ==
                [.networks, .saved, .channels, .privateBuffers, .contacts])
    }

    @MainActor
    @Test func moveSectionOntoSelfIsNoOp() {
        let store = makeStore()
        let before = store.settings.sidebarSectionOrder
        store.moveSidebarSection(.networks, before: .networks)
        #expect(store.settings.sidebarSectionOrder == before)
    }

    @MainActor
    @Test func moveSectionPreservesEverySection() {
        // Pathological reorder: every step should still leave all five
        // sections present. Drop-on-drop accidentally slicing a section
        // out of the list is the regression I worry about most here.
        let store = makeStore()
        store.moveSidebarSection(.contacts, before: .networks)
        store.moveSidebarSection(.saved, before: .privateBuffers)
        store.moveSidebarSection(.channels, before: .saved)
        #expect(Set(store.settings.sidebarSectionOrder) == Set(SidebarSection.allCases))
        #expect(store.settings.sidebarSectionOrder.count == SidebarSection.allCases.count)
    }

    @MainActor
    @Test func resetSectionOrderRestoresFactoryDefault() {
        let store = makeStore()
        store.settings.sidebarSectionOrder = [.contacts, .saved, .privateBuffers, .channels, .networks]
        store.resetSidebarSectionOrder()
        #expect(store.settings.sidebarSectionOrder == SidebarSection.defaultOrder)
    }

    @MainActor
    @Test func moveSectionRecoversFromDropOutsidePersistedList() {
        // Simulates a settings file that had been shaved down to a partial
        // list (e.g. a bug or hand-edit). moveSidebarSection should still
        // produce a normalized 5-section result.
        let store = makeStore()
        store.settings.sidebarSectionOrder = [.networks, .channels]
        store.moveSidebarSection(.contacts, before: .channels)
        // Still ends up well-formed and includes every section.
        #expect(Set(store.settings.sidebarSectionOrder) == Set(SidebarSection.allCases))
    }

    // IRCConnection.purgeServerBuffer is intentionally not unit-tested
    // here: constructing an IRCConnection pulls in WatchlistService.init,
    // which calls UNUserNotificationCenter.currentNotificationCenter and
    // crashes outside an .app bundle. The implementation is a 6-line
    // mutation against `buffers`, exercised end-to-end via the
    // launch-time path in ChatModel.purgeServerBuffersOnLaunch.
}

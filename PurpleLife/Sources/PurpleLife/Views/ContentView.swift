import SwiftUI

/// Main split-view surface — sidebar of types on the left, the selected
/// type's records on the right. Phase 2 starting point. Today / Planner
/// (Phase 3) takes over the detail-pane default once it lands.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        // Database health takeover. When the on-disk file is encrypted
        // with a key we no longer have, `RecoveryScreen` replaces the
        // entire window — there's no useful interaction to offer in the
        // broken state, and clicking into a sidebar where every query
        // fails is worse than a clear "this is what's wrong" screen.
        if case .unrecoverable(let detail) = appState.dbHealth {
            return AnyView(RecoveryScreen(
                detail: detail,
                onReset: { appState.resetUnrecoverableData() },
                hasRecoveryEnvelope: appState.keyStore.hasRecoveryEnvelope,
                onRecoveryKey: appState.keyStore.hasRecoveryEnvelope
                    ? { phrase in appState.tryRecoveryKeyUnlock(phrase: phrase) }
                    : nil
            ))
        }
        // Phase B (2026-05-15) — first-launch / migration takeover.
        // When a recovery key has just been generated the user MUST
        // be shown it before they can do anything else. This screen
        // is non-dismissable; the user clears it by going through
        // the confirmation typeback inside, which calls
        // `confirmRecoveryKeySaved()`.
        if let words = appState.pendingRecoveryKey {
            return AnyView(RecoveryKeySaveSheet(words: words) {
                appState.confirmRecoveryKeySaved()
            })
        }
        return AnyView(mainSplitView)
    }

    private var mainSplitView: some View {
        NavigationSplitView {
            Sidebar()
                // Clamp the sidebar column width so a user can never
                // drag the splitter to absurdity. AppKit's NSSplitView
                // (which SwiftUI's NavigationSplitView wraps on macOS)
                // persists subview frames in the app's UserDefaults
                // under the "NSSplitView Subview Frames …" key — if the
                // saved value exceeds the window width, the sidebar
                // takes the entire window and the detail pane is
                // invisible until the prefs are wiped. The
                // `navigationSplitViewColumnWidth` modifier caps the
                // max so even a hostile drag stays inside the window.
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
        } detail: {
            if appState.showTodayInDetail {
                TodayScreen()
            } else if let typeId = appState.selectedTypeId {
                // The Note type swaps the standard RecordsScreen for the
                // PurpleTracker-style two-pane Notes workspace. Same
                // ObjectEngine + sync underneath; just a different UX.
                if typeId == "Note" {
                    NotesWorkspaceView(typeId: typeId)
                } else {
                    RecordsScreen(typeId: typeId)
                }
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Wire SwiftUI's main-window undo manager into the engines
            // so ⌘Z routes to the same instance the mutation methods
            // register against. RecordsScreen and SchemaEditorScreen
            // re-do the same wiring on their own appear hooks (their
            // window may have a different env value), but doing it
            // here covers the Today screen and any other root-level
            // surface that mutates indirectly.
            ObjectEngine.undoManager = undoManager
            appState.schema.undoManager = undoManager
        }
    }

    fileprivate static let recoverySupportingLine =
        "All readable data is preserved in a timestamped `.unrecoverable-…/` " +
        "folder inside your Application Support directory; nothing is deleted."

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Pick a type from the sidebar")
                .font(.headline).foregroundStyle(.secondary)
            Text("\(AppVersion.display)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import Foundation
import SwiftUI
import Combine
import GRDB
import MasterClipperCore

@MainActor
final class iOSAppState: ObservableObject {
    @Published var snapshotReader = SnapshotReader()
    @Published var outbox: IntentOutbox

    @Published private(set) var clips: [Clip] = []
    @Published private(set) var personas: [Persona] = []
    @Published private(set) var sites: [Site] = []
    @Published private(set) var categories: [ClipCategory] = []

    @Published var searchText: String = ""
    @Published var personaFilter: String? = nil       // persona code or nil = all
    @Published var statusFilter: ClipStatus? = nil     // nil = all

    @Published private(set) var loadError: String?

    /// Operator name written into addNote intents. iOS-side it just defaults
    /// to "iPhone" until we surface a settings screen for it.
    @Published var operatorName: String = "iPhone"

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let reader = SnapshotReader()
        self.snapshotReader = reader
        self.outbox = IntentOutbox(reader: reader)

        // Re-run our in-memory queries whenever SnapshotReader publishes a
        // new manifest (i.e. the Mac just dropped a new snapshot in iCloud).
        // Also reconcile the outbox's pending list against the manifest's
        // `generated_at` — anything older has been confirmed by the Mac.
        snapshotReader.$manifest
            .removeDuplicates()
            .sink { [weak self] manifest in
                Task { @MainActor in
                    await self?.reloadFromSnapshot()
                    if let m = manifest { self?.outbox.reconcileWithManifest(m) }
                }
            }
            .store(in: &cancellables)
    }

    /// Called once from the App's `.task`. Boots the SnapshotReader and
    /// reloads in-memory collections.
    func start() async {
        await snapshotReader.start()
        await reloadFromSnapshot()
    }

    /// Re-run queries against the snapshot's GRDB queue. Called after
    /// SnapshotReader publishes a new manifest.
    func reloadFromSnapshot() async {
        guard let reader = snapshotReader.reader else {
            // No snapshot loaded yet — clear in-memory state.
            self.clips = []
            self.personas = []
            self.sites = []
            self.categories = []
            return
        }
        do {
            self.clips      = try ClipQueries.fetchAllClips(in: reader)
            self.personas   = try ClipQueries.fetchPersonas(in: reader)
            self.sites      = try ClipQueries.fetchSites(in: reader)
            self.categories = try ClipQueries.fetchCategories(in: reader)
            self.loadError = nil
        } catch {
            self.loadError = error.localizedDescription
        }
    }

    // MARK: - Derived data

    /// Apply search + filters in memory. Mirrors SearchService.matches; small
    /// libraries make this acceptable. Phase 5 swaps to FTS5.
    var filteredClips: [Clip] {
        clips.filter { clip in
            if let p = personaFilter, clip.personaCode.caseInsensitiveCompare(p) != .orderedSame {
                return false
            }
            if let s = statusFilter, clip.statusEnum != s {
                return false
            }
            return SearchService.matches(clip: clip, query: searchText, includeNotes: true)
        }
    }

    func persona(code: String) -> Persona? {
        personas.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    func site(id: Int64) -> Site? {
        sites.first { $0.id == id }
    }

    // MARK: - Per-clip fetch (postings, notes, categories)

    func postings(forClip clipId: String) -> [ClipPosting] {
        guard let reader = snapshotReader.reader else { return [] }
        return (try? ClipQueries.fetchPostings(forClip: clipId, in: reader)) ?? []
    }

    func notes(forClip clipId: String) -> [ClipNote] {
        guard let reader = snapshotReader.reader else { return [] }
        return (try? ClipQueries.fetchClipNotes(clipId: clipId, in: reader)) ?? []
    }

    func categories(forClip clipId: String) -> [ClipCategory] {
        guard let reader = snapshotReader.reader else { return [] }
        return (try? ClipQueries.fetchCategoriesForClip(clipId: clipId, in: reader)) ?? []
    }
}

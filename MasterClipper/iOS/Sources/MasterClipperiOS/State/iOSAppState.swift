import Foundation
import SwiftUI
import Combine
import GRDB
import MasterClipperCore

@MainActor
final class iOSAppState: ObservableObject {
    @Published var snapshotReader = SnapshotReader()
    @Published var outbox: IntentOutbox
    @Published var sharedReader = SharedZoneReader()

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
        // Pull any shared zones the recipient already accepted before this
        // launch (e.g. from a previous install).
        await sharedReader.refresh()
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

    /// Apply search + filters. When a search string is set and the snapshot
    /// has a FTS5 index, we run a SQL search (BM25-ranked, supports prefix
    /// matching). Otherwise we fall back to in-memory matching. Persona /
    /// status filters always apply on top.
    var filteredClips: [Clip] {
        var candidates: [Clip]

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let reader = snapshotReader.reader, ClipQueries.hasFTS(in: reader) {
            candidates = (try? ClipQueries.searchFTS(query: trimmed, in: reader)) ?? []
        } else {
            candidates = clips.filter { clip in
                SearchService.matches(clip: clip, query: searchText, includeNotes: true)
            }
        }

        return candidates.filter { clip in
            if let p = personaFilter, clip.personaCode.caseInsensitiveCompare(p) != .orderedSame {
                return false
            }
            if let s = statusFilter, clip.statusEnum != s {
                return false
            }
            return true
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

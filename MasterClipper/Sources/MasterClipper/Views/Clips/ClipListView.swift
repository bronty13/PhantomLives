import SwiftUI

struct ClipListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText: String = ""
    @State private var personaFilter: String = ""        // empty = all
    @State private var statusFilter: String = ""         // empty = all
    @State private var postingFilter: PostingFilter = .all
    @State private var includeArchived: Bool = false
    @State private var selection: Clip.ID?
    @State private var showingNewSheet: Bool = false
    @State private var showingExportSheet: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var postedSitesByClip: [String: Set<Int64>] = [:]
    @State private var sortOrder: [KeyPathComparator<Clip>] = [
        KeyPathComparator(\Clip.createdAt, order: .reverse)
    ]

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                clipTable
            }
            .frame(minWidth: 540)

            ClipDetailView(clipId: selection)
                .frame(minWidth: 480)
        }
        .navigationTitle("Clips")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingNewSheet = true
                } label: {
                    Label("New Clip", systemImage: "plus")
                }

                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export Clip…", systemImage: "square.and.arrow.up")
                }
                .disabled(selection == nil)

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection == nil)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Delete the selected clip (⌘⌫)")

                Button {
                    appState.reloadClips()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Delete this clip?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = selection { deleteClip(id: id) }
            }
        } message: {
            if let id = selection,
               let clip = appState.clips.first(where: { $0.id == id }) {
                let titleText = clip.title.isEmpty ? clip.id : "\"\(clip.title)\""
                Text("\(titleText) and all its postings, category links, and history will be permanently deleted. This cannot be undone — restore from a backup if you change your mind.")
            } else {
                Text("This clip and all its associated data will be permanently deleted. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            if let id = selection, let clip = appState.clips.first(where: { $0.id == id }) {
                ClipExportSheet(clip: clip) { showingExportSheet = false }
                    .environmentObject(appState)
            } else {
                Text("No clip selected").padding()
            }
        }
        .sheet(isPresented: $showingNewSheet) {
            NewClipView { newClip in
                selection = newClip.id
                showingNewSheet = false
            } onCancel: {
                showingNewSheet = false
            }
            .environmentObject(appState)
            .frame(minWidth: 460, minHeight: 380)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newClipRequested)) { _ in
            showingNewSheet = true
        }
        .onAppear {
            applyFocusedClipIfAny()
            applyPendingPostingFilterIfAny()
            reloadPostingsCache()
        }
        .onChange(of: appState.focusedClipId)        { _, _ in applyFocusedClipIfAny() }
        .onChange(of: appState.pendingPostingFilter) { _, _ in applyPendingPostingFilterIfAny() }
        .onChange(of: appState.clips.count)          { _, _ in reloadPostingsCache() }
    }

    private func applyFocusedClipIfAny() {
        guard let id = appState.focusedClipId else { return }
        // Clear any active filters that might exclude the focused clip so it's
        // visible in the table after navigation.
        searchText = ""
        personaFilter = ""
        statusFilter = ""
        postingFilter = .all
        if let clip = appState.clips.first(where: { $0.id == id }) {
            includeArchived = clip.archived
        }
        selection = id
        appState.focusedClipId = nil
    }

    private func applyPendingPostingFilterIfAny() {
        guard let f = appState.pendingPostingFilter else { return }
        // Reset other filters so the count matches what the dashboard showed.
        searchText = ""
        personaFilter = ""
        statusFilter = ""
        includeArchived = false
        postingFilter = f
        appState.pendingPostingFilter = nil
        reloadPostingsCache()
    }

    // MARK: - Subviews

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search title, description, keywords, ID…", text: $searchText)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)

            Divider().frame(height: 18)

            Picker("Persona", selection: $personaFilter) {
                Text("All personas").tag("")
                ForEach(appState.personas) { p in
                    Text(p.code).tag(p.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag("")
                ForEach(ClipStatus.allCases, id: \.self) { s in
                    Text(s.label).tag(s.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Picker("Posting", selection: $postingFilter) {
                ForEach(PostingFilter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Toggle("Archived", isOn: $includeArchived)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(10)
        .background(.background.secondary)
    }

    private var clipTable: some View {
        // Title is column 1 so it gets first claim on horizontal space and the
        // user sees it at a glance. The other columns are sized just-wide-enough
        // for their content; Title soaks up everything else.
        Table(filteredClips, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \Clip.title) { clip in
                Text(clip.title.isEmpty ? "—" : clip.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                    .help(clip.title)
            }
            .width(min: 260, ideal: 520)

            TableColumn("Persona", value: \Clip.personaCode) { clip in
                PersonaPill(code: clip.personaCode)
            }
            .width(min: 86, ideal: 96)

            TableColumn("Status", value: \Clip.status) { clip in
                Text(clip.statusEnum.label)
                    .font(.caption)
            }
            .width(min: 88, ideal: 96)

            TableColumn("Go-Live") { clip in
                Text(clip.goLiveDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle((clip.goLiveDate ?? "").isEmpty ? .tertiary : .secondary)
            }
            .width(min: 92, ideal: 100)

            TableColumn("Length") { clip in
                Text(DurationFormatter.format(clip.lengthSeconds))
                    .font(.caption.monospacedDigit())
            }
            .width(min: 56, ideal: 68)

            TableColumn("ID", value: \Clip.id) { clip in
                Text(clip.id).font(.caption.monospaced())
            }
            .width(min: 130, ideal: 140)
        }
        .onChange(of: sortOrder) { _, newOrder in
            // Sort applies on the in-memory list — handled in filteredClips.
            _ = newOrder
        }
        .contextMenu(forSelectionType: Clip.ID.self) { ids in
            if let id = ids.first {
                Button("Edit") { selection = id }
                Divider()
                Button("Mark as historical (all scope sites posted)") {
                    markHistorical(id: id)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deleteClip(id: id)
                }
            }
        }
    }

    // MARK: - Filtering

    private var filteredClips: [Clip] {
        var result = appState.clips

        if !includeArchived {
            result = result.filter { !$0.archived }
        }

        if !personaFilter.isEmpty {
            result = result.filter { $0.personaCode.caseInsensitiveCompare(personaFilter) == .orderedSame }
        }

        if !statusFilter.isEmpty {
            result = result.filter { $0.status == statusFilter }
        }

        if postingFilter != .all {
            result = result.filter { matchesPostingFilter($0) }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let inclNotes = appState.settings.includeNotesInGlobalSearch
            result = result.filter { SearchService.matches(clip: $0, query: searchText, includeNotes: inclNotes) }
        }

        return result.sorted(using: sortOrder)
    }

    private func matchesPostingFilter(_ clip: Clip) -> Bool {
        let scoped = appState.sites
            .filter { !$0.archived && $0.appliesTo(personaCode: clip.personaCode) }
        let scopedIds = Set(scoped.compactMap(\.id))
        let posted = postedSitesByClip[clip.id] ?? []
        let postedInScope = posted.intersection(scopedIds)
        switch postingFilter {
        case .all:         return true
        case .fullyPosted: return !scopedIds.isEmpty && postedInScope.count == scopedIds.count
        case .partial:     return !postedInScope.isEmpty && postedInScope.count < scopedIds.count
        case .notPosted:   return postedInScope.isEmpty && !scopedIds.isEmpty
        case .noScope:     return scopedIds.isEmpty
        }
    }

    /// Refresh the posting cache used by the posting-completeness filter. Pulls
    /// every `clip_postings` row and groups posted ones by clip; cheap enough
    /// to re-run on view appear and on clip-count change.
    private func reloadPostingsCache() {
        do {
            let postings = try DatabaseService.shared.dbPool.read { db in
                try ClipPosting.fetchAll(db)
            }
            var map: [String: Set<Int64>] = [:]
            for p in postings where p.statusEnum == .posted {
                map[p.clipId, default: []].insert(p.siteId)
            }
            postedSitesByClip = map
        } catch {
            postedSitesByClip = [:]
        }
    }

    private func deleteClip(id: String) {
        do {
            try appState.deleteClip(id: id)
            if selection == id { selection = nil }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func markHistorical(id: String) {
        do {
            _ = try DatabaseService.shared.markAllScopedSitesPosted(clipId: id)
            appState.reloadClips()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

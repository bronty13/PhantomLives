import SwiftUI

/// Tags Increment 3b — Advanced Search window.
///
/// A dedicated window (separate from ⌘K Quick Switcher) for cross-
/// type queries with structured filtering: type scope, tag include
/// (.any / .all) or untagged-only, date range, and Vault gating.
/// Reachable via ⌘⇧F, via the Sidebar's "Search" entry, and via the
/// "Open in Search…" footer on Quick Switcher (Phase 3d).
///
/// **Vault gating** matches the 2026-05-14 design: when the Vault is
/// locked, the "Include Vault" checkbox is *hidden entirely* (its
/// existence is not telegraphed to a casual viewer) and the type
/// picker omits Vault types. When the Vault is unlocked, the
/// checkbox appears unchecked by default — the user has to opt in
/// per-search. Phase 3c locks the contract in tests.
struct SearchScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var query: String = ""
    @State private var selectedTypeIds: Set<String> = []
    @State private var selectedTagIds: Set<String> = []
    @State private var tagMatchMode: SearchService.TagMatchMode = .any
    @State private var untaggedOnly: Bool = false
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var includeVault: Bool = false
    @State private var hits: [SearchService.Hit] = []
    @State private var initialQuery: String? = nil

    /// One value that collapses every filter input into a single
    /// observable token. Reduces a stack of nine `.onChange`
    /// modifiers (which blows the SwiftUI type checker on macOS)
    /// down to one — and as a bonus runs `runSearch()` at most once
    /// per render cycle even when several inputs change together
    /// (e.g. when re-locking the Vault clears multiple states).
    private var filterSignature: String {
        var parts: [String] = []
        parts.append(query)
        parts.append(selectedTypeIds.sorted().joined(separator: ","))
        parts.append(selectedTagIds.sorted().joined(separator: ","))
        parts.append(tagMatchMode.rawValue)
        parts.append(untaggedOnly ? "untag" : "")
        parts.append(dateFrom.map { String($0.timeIntervalSince1970) } ?? "")
        parts.append(dateTo.map { String($0.timeIntervalSince1970) } ?? "")
        parts.append(includeVault ? "vault" : "")
        return parts.joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            queryHeader
            Divider()
            filtersBar
            Divider()
            resultsList
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            // The Quick Switcher footer (Phase 3d) sets
            // `appState.searchHandoffQuery` to seed the first query
            // when opening the window via "Open in Search…". Pick
            // that up once on appear, then clear it so subsequent
            // opens with a different query are honored.
            if let handoff = appState.searchHandoffQuery, !handoff.isEmpty {
                query = handoff
                appState.searchHandoffQuery = nil
            }
            runSearch()
        }
        .onChange(of: filterSignature) { _, _ in runSearch() }
        .onChange(of: appState.vaultRevealed) { _, revealed in
            // Re-locking the Vault while the search window is open
            // must clear the user's "include Vault" choice and any
            // Vault-type selections from the chip list. Otherwise
            // the locked-Vault SQL would still receive a filter
            // referencing Vault type ids and silently drop hits.
            // The filterSignature change that this triggers will
            // re-run the search.
            if !revealed {
                includeVault = false
                selectedTypeIds.subtract(appState.schema.vaultTypeIds)
            }
        }
    }

    // MARK: - Query header

    private var queryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.large)
            TextField("Search across every type…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Filter bar

    private var filtersBar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                typesSection
                tagsSection
                dateSection
                if appState.vaultRevealed {
                    vaultSection
                }
            }
            .padding(14)
        }
        .frame(maxHeight: 240)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    private var typesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Types",
                         hint: selectedTypeIds.isEmpty ? "all visible" : "\(selectedTypeIds.count) selected")
            FlowChips {
                ForEach(visibleTypesForPicker, id: \.id) { type in
                    typeChip(type)
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("Tags",
                             hint: tagsHint)
                Spacer()
                if selectedTagIds.count > 1 && !untaggedOnly {
                    Picker("", selection: $tagMatchMode) {
                        Text("Any of").tag(SearchService.TagMatchMode.any)
                        Text("All of").tag(SearchService.TagMatchMode.all)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .labelsHidden()
                }
                Toggle("Untagged only", isOn: $untaggedOnly)
                    .toggleStyle(.checkbox)
                    .disabled(!selectedTagIds.isEmpty)
            }
            if !untaggedOnly {
                FlowChips {
                    ForEach(TagService.allTags) { tag in
                        tagChip(tag)
                    }
                }
                if TagService.allTags.isEmpty {
                    Text("No tags yet — add tags from any record's Detail view.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Updated", hint: dateHint)
            HStack(spacing: 12) {
                quickDateButton("Any time")        { dateFrom = nil; dateTo = nil }
                quickDateButton("Last 24 hours")   { dateFrom = Date().addingTimeInterval(-86400); dateTo = nil }
                quickDateButton("Last 7 days")     { dateFrom = Date().addingTimeInterval(-7 * 86400); dateTo = nil }
                quickDateButton("Last 30 days")    { dateFrom = Date().addingTimeInterval(-30 * 86400); dateTo = nil }
                Spacer()
            }
            HStack(spacing: 8) {
                Text("From").font(.caption).foregroundStyle(.tertiary)
                customDatePicker(date: $dateFrom, fallbackLabel: "any")
                Text("To").font(.caption).foregroundStyle(.tertiary)
                customDatePicker(date: $dateTo, fallbackLabel: "now")
            }
        }
    }

    private var vaultSection: some View {
        // Phase 3c: only rendered when vaultRevealed is true. When
        // locked, the entire surface is hidden so the existence of
        // the Vault is not telegraphed to a casual viewer.
        HStack(spacing: 8) {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(.purple)
                .imageScale(.small)
            Toggle("Include Vault records in results", isOn: $includeVault)
                .toggleStyle(.checkbox)
        }
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        if hits.isEmpty {
            emptyResults
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { hit in
                        Button {
                            open(hit)
                        } label: {
                            resultRow(hit)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: query.isEmpty ? "magnifyingglass" : "questionmark.circle")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text(query.isEmpty
                 ? "Type a query, pick filters, or both."
                 : "No matches for those filters.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ hit: SearchService.Hit) -> some View {
        let type = appState.schema.type(id: hit.typeId)
        let tone: Color = type.flatMap { Color(hex: $0.colorHex) } ?? .accentColor
        return HStack(spacing: 12) {
            Image(systemName: type?.systemImage ?? "doc")
                .foregroundStyle(tone)
                .frame(width: 28, height: 28)
                .background(tone.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title.isEmpty ? "Untitled" : hit.title)
                    .font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    Text(type?.name ?? hit.typeId)
                        .font(.caption2).foregroundStyle(.tertiary)
                    if !hit.body.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(hit.body)
                            .font(.caption2).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// Type chips shown in the picker. Phase 3c: Vault types appear
    /// only when the Vault is unlocked AND "Include Vault" is
    /// checked — otherwise the casual-viewer privacy story leaks.
    private var visibleTypesForPicker: [ObjectType] {
        var types = appState.schema.visibleTypes
        if appState.vaultRevealed && includeVault {
            types += appState.schema.visibleVaultTypes
        }
        return types
    }

    private var tagsHint: String {
        if untaggedOnly { return "untagged records only" }
        if selectedTagIds.isEmpty { return "any" }
        return "\(selectedTagIds.count) selected · \(tagMatchMode == .all ? "all of" : "any of")"
    }

    private var dateHint: String {
        switch (dateFrom, dateTo) {
        case (nil, nil): return "any time"
        case (let f?, nil): return "since \(shortDate(f))"
        case (nil, let t?): return "until \(shortDate(t))"
        case (let f?, let t?): return "\(shortDate(f)) – \(shortDate(t))"
        }
    }

    private func sectionLabel(_ title: String, hint: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase).tracking(0.5)
                .foregroundStyle(.secondary)
            Text("· \(hint)")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func typeChip(_ type: ObjectType) -> some View {
        let on = selectedTypeIds.contains(type.id)
        let tone = Color(hex: type.colorHex) ?? .accentColor
        return Button {
            if on { selectedTypeIds.remove(type.id) } else { selectedTypeIds.insert(type.id) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: type.systemImage).imageScale(.small)
                Text(type.pluralName).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(on ? tone.opacity(0.25) : Color.secondary.opacity(0.08))
            .foregroundStyle(on ? tone : Color.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tagChip(_ tag: TagDef) -> some View {
        let on = selectedTagIds.contains(tag.id)
        let tone = tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return Button {
            if on { selectedTagIds.remove(tag.id) } else { selectedTagIds.insert(tag.id) }
        } label: {
            Text(tag.name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(on ? tone.opacity(0.25) : Color.secondary.opacity(0.08))
                .foregroundStyle(on ? tone : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickDateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .font(.caption)
    }

    private func customDatePicker(date: Binding<Date?>, fallbackLabel: String) -> some View {
        HStack(spacing: 6) {
            if let unwrapped = date.wrappedValue {
                DatePicker("", selection: Binding(
                    get: { unwrapped },
                    set: { date.wrappedValue = $0 }
                ), displayedComponents: .date)
                    .labelsHidden()
                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button(fallbackLabel) {
                    date.wrappedValue = Date()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: d)
    }

    // MARK: - Search

    private func runSearch() {
        var filter = SearchService.Filter()
        filter.query = query
        if !selectedTypeIds.isEmpty {
            filter.typeIds = selectedTypeIds
        }
        // Vault exclusion: always pass the Vault type ids unless the
        // user has explicitly opted in via the "Include Vault"
        // checkbox (which is only reachable when the Vault is
        // unlocked).
        if !(appState.vaultRevealed && includeVault) {
            filter.excludingTypeIds = appState.schema.vaultTypeIds
        }
        filter.requiredTagIds = selectedTagIds
        filter.tagMatchMode = tagMatchMode
        filter.untaggedOnly = untaggedOnly
        if dateFrom != nil || dateTo != nil {
            filter.dateRange = .init(from: dateFrom, to: dateTo)
        }
        hits = SearchService.search(filter)
    }

    private func open(_ hit: SearchService.Hit) {
        appState.selectedTypeId = hit.typeId
        appState.showTodayInDetail = false
        appState.openRecordRequest = hit.recordId
    }
}

/// Local flow layout for the chip clusters in the filter bar. Same
/// shape as the one in `TagPillRow.swift`; redeclared here to keep
/// the views decoupled (no `internal` Layout type leak).
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        FlowLayout(spacing: 6) { content() }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: maxRowWidth, height: y + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

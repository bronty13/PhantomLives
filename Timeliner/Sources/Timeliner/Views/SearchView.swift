import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search across all cases, events, people, and tags…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !query.isEmpty {
                    Button("Clear") { query = "" }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                Text("Type to search.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let results = SearchService.run(
                    query: query,
                    cases: appState.cases,
                    events: appState.events,
                    people: appState.people,
                    tags: appState.tags,
                    tagsByEvent: appState.tagsByEvent
                )
                if results.isEmpty {
                    Spacer()
                    Text("No matches.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(results, id: \.id) { hit in
                                SearchHitRow(hit: hit) {
                                    open(hit)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }

    private func open(_ hit: SearchService.Hit) {
        switch hit.kind {
        case .case_:
            appState.selectedCaseId = hit.id
            appState.selectedSection = .allCases
        case .event(let caseId):
            appState.selectedCaseId = caseId
            appState.selectedSection = .allCases
        case .person(let caseId):
            appState.selectedCaseId = caseId
            appState.selectedSection = .allCases
        case .tag:
            // Tag hits open the Tags pane.
            appState.selectedSection = .tags
        }
    }
}

private struct SearchHitRow: View {
    let hit: SearchService.Hit
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hit.kind.systemImage)
                    .foregroundStyle(hit.kind.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(hit.title).font(.body.weight(.semibold))
                        Spacer()
                        Text(hit.kind.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !hit.subtitle.isEmpty {
                        Text(hit.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

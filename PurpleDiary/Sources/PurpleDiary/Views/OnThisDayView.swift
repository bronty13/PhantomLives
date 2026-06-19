import SwiftUI

/// "On This Day": entries written on today's month-and-day in previous years,
/// grouped by how long ago. A purely local look back over your own journal —
/// nothing is fetched. Respects the active journal + hidden-journal filter
/// (operates on `visibleEntries`). Tapping an entry jumps to it in the Timeline.
struct OnThisDayView: View {
    @EnvironmentObject private var appState: AppState

    private var matches: [Entry] {
        OnThisDayService.entries(from: appState.onThisDayEntries)
    }

    var body: some View {
        Group {
            if matches.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.label) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    EntryRow(entry: entry,
                                             tags: appState.tagsByEntry[entry.id] ?? [],
                                             isSelected: false,
                                             concealed: appState.journalsById[entry.journalId]?.concealContent ?? false)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            appState.selectedEntryId = entry.id
                                            appState.selectedSection = .timeline
                                        }
                                }
                            } header: {
                                Text(group.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(.bar)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct YearGroup { let label: String; let entries: [Entry] }

    private var grouped: [YearGroup] {
        let today = Date()
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for entry in matches {
            let label = OnThisDayService.label(yearsAgo: OnThisDayService.yearsAgo(entry.dateValue, today: today))
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(entry)
        }
        return order.map { YearGroup(label: $0, entries: buckets[$0] ?? []) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Nothing from this day yet")
                .font(.headline)
            Text("Once you've journaled on this date in an earlier year, your past entries will show up here to look back on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

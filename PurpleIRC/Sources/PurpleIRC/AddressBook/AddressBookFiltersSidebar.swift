import SwiftUI

/// Left sidebar of the Address Book workspace. Hosts the filter
/// sections (presence, network coverage, recency) plus a list of
/// every defined `ContactTag` and a Recent Hits panel.
struct AddressBookFiltersSidebar: View {
    @EnvironmentObject var model: ChatModel
    @Binding var filter: AddressBookFilter

    var body: some View {
        List(selection: tagSelectionBinding) {
            Section("Presence") {
                ForEach(AddressBookFilter.PresenceFilter.allCases) { f in
                    Button {
                        filter.presence = f
                    } label: {
                        HStack {
                            Image(systemName: presenceIcon(for: f))
                                .foregroundStyle(presenceColor(for: f))
                                .frame(width: 16)
                            Text(f.label)
                            Spacer()
                            if filter.presence == f {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Network coverage") {
                ForEach(AddressBookFilter.CoverageFilter.allCases) { f in
                    Button {
                        filter.coverage = f
                    } label: {
                        HStack {
                            Image(systemName: coverageIcon(for: f))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(f.label)
                            Spacer()
                            if filter.coverage == f {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Recency") {
                ForEach(AddressBookFilter.RecencyFilter.allCases) { f in
                    Button {
                        filter.recency = f
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(f.label)
                            Spacer()
                            if filter.recency == f {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !model.settings.settings.contactTags.isEmpty {
                Section("Tags") {
                    Button {
                        filter.tagID = nil
                    } label: {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text("All tags")
                            Spacer()
                            if filter.tagID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(model.settings.settings.contactTags) { tag in
                        Button {
                            filter.tagID = (filter.tagID == tag.id) ? nil : tag.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tagColor(tag))
                                    .frame(width: 10, height: 10)
                                Text(tag.name.isEmpty ? "Untitled tag" : tag.name)
                                Spacer()
                                Text("\(usageCount(for: tag))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if filter.tagID == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.watchlist.recentHits.isEmpty {
                Section("Recent hits") {
                    ForEach(model.watchlist.recentHits.prefix(10)) { hit in
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.nick).font(.callout)
                                Text(hit.source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(relativeTimeString(hit.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helpers

    private var tagSelectionBinding: Binding<UUID?> {
        Binding(get: { filter.tagID }, set: { filter.tagID = $0 })
    }

    private func presenceIcon(for f: AddressBookFilter.PresenceFilter) -> String {
        switch f {
        case .any:     return "circle.dotted"
        case .online:  return "circle.fill"
        case .offline: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func presenceColor(for f: AddressBookFilter.PresenceFilter) -> Color {
        switch f {
        case .online:  return .green
        case .offline: return .secondary
        default:       return .secondary
        }
    }

    private func coverageIcon(for f: AddressBookFilter.CoverageFilter) -> String {
        switch f {
        case .any:      return "globe"
        case .single:   return "1.circle"
        case .multi:    return "infinity"
        case .unlinked: return "link.badge.plus"
        }
    }

    private func tagColor(_ tag: ContactTag) -> Color {
        if let hex = tag.colorHex, let c = Color(hex: hex) { return c }
        return .purple
    }

    private func usageCount(for tag: ContactTag) -> Int {
        model.settings.settings.addressBook
            .filter { $0.tagIDs.contains(tag.id) }
            .count
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

import SwiftUI

/// Fixed-width sidebar: app title, the five top-level sections, and a small
/// stats footer. Sections are plain tappable rows (not a `List` selection)
/// to stay consistent with the manual-layout pattern.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppState.Section.allCases, id: \.self) { section in
                        sectionRow(section)
                    }
                }
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(appState.effectiveAccentColor)
                .font(.title3)
            Text("PurpleDiary")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionRow(_ section: AppState.Section) -> some View {
        let isSelected = appState.selectedSection == section
        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? appState.effectiveAccentColor : .secondary)
                Text(section.title)
                    .foregroundStyle(.primary)
                Spacer()
                if section == .timeline {
                    Text("\(appState.entries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? appState.effectiveAccentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private var footer: some View {
        let totalWords = appState.entries.reduce(0) { $0 + $1.wordCount }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Entries").foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.entries.count)")
            }
            HStack {
                Text("Words").foregroundStyle(.secondary)
                Spacer()
                Text("\(totalWords)")
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

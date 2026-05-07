import SwiftUI

/// Hybrid sidebar selection: top-level sections OR a specific case. Modeled
/// as an enum so SwiftUI's `List(selection:)` binding works against a single
/// `Hashable` type.
enum SidebarSelection: Hashable {
    case section(AppState.Section)
    case caseRow(String)        // case.id
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: Binding<SidebarSelection?>(
            get: {
                if let id = appState.selectedCaseId,
                   appState.selectedSection == .allCases {
                    return .caseRow(id)
                }
                return .section(appState.selectedSection)
            },
            set: { newValue in
                guard let s = newValue else { return }
                switch s {
                case .section(let sec):
                    appState.selectedSection = sec
                case .caseRow(let id):
                    appState.selectedSection = .allCases
                    appState.selectedCaseId = id
                }
            }
        )) {
            Section("Timeliner") {
                ForEach(AppState.Section.allCases, id: \.self) { section in
                    NavigationLink(value: SidebarSelection.section(section)) {
                        Label {
                            HStack {
                                Text(section.title)
                                Spacer()
                                if let badge = badge(for: section) {
                                    Text(badge)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                    }
                }
            }

            if !appState.cases.isEmpty {
                Section("Cases") {
                    ForEach(appState.cases) { aCase in
                        NavigationLink(value: SidebarSelection.caseRow(aCase.id)) {
                            CaseRow(aCase: aCase)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Timeliner")
        .frame(minWidth: 240)
    }

    private func badge(for section: AppState.Section) -> String? {
        switch section {
        case .allCases:
            return appState.cases.isEmpty ? nil : "\(appState.cases.count)"
        case .people:
            return appState.people.isEmpty ? nil : "\(appState.people.count)"
        case .tags:
            return appState.tags.isEmpty ? nil : "\(appState.tags.count)"
        default:
            return nil
        }
    }
}

private struct CaseRow: View {
    @EnvironmentObject private var appState: AppState
    let aCase: Case

    var body: some View {
        HStack {
            if aCase.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Image(systemName: aCase.statusEnum.systemImage)
                    .foregroundStyle(aCase.statusEnum.tint)
                    .font(.caption)
            }
            Text(aCase.title.isEmpty ? "Untitled case" : aCase.title)
                .lineLimit(1)
            Spacer()
            let count = appState.events.filter { $0.caseId == aCase.id }.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button(aCase.pinned ? "Unpin" : "Pin") {
                try? appState.togglePin(caseId: aCase.id)
            }
            Divider()
            Button("Delete Case…", role: .destructive) {
                NotificationCenter.default.post(
                    name: .deleteCaseRequested,
                    object: aCase.id
                )
            }
        }
    }
}

extension Notification.Name {
    static let deleteCaseRequested = Notification.Name("Timeliner.deleteCaseRequested")
}

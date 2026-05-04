import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedSection },
            set: { appState.selectedSection = $0 ?? .dashboard }
        )) {
            Section("MasterClipper") {
                ForEach(AppState.Section.allCases, id: \.self) { section in
                    NavigationLink(value: section) {
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
        }
        .listStyle(.sidebar)
        .navigationTitle("MasterClipper")
        .frame(minWidth: 220)
    }

    private func badge(for section: AppState.Section) -> String? {
        switch section {
        case .clips:
            return "\(appState.clips.count)"
        case .editingQueue:
            // Mirror the Editing Queue's default status filter: anything
            // that isn't yet fully through Editing (new + editing + toPost).
            let n = appState.clips.filter {
                !$0.archived &&
                ($0.statusEnum == .new || $0.statusEnum == .editing || $0.statusEnum == .toPost)
            }.count
            return n > 0 ? "\(n)" : nil
        case .postingQueue:
            let n = appState.clips.filter {
                !$0.archived && ($0.statusEnum == .toPost || $0.statusEnum == .posting)
            }.count
            return n > 0 ? "\(n)" : nil
        default:
            return nil
        }
    }
}

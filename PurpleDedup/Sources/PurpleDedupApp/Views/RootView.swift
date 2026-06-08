import SwiftUI
import PurpleDedupCore

/// Top-level mode the window is showing.
enum AppMode: String, CaseIterable, Hashable {
    case dedup
    case audit
}

/// Window shell that switches between the two top-level workflows:
/// **Dedup** (the existing `ContentView`) and **Audit against Photos**
/// (`AuditView`). A thin segmented switcher sits above the active view; the
/// dedup layout is left completely untouched (its `NavigationSplitView` and
/// toolbar still own the window chrome when it's the active mode).
struct RootView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var mode: AppMode = .dedup

    var body: some View {
        VStack(spacing: 0) {
            modeSwitcher
            Divider()
            Group {
                switch mode {
                case .dedup: ContentView(settingsStore: settingsStore)
                case .audit: AuditView(settingsStore: settingsStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 10) {
            Picker("", selection: $mode) {
                Label("Find Duplicates", systemImage: "square.stack.3d.up")
                    .tag(AppMode.dedup)
                Label("Audit vs Photos", systemImage: "checklist")
                    .tag(AppMode.audit)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Switch between finding duplicates and auditing a folder against your Photos library.")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

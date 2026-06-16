import SwiftUI

/// Root layout: a fixed-width sidebar + main area in a manual `HStack` (the PhantomLives
/// pattern — NOT `NavigationSplitView`, which mis-restores divider widths on macOS 14+).
///
/// Phase 1 wires the two panes and the themed background. The folder grid, detail panel,
/// and Preview-mode content arrive in later phases; for now the main area shows an
/// empty-state prompt.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .background(theme.sidebarBackground)
                Divider()
            }
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $appState.appMode) {
                    ForEach(AppMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
    }

    // MARK: - Main area

    @ViewBuilder
    private var mainArea: some View {
        ZStack {
            LinearGradient(
                colors: theme.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(theme.accentColor)
            Text("Drop a folder to begin")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("PurplePeek will scan it for photos, videos, and audio so you can triage them before importing to Photos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }
}

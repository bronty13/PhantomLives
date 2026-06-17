import SwiftUI
import AppKit

/// The Browse-mode main area: a header (current scope + counts + grid/list toggle) over
/// either the thumbnail grid or a compact list. Shows a scan progress overlay while a scan
/// is running, and an empty state when the selected scope has no media.
struct FolderBrowseView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @AppStorage("browseLayoutIsGrid") private var isGrid: Bool = true

    /// Local key monitor for the Space → Quick Look "peek" (Finder-style).
    @State private var keyMonitor: Any?

    private var files: [MediaFile] { appState.visibleMediaFiles }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .overlay { if appState.isScanning { scanOverlay } }
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
        // Keep an open peek in step as the selection moves (click another thumbnail).
        .onChange(of: appState.selectedFileId) { _, _ in
            if let f = appState.selectedFile { QuickLookCoordinator.shared.refreshIfVisible(f.fileURL) }
        }
    }

    // MARK: - Keyboard (Space → peek)

    private func installMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard appState.appMode == .folderBrowse else { return event }
            // Don't steal Space while a title/caption field (detail panel) is being edited.
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            guard event.keyCode == 49 else { return event }   // 49 = space
            guard let file = appState.selectedFile else { return event }
            QuickLookCoordinator.shared.toggle(file.fileURL)
            return nil
        }
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scopeTitle).font(.headline).lineLimit(1)
                Text(countSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Show", selection: $appState.gridDecisionFilter) {
                ForEach(DecisionFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("Filter by decision — pick Decided / Kept / Skipped to review choices you've made")
            Picker("Layout", selection: $isGrid) {
                Image(systemName: "square.grid.2x2").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var scopeTitle: String {
        if let folder = appState.selectedFolderPath { return (folder as NSString).lastPathComponent }
        if let root = appState.selectedRootPath { return (root as NSString).lastPathComponent }
        return "PurplePeek"
    }

    private var countSummary: String {
        let total = files.count
        let undecided = files.filter { $0.keep == nil }.count
        let kept = files.filter { $0.keepDecision == true }.count
        return "\(total) item\(total == 1 ? "" : "s") · \(undecided) undecided · \(kept) keep"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if files.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                Text("No media here").font(.title3)
                Text("Nothing to triage in this folder.").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isGrid {
            MediaGridView(files: files)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        MediaListRow(
                            file: file,
                            isSelected: appState.selectedFileId == file.id,
                            onTap: { appState.selectFile(file.id) }
                        )
                        Divider().opacity(0.15)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Scan overlay

    private var scanOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: appState.scanProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 260)
                    .tint(theme.accentColor)
                Text(appState.scanMessage)
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

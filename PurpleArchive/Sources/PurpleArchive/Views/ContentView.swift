import SwiftUI
import UniformTypeIdentifiers
import ArchiveKit

/// Top-level layout: a fixed-width manual `HStack` sidebar (NOT
/// `NavigationSplitView` — see docs/sidebar-layout.md), a detail pane, and a
/// status bar. The whole window accepts drops: an archive opens in Browse,
/// other files go to Compress.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sidebarVisible") private var sidebarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if sidebarVisible {
                    SidebarView()
                        .frame(width: 220)
                        .background(.ultraThinMaterial)
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { sidebarVisible.toggle() } } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers); return true
        }
        .alert("Couldn’t complete that", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private var detail: some View {
        switch model.sidebarSelection {
        case .browse: ArchiveBrowserView()
        case .compress: CompressDropView()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let info = model.info, model.sidebarSelection == .browse {
                Text("\(info.entryCount) entries")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            // A single archive → browse it; anything else → compress.
            if urls.count == 1, ArchiveProbe.looksLikeArchive(urls[0]) {
                model.sidebarSelection = .browse
                model.open(urls[0])
            } else {
                model.sidebarSelection = .compress
                model.compress(urls)
            }
        }
    }
}

/// Lightweight "is this an archive we should open vs compress" check by
/// extension. (Deep magic-byte detection lives in the engine; this is just for
/// the drop-routing decision.)
enum ArchiveProbe {
    static func looksLikeArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        // Raw split volumes (.001/.002/…) are archives too.
        if ext.count >= 2, ext.allSatisfy(\.isNumber) { return true }
        return ArchiveFormat.forFilename(url.lastPathComponent) != nil
            || ["rar", "7z", "cab", "iso", "lha", "lzh", "cpio", "ar", "xar", "sit", "sitx", "cpt", "hqx"]
                .contains(ext)
    }
}

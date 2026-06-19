import SwiftUI
import AppKit

/// A read-only browser for the saved chat logs under
/// ~/Downloads/Ircle/Logs/<network>/<target>.log. Sidebar of conversations on
/// the left (manual fixed-width HStack per docs/sidebar-layout.md), the selected
/// transcript on the right.
struct LogViewerView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var files: [LogFile] = []
    @State private var selected: LogFile.ID?
    @State private var content: String = ""

    private var palette: PlatinumPalette { settingsStore.palette }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(palette.paneBG)
            Divider().overlay(palette.hairline)
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.textBG)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([LogService.shared.directory])
                } label: { Label("Reveal in Finder", systemImage: "folder") }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: selected) { _, _ in loadSelected() }
    }

    private var sidebar: some View {
        Group {
            if files.isEmpty {
                VStack(spacing: 6) {
                    Text("No logs yet.").font(palette.chromeFontBold())
                    Text("Enable logging in Settings → Logging, then chat.")
                        .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List(selection: $selected) {
                    ForEach(networks, id: \.self) { net in
                        Section(net) {
                            ForEach(files.filter { $0.network == net }) { f in
                                Text(f.target).tag(Optional(f.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private var transcript: some View {
        ScrollView {
            Text(content.isEmpty ? "Select a conversation." : content)
                .font(.custom("Monaco", size: 11))
                .foregroundColor(content.isEmpty ? palette.timestamp : palette.normalText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private var networks: [String] {
        Array(Set(files.map(\.network))).sorted()
    }

    private func reload() {
        files = LogFile.scan(LogService.shared.directory)
        if let sel = selected, !files.contains(where: { $0.id == sel }) { selected = nil }
        loadSelected()
    }

    private func loadSelected() {
        guard let id = selected, let file = files.first(where: { $0.id == id }) else {
            content = ""; return
        }
        content = LogFile.read(file.url)
    }
}

/// One discovered log file.
struct LogFile: Identifiable, Hashable {
    let id: String   // path
    let network: String
    let target: String
    let url: URL

    /// Discover `<dir>/<network>/<target>.log` files.
    static func scan(_ dir: URL) -> [LogFile] {
        let fm = FileManager.default
        guard let nets = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [LogFile] = []
        for net in nets where (try? net.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let logs = (try? fm.contentsOfDirectory(at: net, includingPropertiesForKeys: nil)) ?? []
            for log in logs where log.pathExtension == "log" {
                out.append(LogFile(id: log.path,
                                   network: net.lastPathComponent,
                                   target: log.deletingPathExtension().lastPathComponent,
                                   url: log))
            }
        }
        return out.sorted { ($0.network, $0.target) < ($1.network, $1.target) }
    }

    /// Read a log, tailing the last ~256 KB so a huge transcript can't stall the UI.
    static func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let cap = 256 * 1024
        let slice = data.count > cap ? data.suffix(cap) : data
        let text = String(decoding: slice, as: UTF8.self)
        return data.count > cap ? "…(earlier lines truncated)…\n" + text : text
    }
}

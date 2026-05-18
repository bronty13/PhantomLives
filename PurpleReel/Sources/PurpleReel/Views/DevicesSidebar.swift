import SwiftUI
import AppKit

/// Devices section in the sidebar: enumerates mounted volumes
/// (`/` plus everything under `/Volumes/`), each expandable to walk
/// the live filesystem. Clicking a folder lets the user **Add to
/// Workspace** so it becomes a regular catalogued root.
struct DevicesSection: View {
    @EnvironmentObject var appState: AppState
    @State private var devices: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(devices, id: \.self) { device in
                DeviceRow(url: device, depth: 0)
                    .environmentObject(appState)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        // Enumerate user-visible volumes via `/Volumes/*`. Devices is
        // always-present and not affected by "Clear Workspace" — the
        // workspace owns user-added folder favourites; Devices is the
        // system's mounted-volume list (Macintosh HD + any externals).
        //
        // Use a Set to dedupe — macOS occasionally shows the boot
        // volume under multiple paths during APFS firmlink resolution
        // and we don't want it to render twice.
        var seen: Set<String> = []
        var found: [URL] = []
        if let vols = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for v in vols.sorted() where !v.hasPrefix(".") {
                let url = URL(fileURLWithPath: "/Volumes").appendingPathComponent(v)
                if seen.insert(v).inserted {
                    found.append(url)
                }
            }
        }
        if found.isEmpty { found = [URL(fileURLWithPath: "/")] }
        devices = found
    }
}

/// One device or filesystem folder row. Lazy-expandable: children are
/// loaded the first time the user clicks the chevron. Avoids walking
/// the whole filesystem up front.
private struct DeviceRow: View {
    let url: URL
    let depth: Int
    @EnvironmentObject var appState: AppState

    @State private var expanded: Bool = false
    @State private var children: [URL] = []
    @State private var didLoadChildren: Bool = false

    private var isVolumeRoot: Bool { depth == 0 }

    private var displayName: String {
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent
    }

    /// Path we send to AppState — boot-volume firmlinks resolve to `/`
    /// so that prefix matching against catalogued `/Users/…` paths
    /// actually works. External volumes pass through unchanged.
    private var canonicalPath: String {
        AppState.canonicalizeBootVolumePath(url.path)
    }

    private var isSelected: Bool { appState.selectedFolderPath == canonicalPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    if !didLoadChildren { loadChildren() }
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: isVolumeRoot ? "internaldrive" : "folder")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                    if appState.isDrilldownEnabled(forPath: canonicalPath) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .background(Circle().fill(.background))
                            .offset(x: 3, y: 3)
                    }
                }

                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.leading, 8 + CGFloat(depth) * 12)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(
                isSelected ? Color.accentColor.opacity(0.30) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Add to Workspace") {
                    if !appState.workspaceRoots.contains(url) {
                        appState.workspaceRoots.append(url)
                    }
                    appState.rootFolder = url
                    appState.selectedFolderPath = url.path
                    UserDefaults.standard.set(
                        appState.workspaceRoots.map(\.path),
                        forKey: "workspaceRoots"
                    )
                    Task { await appState.rescan() }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            // Single-click navigates to the folder (matches workspace
            // tree behavior); the chevron handles expand/collapse.
            .onTapGesture {
                appState.navigate(to: canonicalPath)
                if !didLoadChildren { loadChildren() }
            }

            if expanded {
                ForEach(children, id: \.self) { child in
                    DeviceRow(url: child, depth: depth + 1)
                        .environmentObject(appState)
                }
            }
        }
    }

    private func loadChildren() {
        didLoadChildren = true
        // Synchronous read on the main actor — listing a volume root
        // is ~1ms even for crowded `/Volumes` and the previous
        // Task.detached approach was racing the @State binding for
        // Macintosh HD (the View struct got recreated before the
        // detached task hopped back, so `self.children = dirs` landed
        // on a stale wrapper). Synchronous makes children appear
        // before `expanded` flips and is plenty fast for these reads.
        let fm = FileManager.default
        do {
            let raw = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let dirs = raw.filter { u in
                ((try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            }.sorted {
                $0.lastPathComponent
                    .localizedCaseInsensitiveCompare($1.lastPathComponent)
                    == .orderedAscending
            }
            self.children = dirs
        } catch {
            // Most likely cause when this fails for /Volumes/Macintosh HD:
            // Files & Folders TCC hasn't been granted. We log and
            // leave `children` empty; the chevron stays flipped so
            // the user sees nothing dropped down and can retry after
            // granting access.
            NSLog("[PurpleReel] DeviceRow loadChildren(\(url.path)) failed: \(error)")
        }
    }
}

/// Drilldown toggle pill used by both Workspace folder rows and Devices
/// rows. Reads like a tag/chip so it's obviously interactive — labelled
/// "drill" with an explicit on/off state instead of a tiny tray icon.
struct DrilldownToggleButton: View {
    @EnvironmentObject var appState: AppState
    let path: String

    private var on: Bool { appState.isDrilldownEnabled(forPath: path) }

    var body: some View {
        Button {
            appState.toggleDrilldown(forPath: path)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: on
                      ? "arrow.down.right.and.arrow.up.left.square.fill"
                      : "arrow.down.right.and.arrow.up.left.square")
                    .font(.system(size: 11))
                Text("drill")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(on ? Color.white : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(on ? Color.orange : Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .help(on
              ? "Drilldown ON — including all subfolders. Click to limit to direct children."
              : "Drilldown OFF — direct children only. Click to include subfolders.")
    }
}

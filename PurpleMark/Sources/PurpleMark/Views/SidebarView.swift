import SwiftUI

/// The segmented Outline | Files sidebar. Outline (default) is the live TOC of
/// the current document; Files browses the opened folder's markdown files.
struct SidebarView: View {
    @ObservedObject var doc: Document
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.sidebarTab) {
                Text("Outline").tag(SidebarTab.outline)
                Text("Files").tag(SidebarTab.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()

            switch state.sidebarTab {
            case .outline: OutlineList(doc: doc)
            case .files:   FileList()
            }
        }
    }
}

/// Live table-of-contents with colored heading-level badges.
private struct OutlineList: View {
    @ObservedObject var doc: Document

    /// Hard bound on rendered rows. A 100MB document can carry 50k+ headings —
    /// enough eagerly-built SwiftUI rows to abort in AttributeGraph. LazyVStack
    /// defers row creation; the cap bounds the bookkeeping too.
    private static let maxRows = 4_000

    var body: some View {
        let items = doc.outline
        if items.isEmpty {
            placeholder("No headings yet.\nAdd a # heading to build the outline.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items.prefix(Self.maxRows)) { item in
                        Button { jump(to: item) } label: {
                            HStack(spacing: 8) {
                                Text("H\(item.level)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(badgeColor(item.level))
                                    .frame(width: 22, alignment: .leading)
                                Text(item.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if items.count > Self.maxRows {
                        Text("Outline truncated — \(items.count) headings total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func jump(to item: OutlineItem) {
        // Fraction as the coarse fallback (e.g. preview chunk not rendered
        // yet); the exact jump follows for whichever view is showing.
        let totalLines = max(1, doc.stats.lines - 1)
        doc.scrollFraction = max(0, min(1, Double(item.line) / Double(totalLines)))
        let headingIndex = doc.outline.firstIndex(where: { $0 == item }) ?? 0
        doc.requestOutlineJump(line: item.line, headingIndex: headingIndex)
    }

    private func badgeColor(_ level: Int) -> Color {
        switch level {
        case 1:  return .blue
        case 2:  return Color(red: 0.85, green: 0.35, blue: 0.78)   // magenta
        case 3:  return .teal
        default: return .secondary
        }
    }
}

/// Folder browser of `.md` files.
private struct FileList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(state.folder?.lastPathComponent ?? "No folder")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button { state.openFolderDialog() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless)
                    .help("Open Folder…")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            if state.folderFiles.isEmpty {
                placeholderView("Open a folder to browse its Markdown files.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.folderFiles, id: \.self) { url in
                            Button { state.open(url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(isCurrent(url) ? Color.accentColor : .secondary)
                                    Text(url.lastPathComponent)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isCurrent(url) ? Color.accentColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func isCurrent(_ url: URL) -> Bool {
        state.active.fileURL?.standardizedFileURL == url.standardizedFileURL
    }
}

@ViewBuilder
private func placeholder(_ text: String) -> some View {
    VStack { Spacer(); placeholderView(text); Spacer() }
}

@ViewBuilder
private func placeholderView(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(20)
        .frame(maxWidth: .infinity)
}

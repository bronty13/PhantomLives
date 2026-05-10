import SwiftUI
import PurpleDedupCore

/// Side-by-side metadata table. Each row is one EXIF/codec attribute; cells
/// with values that disagree across the cluster get a subtle background tint
/// so the user's eye lands on the differences (FR-3.7 — visual diff
/// indicators). Path + Size always render at the top because directory
/// location is one of the most common deciding factors and they're useful
/// before EXIF extraction finishes.
struct MetadataDiffTable: View {
    let selection: ClusterSelection
    @ObservedObject var loader: MetadataLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Metadata").font(.headline)
                if loader.loading { ProgressView().controlSize(.small) }
                Spacer()
            }

            let allRows = loader.unifiedRowKeys(for: selection)
            // Horizontal scroll lets the per-file columns extend wider than
            // the pane for clusters with many members; vertical scrolling is
            // handled by the outer pane ScrollView so the table can grow
            // naturally without clipping.
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(selection.files, id: \.url) { f in
                            Text(f.url.lastPathComponent)
                                .font(.caption.bold())
                                .lineLimit(1).truncationMode(.middle)
                                .frame(minWidth: 200, alignment: .leading)
                        }
                    }
                    Divider().gridCellColumns(selection.files.count + 1)

                    // PATH — always at the top of the table because directory
                    // location is one of the most common deciding factors.
                    // Paths always differ across cluster members (otherwise
                    // they'd be the same file), so the orange diff highlight
                    // is permanent on this row.
                    GridRow {
                        Text("Path").font(.callout).foregroundStyle(.secondary)
                        ForEach(selection.files, id: \.url) { f in
                            Text(parentDirectoryDisplay(f.url))
                                .font(.callout.monospaced())
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .padding(.horizontal, 4)
                                .background(Color.orange.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .help(f.url.path)
                                .frame(minWidth: 200, alignment: .leading)
                        }
                    }

                    // SIZE — companion row for path. Always populated, often
                    // identical (exact dupes) but useful when comparing
                    // perceptual variants where one is a smaller re-encode.
                    GridRow {
                        Text("Size").font(.callout).foregroundStyle(.secondary)
                        ForEach(selection.files, id: \.url) { f in
                            let allSizes = selection.files.map(\.sizeBytes)
                            let sizesDiffer = !allSizes.allSatisfy { $0 == allSizes.first }
                            Text(formatBytes(f.sizeBytes))
                                .font(.callout.monospaced())
                                .padding(.horizontal, 4)
                                .background(sizesDiffer ? Color.orange.opacity(0.25) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    if allRows.isEmpty && !loader.loading {
                        GridRow {
                            Text("Metadata").font(.callout).foregroundStyle(.secondary)
                            Text("No EXIF or codec metadata available for these files.")
                                .font(.callout).foregroundStyle(.secondary)
                                .gridCellColumns(selection.files.count)
                        }
                    } else {
                        ForEach(allRows, id: \.self) { rowKey in
                            let valuesByURL = loader.valuesForRow(rowKey, in: selection)
                            let differs = valuesDiffer(valuesByURL.map { $0.value })
                            GridRow {
                                Text(loader.labelFor(rowKey))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                ForEach(selection.files, id: \.url) { f in
                                    Text(valuesByURL[f.url] ?? "—")
                                        .font(.callout.monospaced())
                                        .padding(.horizontal, 4)
                                        .background(differs ? Color.orange.opacity(0.25) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func valuesDiffer(_ values: [String]) -> Bool {
        guard let first = values.first else { return false }
        return values.contains { $0 != first }
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter(); bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }

    private func parentDirectoryDisplay(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if dir == home || dir.hasPrefix(home + "/") {
            return "~" + dir.dropFirst(home.count) + "/"
        }
        return dir + "/"
    }
}

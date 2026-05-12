import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MasterClipperCore

/// Single-screen browser for the `c4s_historical` table — a snapshot of
/// the most recent on-demand Clips4Sale storefront export per store.
/// Top toolbar: store filter + search + Import. Body: a sortable table
/// (left) and a detail panel (right) for the selected row.
struct C4SHistoricalView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rows: [C4SHistoricalRecord] = []
    @State private var storeFilter: String = ""              // "" / "CoC" / "PoA"
    @State private var search: String = ""
    @State private var selection: C4SHistoricalRecord.ID? = nil
    @State private var sortOrder: [KeyPathComparator<C4SHistoricalRecord>] = [
        KeyPathComparator(\C4SHistoricalRecord.title)
    ]

    @State private var showingImport: Bool = false
    @State private var showingBackfill: Bool = false
    @State private var statusMessage: String? = nil

    var body: some View {
        EdPageShell(
            eyebrow: "Section · C4S Historical",
            headline: "Clips4Sale snapshots.",
            emphasized: "snapshots",
            deck: "Imported storefront exports — read-only catalog of past activity.",
            trailing: AnyView(
                HStack(spacing: 8) {
                    Button { showingBackfill = true } label: { Text("BACKFILL CATEGORIES") }
                        .buttonStyle(EdGhostButtonStyle())
                        .disabled(rows.isEmpty)
                        .help(rows.isEmpty ? "Import a C4S export first"
                              : "Apply categories from the imported snapshot to production clips with no categories")
                    Button { showingImport = true } label: { Text("⌘ I · IMPORT") }
                        .buttonStyle(EdInkPillButtonStyle())
                        .keyboardShortcut("i", modifiers: [.command])
                        .help("Import a Clips4Sale storefront export (XLSX or pipe-CSV)")
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                header
                EdHairline(color: EdColor.ink(0.18))
                HSplitView {
                    table
                        .frame(minWidth: 520)
                    detail
                        .frame(minWidth: 320, idealWidth: 420)
                }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showingImport) {
            C4SHistoricalImportSheet(onComplete: { result in
                showingImport = false
                if let r = result {
                    statusMessage = "Imported \(r.count) row\(r.count == 1 ? "" : "s") into \(r.store)."
                    storeFilter = r.store
                    reload()
                }
            })
            .frame(minWidth: 520, minHeight: 320)
        }
        .sheet(isPresented: $showingBackfill) {
            HistoricalCategoryBackfillSheet(onComplete: { count in
                showingBackfill = false
                if let n = count {
                    statusMessage = "Backfilled categories on \(n) clip\(n == 1 ? "" : "s")."
                }
            })
        }
    }

    // MARK: - Header / toolbar

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $storeFilter) {
                Text("All (\(rows.count))").tag("")
                Text("CoC (\(rows.filter { $0.store == "CoC" }.count))").tag("CoC")
                Text("PoA (\(rows.filter { $0.store == "PoA" }.count))").tag("PoA")
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            TextField("Search title, description, keywords…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            Spacer()

            if let msg = statusMessage {
                Text(msg)
                    .font(EdFont.mono(10.5))
                    .foregroundStyle(EdColor.ink(0.7))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(EdColor.bone)
    }

    // MARK: - Table

    private var filteredRows: [C4SHistoricalRecord] {
        var result = rows
        if !storeFilter.isEmpty {
            result = result.filter { $0.store == storeFilter }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.descriptionText.lowercased().contains(q) ||
                $0.keywords.lowercased().contains(q) ||
                $0.categories.lowercased().contains(q) ||
                $0.clipId.lowercased().contains(q) ||
                $0.performers.lowercased().contains(q)
            }
        }
        return result.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(filteredRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Store", value: \C4SHistoricalRecord.store) { row in
                Text(row.store)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(storeColor(row.store).opacity(0.18), in: Capsule())
                    .foregroundStyle(storeColor(row.store))
            }
            .width(min: 50, ideal: 56)

            TableColumn("Title", value: \C4SHistoricalRecord.title) { row in
                Text(row.title.isEmpty ? "—" : row.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(row.title)
            }
            .width(min: 220, ideal: 380)

            TableColumn("Status", value: \C4SHistoricalRecord.clipStatus) { row in
                Text(row.clipStatus.isEmpty ? "—" : row.clipStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)

            TableColumn("C4S ID", value: \C4SHistoricalRecord.clipId) { row in
                Text(row.clipId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .width(min: 84, ideal: 96)

            TableColumn("Price", value: \C4SHistoricalRecord.priceCents,
                         comparator: OptionalIntComparator()) { row in
                Text(row.priceDisplay.isEmpty ? "—" : row.priceDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.priceCents == nil ? .tertiary : .primary)
            }
            .width(min: 60, ideal: 70)

            TableColumn("Sales", value: \C4SHistoricalRecord.salesCount,
                         comparator: OptionalIntComparator()) { row in
                Text(row.salesDisplay.isEmpty ? "—" : row.salesDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.salesCount == nil ? .tertiary : .primary)
            }
            .width(min: 56, ideal: 64)

            TableColumn("Income (6mo)", value: \C4SHistoricalRecord.incomeCents,
                         comparator: OptionalIntComparator()) { row in
                Text(row.incomeDisplay.isEmpty ? "—" : row.incomeDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.incomeCents == nil ? .tertiary : .primary)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Categories", value: \C4SHistoricalRecord.categories) { row in
                Text(row.categories.isEmpty ? "—" : row.categories)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(row.categories)
            }
            .width(min: 160, ideal: 220)
        }
        .tableStyle(.inset)
    }

    // MARK: - Detail panel

    private var detail: some View {
        Group {
            if let id = selection, let row = rows.first(where: { $0.id == id }) {
                detailBody(row)
            } else {
                emptyDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailBody(_ row: C4SHistoricalRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(row.store)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(storeColor(row.store).opacity(0.2), in: Capsule())
                        .foregroundStyle(storeColor(row.store))
                    Text("C4S #\(row.clipId)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Text(row.clipStatus)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                metricsRow(row)

                if !row.descriptionText.isEmpty {
                    detailSection("Description") {
                        Text(row.descriptionText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !row.categories.isEmpty {
                    detailSection("Categories") {
                        WrapChips(items: row.categoryList, color: .accentColor.opacity(0.18))
                    }
                }

                if !row.keywords.isEmpty {
                    detailSection("Keywords") {
                        WrapChips(items: row.keywordList, color: .gray.opacity(0.18))
                    }
                }

                if !row.performers.isEmpty {
                    detailSection("Performers") {
                        Text(row.performers).textSelection(.enabled)
                    }
                }

                detailSection("Files") {
                    fileRow(label: "Clip",      value: row.clipFilename)
                    fileRow(label: "Thumbnail", value: row.thumbnailFilename)
                    fileRow(label: "Preview",   value: row.previewFilename)
                }

                if !row.trackingTag.isEmpty {
                    detailSection("Tracking tag") {
                        Text(row.trackingTag)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Text("Imported \(row.importedAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a clip to see its details")
                .font(.callout)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Button {
                    showingImport = true
                } label: {
                    Label("Import a C4S export…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricsRow(_ row: C4SHistoricalRecord) -> some View {
        HStack(spacing: 18) {
            metricCell("Price",         row.priceDisplay.isEmpty ? "—" : row.priceDisplay)
            metricCell("Sales",         row.salesDisplay.isEmpty ? "—" : row.salesDisplay)
            metricCell("Income (6mo)",  row.incomeDisplay.isEmpty ? "—" : row.incomeDisplay)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func fileRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
        }
    }

    // MARK: - Helpers

    private func reload() {
        do {
            rows = try DatabaseService.shared.fetchC4SHistorical()
        } catch {
            statusMessage = "Failed to load: \(error.localizedDescription)"
            rows = []
        }
    }

    private func storeColor(_ store: String) -> Color {
        if let p = appState.persona(forCode: store), let c = Color(hex: p.colorHex) {
            return c
        }
        return .accentColor
    }
}

// MARK: - Optional<Int> comparator

/// SwiftUI's `KeyPathComparator(value:)` can't sort `Int?` directly; this
/// just sorts nils last. Reused by the price / sales / income columns.
struct OptionalIntComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ a: Int?, _ b: Int?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _):   return order == .forward ? .orderedDescending : .orderedAscending
        case (_, nil):   return order == .forward ? .orderedAscending  : .orderedDescending
        case let (l?, r?):
            if l == r { return .orderedSame }
            let asc: ComparisonResult = (l < r) ? .orderedAscending : .orderedDescending
            return order == .forward ? asc : (asc == .orderedAscending ? .orderedDescending : .orderedAscending)
        }
    }
}

// MARK: - Wrapping chip row

/// Horizontal flow of pill-style chips. Used for categories / keywords
/// in the detail panel; small enough that it doesn't need to be its own
/// shared file.
private struct WrapChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color, in: Capsule())
                    .foregroundStyle(.primary)
            }
        }
    }
}

// FlowLayout is defined in `Views/Clips/CategoryChipPicker.swift` and
// re-used here for category / keyword chips.

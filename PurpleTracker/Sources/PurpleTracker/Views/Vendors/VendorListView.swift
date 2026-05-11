import SwiftUI
import AppKit

/// Master list of Third Parties (vendors). Lives in the content column when
/// the sidebar `.thirdPartiesAll` section is active.
struct VendorListView: View {
    @EnvironmentObject var app: AppState
    @State private var search: String = ""

    private var filtered: [Vendor] {
        let q = search.lowercased()
        guard !q.isEmpty else { return app.vendors }
        return app.vendors.filter {
            $0.name.lowercased().contains(q) ||
            $0.resellerDisplay.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search vendors", text: $search)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button { addVendor() } label: {
                    Label("New Vendor", systemImage: "plus")
                }
                Menu {
                    Button("Export Basic (Markdown)…")    { exportAll(detailed: false, format: .markdown) }
                    Button("Export Detailed (Markdown)…") { exportAll(detailed: true,  format: .markdown) }
                    Divider()
                    Button("Export Basic (PDF)…")    { exportAll(detailed: false, format: .pdf) }
                    Button("Export Detailed (PDF)…") { exportAll(detailed: true,  format: .pdf) }
                } label: { Label("All-Vendors Report", systemImage: "square.and.arrow.up") }
            }
            .padding(8)
            Divider()
            List(selection: Binding(
                get: { app.selectedVendorId },
                set: { app.selectVendor(id: $0) }
            )) {
                ForEach(filtered) { v in
                    VendorRow(vendor: v)
                        .tag(v.id as String?)
                        .contextMenu {
                            Button("Open") { app.selectVendor(id: v.id) }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                try? app.softDeleteVendor(id: v.id)
                            }
                        }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Third Parties")
    }

    private func addVendor() {
        do {
            _ = try app.createVendor()
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }

    private func exportAll(detailed: Bool, format: VendorReportService.Format) {
        do {
            let url = try VendorReportService.exportAllVendors(
                detailed: detailed, format: format,
                vendors: app.vendors,
                settingsStore: app.settingsStore,
                yearRange: app.thirdPartyYearRange
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

private struct VendorRow: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor

    var body: some View {
        let firstYear = app.thirdPartyYearRange.first ?? Calendar.current.component(.year, from: Date())
        let budget = (try? VendorService.fetchYearAmounts(vendorId: vendor.id))?
            .first(where: { $0.year == firstYear })?.budgetCents
        let productsCount = (try? VendorService.fetchProducts(vendorId: vendor.id).count) ?? 0
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(vendor.name.isEmpty ? "(unnamed)" : vendor.name)
                    .font(.headline)
                Spacer()
                if let r = vendor.rating {
                    StarsView(rating: r, size: 11)
                }
            }
            HStack(spacing: 8) {
                Text(vendor.resellerDisplay)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                Text("\(productsCount) product\(productsCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if let b = budget {
                    Text("\(firstYear): \(Money.format(cents: b))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

/// 1..5 star control. Read-only when `onTap` is nil; clickable otherwise.
/// `rating = 0` renders all hollow; tapping a filled star clears it.
struct StarsView: View {
    let rating: Int
    var size: CGFloat = 14
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        if let onTap {
                            onTap(rating == i ? 0 : i)
                        }
                    }
            }
        }
    }
}

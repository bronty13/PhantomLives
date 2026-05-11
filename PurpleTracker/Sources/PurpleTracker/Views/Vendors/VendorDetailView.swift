import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Full tabbed editor for a single Third Party. Big, but kept in one file so
/// the per-tab subviews share the `vendor` + AppState plumbing.
struct VendorDetailView: View {
    let vendor: Vendor
    @EnvironmentObject var app: AppState

    @State private var tab: VTab = .overview

    enum VTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case contacts = "Contacts"
        case products = "Products"
        case budget   = "Budget & Actuals"
        case contracts = "Contracts"
        case invoices = "Invoices"
        case other    = "Other Files"
        case contractSummary = "Contract Summary"
        case costingSummary  = "Costing Summary"
        case exitStrategy    = "Exit Strategy"
        case notes    = "Notes"
        case linked   = "Linked Matters"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()
                .background(Color.accentColor.opacity(0.08))
            Divider()
            VendorTabBar(tabs: VTab.allCases, selection: $tab) { t in t.rawValue }
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .overview:        VendorOverviewTab(vendor: vendor)
                    case .contacts:        VendorContactsTab(vendor: vendor)
                    case .products:        VendorProductsTab(vendor: vendor)
                    case .budget:          VendorBudgetTab(vendor: vendor)
                    case .contracts:       VendorAttachmentListTab(vendor: vendor, kind: .contract,
                                                                   title: "Contracts")
                    case .invoices:        VendorInvoicesTab(vendor: vendor)
                    case .other:           VendorAttachmentListTab(vendor: vendor, kind: .other,
                                                                   title: "Other Files")
                    case .contractSummary: VendorMarkdownTab(
                                                vendor: vendor,
                                                label: "Contract Summary",
                                                getter: \.contractSummaryMd,
                                                setter: { v, s in var x = v; x.contractSummaryMd = s; return x })
                    case .costingSummary:  VendorMarkdownTab(
                                                vendor: vendor,
                                                label: "Costing Summary",
                                                getter: \.costingSummaryMd,
                                                setter: { v, s in var x = v; x.costingSummaryMd = s; return x })
                    case .exitStrategy:    VendorMarkdownTab(
                                                vendor: vendor,
                                                label: "Exit Strategy",
                                                getter: \.exitStrategyMd,
                                                setter: { v, s in var x = v; x.exitStrategyMd = s; return x })
                    case .notes:           VendorNotesTab(vendor: vendor)
                    case .linked:          VendorLinkedMattersTab(vendor: vendor)
                    }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Summary (Markdown)…")  { exportSingle(detailed: false, format: .markdown) }
                    Button("Full (Markdown)…")     { exportSingle(detailed: true,  format: .markdown) }
                    Divider()
                    Button("Summary (PDF)…")       { exportSingle(detailed: false, format: .pdf) }
                    Button("Full (PDF)…")          { exportSingle(detailed: true,  format: .pdf) }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                TextField("Vendor name", text: bindingName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2.weight(.semibold))
                Spacer()
                StarsView(rating: vendor.rating ?? 0, size: 18, onTap: { newRating in
                    var v = vendor
                    v.rating = newRating == 0 ? nil : newRating
                    try? app.updateVendor(v)
                })
            }
            HStack(spacing: 8) {
                if !vendor.resellerDisplay.isEmpty {
                    Text("Reseller: \(vendor.resellerDisplay)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !vendor.website.isEmpty,
                   let url = URL(string: VendorOverviewTab.normalizeURL(vendor.website)) {
                    Link(destination: url) {
                        Label(vendor.website, systemImage: "link")
                            .font(.caption)
                    }
                }
                if !vendor.phone.isEmpty {
                    Label(vendor.phone, systemImage: "phone")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var bindingName: Binding<String> {
        Binding(
            get: { vendor.name },
            set: { newValue in
                var v = vendor; v.name = newValue
                try? app.updateVendor(v)
            }
        )
    }

    private func exportSingle(detailed: Bool, format: VendorReportService.Format) {
        do {
            let url = try VendorReportService.exportVendor(
                vendor, detailed: detailed, format: format,
                settingsStore: app.settingsStore,
                yearRange: app.thirdPartyYearRange
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Overview tab

struct VendorOverviewTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                row("Address",       bind(\.address))
                row("Website",       bind(\.website),     placeholder: "https://…")
                row("Phone",         bind(\.phone))
                row("Data Center",   bind(\.dataCenter))
                row("Budget Code",   bind(\.budgetCode),  placeholder: "SEC# / cost-center")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Reseller").frame(width: 110, alignment: .trailing).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { vendor.reseller },
                    set: { newValue in
                        var v = vendor; v.reseller = newValue
                        try? app.updateVendor(v)
                    }
                )) {
                    Text("None").tag("")
                    ForEach(Reseller.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if vendor.reseller == Reseller.other.rawValue {
                    TextField("Other reseller", text: bind(\.resellerOther))
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Rating Note").frame(width: 110, alignment: .trailing).foregroundStyle(.secondary)
                TextField("Why this rating?", text: bind(\.ratingNote))
                    .textFieldStyle(.roundedBorder)
            }
            Divider().padding(.vertical, 6)
            Text("Description").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: bind(\.descriptionMd))
                .frame(minHeight: 160)
                .border(Color.secondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ binding: Binding<String>, placeholder: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).frame(width: 110, alignment: .trailing).foregroundStyle(.secondary)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Type-safe binding into a writable string field on the vendor.
    private func bind(_ kp: WritableKeyPath<Vendor, String>) -> Binding<String> {
        Binding(
            get: { vendor[keyPath: kp] },
            set: { newValue in
                var v = vendor; v[keyPath: kp] = newValue
                try? app.updateVendor(v)
            }
        )
    }

    /// Best-effort URL normaliser: prepend `https://` if no scheme is present.
    static func normalizeURL(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("://") { return t }
        return "https://\(t)"
    }
}

// MARK: - Contacts tab

struct VendorContactsTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(VendorContactKind.allCases) { kind in
                contactCard(kind: kind)
            }
        }
    }

    private func contactCard(kind: VendorContactKind) -> some View {
        let contact = app.vendorContacts.first(where: { $0.kind == kind.rawValue })
            ?? VendorContact.empty(vendorId: vendor.id, kind: kind)
        return VStack(alignment: .leading, spacing: 6) {
            Text(kind.displayName).font(.headline)
            field("Name",   text: bind(contact, \.name))
            field("Phone",  text: bind(contact, \.phone))
            field("Mobile", text: bind(contact, \.mobile))
            field("Email",  text: bind(contact, \.email))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func bind(_ contact: VendorContact, _ kp: WritableKeyPath<VendorContact, String>) -> Binding<String> {
        Binding(
            get: { contact[keyPath: kp] },
            set: { newValue in
                var c = contact; c[keyPath: kp] = newValue
                try? app.upsertVendorContact(c)
            }
        )
    }
}

// MARK: - Products tab

struct VendorProductsTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Products").font(.headline)
                Spacer()
                Button { addProduct() } label: { Label("Add", systemImage: "plus") }
            }
            ForEach(app.vendorProducts) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Product name", text: bind(p, \.name))
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            try? app.deleteVendorProduct(id: p.id)
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    TextField("Notes", text: bind(p, \.notes))
                        .textFieldStyle(.roundedBorder)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
            if app.vendorProducts.isEmpty {
                Text("No products yet.").foregroundStyle(.secondary)
            }
        }
    }

    private func addProduct() {
        let p = VendorProduct(id: UUID().uuidString, vendorId: vendor.id,
                              sortOrder: app.vendorProducts.count, name: "", notes: "")
        try? app.upsertVendorProduct(p)
    }

    private func bind(_ p: VendorProduct, _ kp: WritableKeyPath<VendorProduct, String>) -> Binding<String> {
        Binding(
            get: { p[keyPath: kp] },
            set: { newValue in
                var x = p; x[keyPath: kp] = newValue
                try? app.upsertVendorProduct(x)
            }
        )
    }
}

// MARK: - Budget & Actuals tab

struct VendorBudgetTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor

    var body: some View {
        let years = app.thirdPartyYearRange
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget & Actuals")
                .font(.headline)
            Text("Year range is set in Settings → Third Parties. **Effective Actual** = manual override if present, otherwise the sum of invoices in that year. **Variance** = Budget − Effective Actual (positive = under budget). **Y/Y %** compares to the prior year in the matrix.")
                .font(.caption).foregroundStyle(.secondary)
            // Header row.
            HStack {
                Text("Year").frame(width: 60, alignment: .leading)
                Text("Budget").frame(width: 130, alignment: .leading)
                Text("Bud Y/Y").frame(width: 70, alignment: .trailing)
                Text("Actual (override)").frame(width: 150, alignment: .leading)
                Text("Effective Actual").frame(width: 130, alignment: .leading)
                Text("Act Y/Y").frame(width: 70, alignment: .trailing)
                Text("Variance").frame(width: 130, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(Array(years.enumerated()), id: \.element) { idx, year in
                let priorYear: Int? = idx > 0 ? years[idx - 1] : nil
                BudgetRow(
                    vendor: vendor,
                    year: year,
                    priorBudgetCents: priorYear.flatMap { y in
                        app.vendorYearAmounts.first(where: { $0.year == y })?.budgetCents
                    },
                    priorActualCents: priorYear.flatMap { app.vendorEffectiveActuals[$0] }
                )
            }
        }
    }
}

private struct BudgetRow: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    let year: Int
    let priorBudgetCents: Int64?
    let priorActualCents: Int64?
    @State private var budgetText: String = ""
    @State private var overrideText: String = ""

    var body: some View {
        let existing = app.vendorYearAmounts.first(where: { $0.year == year })
        let budget = existing?.budgetCents ?? 0
        let effective = app.vendorEffectiveActuals[year] ?? 0
        let variance = budget - effective
        HStack(alignment: .center) {
            Text(verbatim: "\(year)").frame(width: 60, alignment: .leading)
            TextField("$0.00", text: $budgetText, onCommit: commitBudget)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Text(BudgetMath.yoyDisplay(current: budget, prior: priorBudgetCents))
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(BudgetMath.yoyColor(current: budget, prior: priorBudgetCents))
                .font(.callout.monospacedDigit())
            TextField("auto", text: $overrideText, onCommit: commitOverride)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            Text(Money.format(cents: effective))
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(existing?.actualOverrideCents != nil ? .primary : .secondary)
            Text(BudgetMath.yoyDisplay(current: effective, prior: priorActualCents))
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(BudgetMath.yoyColor(current: effective, prior: priorActualCents))
                .font(.callout.monospacedDigit())
            Text(BudgetMath.varianceDisplay(cents: variance))
                .frame(width: 130, alignment: .trailing)
                .foregroundStyle(variance >= 0 ? Color.green : Color.red)
                .font(.callout.monospacedDigit())
        }
        .onAppear { syncFromStore() }
        .onChange(of: vendor.id) { _, _ in syncFromStore() }
        .onChange(of: existing?.budgetCents) { _, _ in syncFromStore() }
        .onChange(of: existing?.actualOverrideCents) { _, _ in syncFromStore() }
    }

    private func syncFromStore() {
        if let e = app.vendorYearAmounts.first(where: { $0.year == year }) {
            budgetText = Money.format(cents: e.budgetCents)
            overrideText = e.actualOverrideCents.map { Money.format(cents: $0) } ?? ""
        } else {
            budgetText = ""
            overrideText = ""
        }
    }

    private func commitBudget() {
        let cents = Money.parse(budgetText) ?? 0
        var existing = app.vendorYearAmounts.first(where: { $0.year == year })
            ?? VendorYearAmount(vendorId: vendor.id, year: year, budgetCents: 0, actualOverrideCents: nil)
        existing.budgetCents = cents
        try? app.upsertVendorYearAmount(existing)
        budgetText = Money.format(cents: cents)
    }

    private func commitOverride() {
        let trimmed = overrideText.trimmingCharacters(in: .whitespaces)
        var existing = app.vendorYearAmounts.first(where: { $0.year == year })
            ?? VendorYearAmount(vendorId: vendor.id, year: year, budgetCents: 0, actualOverrideCents: nil)
        if trimmed.isEmpty {
            existing.actualOverrideCents = nil
            overrideText = ""
        } else {
            let cents = Money.parse(trimmed) ?? 0
            existing.actualOverrideCents = cents
            overrideText = Money.format(cents: cents)
        }
        try? app.upsertVendorYearAmount(existing)
    }
}

// MARK: - Attachment list tab (contracts / other)

struct VendorAttachmentListTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    let kind: VendorAttachmentKind
    let title: String
    @State private var attachments: [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool, kind: String, parentId: String?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { addFile() } label: { Label("Add", systemImage: "paperclip") }
            }
            if attachments.isEmpty {
                Text("No files yet.").foregroundStyle(.secondary)
            } else {
                ForEach(attachments, id: \.id) { a in
                    HStack {
                        Image(systemName: a.lastVerifyOk ? "doc.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(a.lastVerifyOk ? .blue : .red)
                        Text(a.filename)
                        Spacer()
                        Text(byteString(a.sizeBytes)).font(.caption).foregroundStyle(.secondary)
                        Button("Open") { open(a.id) }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            try? app.deleteVendorAttachment(id: a.id)
                            reload()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: app.selectedVendorId) { _, _ in reload() }
    }

    private func reload() {
        attachments = (try? VendorService.fetchAttachmentsMetadata(
            vendorId: vendor.id, kind: kind)) ?? []
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try app.addVendorAttachment(vendorId: vendor.id, fileURL: url, kind: kind)
                reload()
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ id: String) {
        do {
            let result = try app.openVendorAttachment(id: id)
            NSWorkspace.shared.open(result.url)
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

// MARK: - Invoices tab

struct VendorInvoicesTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Invoices").font(.headline)
                Spacer()
                Button { showAdd = true } label: { Label("Add Invoice", systemImage: "plus") }
            }
            Text("Backdating is allowed — the year is taken from the invoice date and used to roll up actuals.")
                .font(.caption).foregroundStyle(.secondary)
            if app.vendorInvoices.isEmpty {
                Text("No invoices yet.").foregroundStyle(.secondary)
            }
            ForEach(app.vendorInvoices) { inv in
                InvoiceRow(invoice: inv)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddInvoiceSheet(vendor: vendor, isPresented: $showAdd)
        }
    }
}

private struct InvoiceRow: View {
    @EnvironmentObject var app: AppState
    let invoice: VendorInvoice
    @State private var files: [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool, kind: String, parentId: String?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(invoice.invoiceDate.formatted(date: .abbreviated, time: .omitted))
                    .frame(width: 110, alignment: .leading)
                Text("#\(invoice.vendorInvoiceNumber.isEmpty ? "—" : invoice.vendorInvoiceNumber)")
                    .frame(width: 140, alignment: .leading)
                    .font(.caption).foregroundStyle(.secondary)
                Text(Money.format(cents: invoice.amountCents))
                    .frame(width: 110, alignment: .trailing)
                    .monospacedDigit()
                Text(invoice.memo).foregroundStyle(.secondary)
                Spacer()
                if let first = files.first {
                    Button("Open File") { openFile(first.id) }
                        .buttonStyle(.borderless)
                }
                Button(role: .destructive) {
                    try? app.deleteVendorInvoice(id: invoice.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            files = (try? VendorService.fetchAttachmentsMetadata(
                vendorId: invoice.vendorId, kind: .invoice, parentId: invoice.id)) ?? []
        }
    }

    private func openFile(_ id: String) {
        do {
            let r = try app.openVendorAttachment(id: id)
            NSWorkspace.shared.open(r.url)
        } catch { app.errorMessage = error.localizedDescription }
    }
}

private struct AddInvoiceSheet: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    @Binding var isPresented: Bool
    @State private var date: Date = Date()
    @State private var amountText: String = ""
    @State private var number: String = ""
    @State private var memo: String = ""
    @State private var fileURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Invoice").font(.title3.weight(.semibold))
            DatePicker("Invoice Date", selection: $date, displayedComponents: .date)
            HStack {
                Text("Amount").frame(width: 90, alignment: .leading)
                TextField("$0.00", text: $amountText).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Number").frame(width: 90, alignment: .leading)
                TextField("Vendor invoice #", text: $number).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Memo").frame(width: 90, alignment: .leading)
                TextField("", text: $memo).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("File").frame(width: 90, alignment: .leading)
                Text(fileURL?.lastPathComponent ?? "—").foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.allowsMultipleSelection = false
                    p.canChooseDirectories = false
                    if p.runModal() == .OK { fileURL = p.url }
                }
            }
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Add") {
                    do {
                        _ = try app.addVendorInvoice(
                            vendorId: vendor.id,
                            date: date,
                            amountCents: Money.parse(amountText) ?? 0,
                            vendorInvoiceNumber: number,
                            memo: memo,
                            fileURL: fileURL
                        )
                        isPresented = false
                    } catch {
                        app.errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Money.parse(amountText) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Markdown summary tabs

struct VendorMarkdownTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    let label: String
    let getter: KeyPath<Vendor, String>
    let setter: (Vendor, String) -> Vendor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            TextEditor(text: Binding(
                get: { vendor[keyPath: getter] },
                set: { newValue in
                    let updated = setter(vendor, newValue)
                    try? app.updateVendor(updated)
                }
            ))
            .frame(minHeight: 300)
            .border(Color.secondary.opacity(0.2))
        }
    }
}

// MARK: - Notes tab

struct VendorNotesTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.headline)
            HStack(alignment: .top) {
                TextEditor(text: $draft)
                    .frame(minHeight: 60)
                    .border(Color.secondary.opacity(0.2))
                VStack {
                    Button("Add") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        _ = try? app.addVendorNote(vendorId: vendor.id, body: trimmed)
                        draft = ""
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Spacer()
                }
            }
            Divider()
            ForEach(app.vendorNotes) { n in
                VendorNoteRow(note: n)
            }
        }
    }
}

private struct VendorNoteRow: View {
    @EnvironmentObject var app: AppState
    let note: VendorNote
    @State private var editing = false
    @State private var body_: String = ""
    @State private var files: [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool, kind: String, parentId: String?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if note.updatedAt > note.createdAt {
                    Text("(edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(editing ? "Save" : "Edit") {
                    if editing {
                        var x = note; x.bodyMd = body_
                        try? app.updateVendorNote(x)
                    } else {
                        body_ = note.bodyMd
                    }
                    editing.toggle()
                }.buttonStyle(.borderless)
                Button("Attach") { attachFile() }.buttonStyle(.borderless)
                Button(role: .destructive) {
                    try? app.deleteVendorNote(id: note.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            if editing {
                TextEditor(text: $body_)
                    .frame(minHeight: 80)
                    .border(Color.secondary.opacity(0.2))
            } else {
                Text(note.bodyMd).fixedSize(horizontal: false, vertical: true)
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files, id: \.id) { f in
                        Button {
                            if let r = try? app.openVendorAttachment(id: f.id) {
                                NSWorkspace.shared.open(r.url)
                            }
                        } label: {
                            Label(f.filename, systemImage: "paperclip")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .onAppear(perform: reloadFiles)
    }

    private func reloadFiles() {
        files = (try? VendorService.fetchAttachmentsMetadata(
            vendorId: note.vendorId, kind: .note, parentId: note.id)) ?? []
    }

    private func attachFile() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        if p.runModal() == .OK, let url = p.url {
            _ = try? app.addVendorAttachment(
                vendorId: note.vendorId, fileURL: url, kind: .note, parentId: note.id
            )
            reloadFiles()
        }
    }
}

// MARK: - Linked Matters tab

struct VendorLinkedMattersTab: View {
    @EnvironmentObject var app: AppState
    let vendor: Vendor
    @State private var matters: [Matter] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Matters").font(.headline)
            if matters.isEmpty {
                Text("No Matters reference this vendor yet. Set the Vendor on a Matter to link it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(matters) { m in
                HStack {
                    Text(m.id).font(.system(.body, design: .monospaced))
                    Text(m.title.isEmpty ? "(untitled)" : m.title)
                    Spacer()
                    Text(m.status).font(.caption).foregroundStyle(.secondary)
                    Button("Open") {
                        app.sidebarSection = .all
                        app.selectMatter(id: m.id)
                    }.buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear { matters = (try? VendorService.fetchLinkedMatters(vendorId: vendor.id)) ?? [] }
        .onChange(of: app.selectedVendorId) { _, _ in
            matters = (try? VendorService.fetchLinkedMatters(vendorId: vendor.id)) ?? []
        }
    }
}

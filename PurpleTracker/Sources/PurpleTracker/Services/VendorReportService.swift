import Foundation
import AppKit

/// Renders Third Party (vendor) reports. v1 supports Markdown and PDF (PDF
/// goes through the same `NSPrintOperation`-on-`NSAttributedString` path
/// used by `ExportService` for Matter exports). HTML and DOCX are deferred
/// to a follow-up release per the user spec.
@MainActor
enum VendorReportService {

    enum Format: String, CaseIterable, Identifiable {
        case markdown, pdf
        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .pdf:      return "pdf"
            }
        }
        var displayName: String {
            switch self {
            case .markdown: return "Markdown (.md)"
            case .pdf:      return "PDF (.pdf)"
            }
        }
    }

    // MARK: - Single vendor

    /// `detailed = false` → summary card (demographics + headline numbers).
    /// `detailed = true`  → everything: contacts, products, full budget matrix,
    ///                       invoices, summaries, notes, linked matters.
    static func renderMarkdown(vendor: Vendor, detailed: Bool, yearRange: [Int]) -> String {
        var out = ""
        out += "# \(vendor.name.isEmpty ? "(unnamed vendor)" : vendor.name)\n\n"
        out += "**Reseller:** \(vendor.resellerDisplay)  \n"
        if let r = vendor.rating { out += "**Rating:** \(stars(r)) (\(r)/5)  \n" }
        if !vendor.ratingNote.isEmpty { out += "**Rating note:** \(vendor.ratingNote)  \n" }
        if !vendor.address.isEmpty    { out += "**Address:** \(vendor.address)  \n" }
        if !vendor.website.isEmpty    { out += "**Website:** \(vendor.website)  \n" }
        if !vendor.phone.isEmpty      { out += "**Phone:** \(vendor.phone)  \n" }
        if !vendor.dataCenter.isEmpty { out += "**Data Center:** \(vendor.dataCenter)  \n" }
        if !vendor.budgetCode.isEmpty { out += "**Budget Code (SEC#):** \(vendor.budgetCode)  \n" }

        let products = (try? VendorService.fetchProducts(vendorId: vendor.id)) ?? []
        if !products.isEmpty {
            out += "\n## Products\n\n"
            for p in products {
                out += "- **\(p.name)**" + (p.notes.isEmpty ? "" : " — \(p.notes)") + "\n"
            }
        }

        // Year matrix is part of both summary and detailed.
        out += "\n## Budget & Actuals\n\n"
        let amounts = (try? VendorService.fetchYearAmounts(vendorId: vendor.id)) ?? []
        let actuals = (try? VendorInvoiceService.effectiveActuals(vendorId: vendor.id, years: yearRange)) ?? [:]
        out += "| Year | Budget | Actual (effective) |\n"
        out += "|------|--------|--------------------|\n"
        for y in yearRange {
            let budget = amounts.first(where: { $0.year == y })?.budgetCents ?? 0
            let actual = actuals[y] ?? 0
            out += "| \(y) | \(Money.format(cents: budget)) | \(Money.format(cents: actual)) |\n"
        }

        if !detailed { return out }

        // Detailed sections beyond this point.

        let contacts = (try? VendorService.fetchContacts(vendorId: vendor.id)) ?? []
        if !contacts.isEmpty {
            out += "\n## Contacts\n\n"
            for kind in VendorContactKind.allCases {
                if let c = contacts.first(where: { $0.kind == kind.rawValue }),
                   !c.name.isEmpty || !c.email.isEmpty || !c.phone.isEmpty || !c.mobile.isEmpty {
                    out += "### \(kind.displayName)\n"
                    if !c.name.isEmpty   { out += "- Name: \(c.name)\n" }
                    if !c.phone.isEmpty  { out += "- Phone: \(c.phone)\n" }
                    if !c.mobile.isEmpty { out += "- Mobile: \(c.mobile)\n" }
                    if !c.email.isEmpty  { out += "- Email: \(c.email)\n" }
                    out += "\n"
                }
            }
        }

        if !vendor.descriptionMd.isEmpty {
            out += "\n## Description\n\n\(vendor.descriptionMd)\n"
        }
        if !vendor.contractSummaryMd.isEmpty {
            out += "\n## Contract Summary\n\n\(vendor.contractSummaryMd)\n"
        }
        if !vendor.costingSummaryMd.isEmpty {
            out += "\n## Costing Summary\n\n\(vendor.costingSummaryMd)\n"
        }
        if !vendor.exitStrategyMd.isEmpty {
            out += "\n## Exit Strategy\n\n\(vendor.exitStrategyMd)\n"
        }

        let invoices = (try? VendorInvoiceService.fetchInvoices(vendorId: vendor.id)) ?? []
        if !invoices.isEmpty {
            out += "\n## Invoices\n\n"
            out += "| Date | Number | Amount | Memo |\n"
            out += "|------|--------|--------|------|\n"
            for i in invoices {
                let date = i.invoiceDate.formatted(date: .abbreviated, time: .omitted)
                out += "| \(date) | \(i.vendorInvoiceNumber) | \(Money.format(cents: i.amountCents)) | \(i.memo) |\n"
            }
        }

        let notes = (try? VendorService.fetchNotes(vendorId: vendor.id)) ?? []
        if !notes.isEmpty {
            out += "\n## Notes\n\n"
            for n in notes {
                out += "### \(n.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
                out += "\(n.bodyMd)\n\n"
            }
        }

        let linked = (try? VendorService.fetchLinkedMatters(vendorId: vendor.id)) ?? []
        if !linked.isEmpty {
            out += "\n## Linked Matters\n\n"
            for m in linked {
                out += "- `\(m.id)` — \(m.title) — \(m.status)\n"
            }
        }

        return out
    }

    /// Plain summary table for the "Basic" all-vendors report.
    static func renderAllVendorsBasic(_ vendors: [Vendor], yearRange: [Int]) -> String {
        var out = "# Third Parties — Basic Report\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        out += "_Generated \(df.string(from: Date()))_\n\n"
        out += "| Vendor | Reseller | Rating | Products | Sales Contact | Phone |\n"
        out += "|--------|----------|--------|----------|---------------|-------|\n"
        for v in vendors {
            let contacts = (try? VendorService.fetchContacts(vendorId: v.id)) ?? []
            let sales = contacts.first(where: { $0.kind == VendorContactKind.sales.rawValue })
            let products = (try? VendorService.fetchProducts(vendorId: v.id).count) ?? 0
            out += "| \(v.name) | \(v.resellerDisplay) | "
            out += (v.rating.map { "\($0)/5" } ?? "—") + " | \(products) | "
            out += "\(sales?.name ?? "—") | \(sales?.phone ?? "—") |\n"
        }
        return out
    }

    /// Detailed all-vendors: concatenated single-vendor full reports.
    static func renderAllVendorsDetailed(_ vendors: [Vendor], yearRange: [Int]) -> String {
        var out = "# Third Parties — Detailed Report\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        out += "_Generated \(df.string(from: Date()))_\n\n"
        for v in vendors {
            out += renderMarkdown(vendor: v, detailed: true, yearRange: yearRange)
            out += "\n\n---\n\n"
        }
        return out
    }

    // MARK: - PDF + file output

    /// Render MD → AttributedString → NSPrintOperation → PDF, mirroring the
    /// existing `ExportService.renderPDF` path so the look is consistent.
    static func renderPDF(markdown md: String, to url: URL) throws {
        let attr = (try? NSAttributedString(
            markdown: md,
            options: .init(interpretedSyntax: .full)
        )) ?? NSAttributedString(string: md)

        let pageSize = NSSize(width: 612, height: 792) // US Letter
        let inset: CGFloat = 54
        let textRect = NSRect(x: inset, y: inset,
                              width: pageSize.width - inset * 2,
                              height: pageSize.height - inset * 2)
        let textView = NSTextView(frame: textRect)
        textView.textStorage?.setAttributedString(attr)
        textView.isEditable = false

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = inset
        printInfo.bottomMargin = inset
        printInfo.leftMargin = inset
        printInfo.rightMargin = inset
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        let ok = op.run()
        if !ok {
            throw NSError(domain: "PurpleTracker.VendorExport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "PDF print operation failed"])
        }
    }

    @discardableResult
    static func exportVendor(_ vendor: Vendor, detailed: Bool, format: Format,
                             settingsStore: SettingsStore, yearRange: [Int]) throws -> URL {
        let md = renderMarkdown(vendor: vendor, detailed: detailed, yearRange: yearRange)
        let dir = settingsStore.resolvedExportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = FileStoreService.sanitize(vendor.name.isEmpty ? "vendor" : vendor.name)
        let suffix = detailed ? "full" : "summary"
        let url = dir.appendingPathComponent("Vendor-\(safe)-\(suffix).\(format.fileExtension)")
        switch format {
        case .markdown:
            try md.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try renderPDF(markdown: md, to: url)
        }
        return url
    }

    @discardableResult
    static func exportAllVendors(detailed: Bool, format: Format,
                                 vendors: [Vendor],
                                 settingsStore: SettingsStore,
                                 yearRange: [Int]) throws -> URL {
        let md = detailed
            ? renderAllVendorsDetailed(vendors, yearRange: yearRange)
            : renderAllVendorsBasic(vendors, yearRange: yearRange)
        let dir = settingsStore.resolvedExportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suffix = detailed ? "Detailed" : "Basic"
        let url = dir.appendingPathComponent("ThirdParties-\(suffix).\(format.fileExtension)")
        switch format {
        case .markdown:
            try md.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try renderPDF(markdown: md, to: url)
        }
        return url
    }

    private static func stars(_ rating: Int) -> String {
        let clamped = max(0, min(5, rating))
        return String(repeating: "★", count: clamped) +
               String(repeating: "☆", count: 5 - clamped)
    }
}

import Foundation
import GRDB

/// One row from a Clips4Sale storefront export. The export comes from C4S
/// "on demand" with 14 fixed columns; we keep one bag-of-rows table per
/// install (`c4s_historical`) and re-bind each row to the configured store
/// (`CoC` or `PoA`) at import time. Rows are wholly replaced for the
/// selected store on every import — the table is a snapshot, not a journal.
struct C4SHistoricalRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var store: String                           // "CoC" or "PoA"
    var clipStatus: String                      // e.g. "active", "p7_under_review"
    var clipId: String                          // C4S external id, e.g. "6377841"
    var trackingTag: String
    var title: String
    var descriptionText: String
    var categories: String                      // C4S returns a single comma-joined string
    var keywords: String
    var clipFilename: String
    var thumbnailFilename: String
    var previewFilename: String
    var performers: String
    var priceCents: Int?                        // "3.99" → 399
    var salesCount: Int?
    var incomeCents: Int?                       // last-6-months income, "2.39" → 239
    var importedAt: String                      // ISO timestamp of the run that wrote this row

    static let databaseTableName = "c4s_historical"

    enum CodingKeys: String, CodingKey {
        case id
        case store
        case clipStatus = "clip_status"
        case clipId = "clip_id"
        case trackingTag = "tracking_tag"
        case title
        case descriptionText = "description_text"
        case categories
        case keywords
        case clipFilename = "clip_filename"
        case thumbnailFilename = "thumbnail_filename"
        case previewFilename = "preview_filename"
        case performers
        case priceCents = "price_cents"
        case salesCount = "sales_count"
        case incomeCents = "income_cents"
        case importedAt = "imported_at"
    }

    /// Display helpers used by the grid / detail view.

    var priceDisplay: String {
        guard let c = priceCents else { return "" }
        return String(format: "$%0.2f", Double(c) / 100.0)
    }

    var incomeDisplay: String {
        guard let c = incomeCents else { return "" }
        return String(format: "$%0.2f", Double(c) / 100.0)
    }

    var salesDisplay: String {
        guard let s = salesCount else { return "" }
        return "\(s)"
    }

    var categoryList: [String] {
        categories.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var keywordList: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

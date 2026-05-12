import Foundation
import GRDB

public struct C4SHistoricalRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var store: String
    public var clipStatus: String
    public var clipId: String
    public var trackingTag: String
    public var title: String
    public var descriptionText: String
    public var categories: String
    public var keywords: String
    public var clipFilename: String
    public var thumbnailFilename: String
    public var previewFilename: String
    public var performers: String
    public var priceCents: Int?
    public var salesCount: Int?
    public var incomeCents: Int?
    public var importedAt: String

    public static let databaseTableName = "c4s_historical"

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

    public init(
        id: Int64? = nil,
        store: String,
        clipStatus: String,
        clipId: String,
        trackingTag: String,
        title: String,
        descriptionText: String,
        categories: String,
        keywords: String,
        clipFilename: String,
        thumbnailFilename: String,
        previewFilename: String,
        performers: String,
        priceCents: Int? = nil,
        salesCount: Int? = nil,
        incomeCents: Int? = nil,
        importedAt: String
    ) {
        self.id = id
        self.store = store
        self.clipStatus = clipStatus
        self.clipId = clipId
        self.trackingTag = trackingTag
        self.title = title
        self.descriptionText = descriptionText
        self.categories = categories
        self.keywords = keywords
        self.clipFilename = clipFilename
        self.thumbnailFilename = thumbnailFilename
        self.previewFilename = previewFilename
        self.performers = performers
        self.priceCents = priceCents
        self.salesCount = salesCount
        self.incomeCents = incomeCents
        self.importedAt = importedAt
    }

    public var priceDisplay: String {
        guard let c = priceCents else { return "" }
        return String(format: "$%0.2f", Double(c) / 100.0)
    }

    public var incomeDisplay: String {
        guard let c = incomeCents else { return "" }
        return String(format: "$%0.2f", Double(c) / 100.0)
    }

    public var salesDisplay: String {
        guard let s = salesCount else { return "" }
        return "\(s)"
    }

    public var categoryList: [String] {
        categories.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var keywordList: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

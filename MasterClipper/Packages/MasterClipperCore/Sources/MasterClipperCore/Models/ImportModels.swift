import Foundation

public enum ClipFieldKey: String, CaseIterable, Hashable {
    case ignore
    case externalClipId
    case trackingTag
    case personaCode
    case title
    case descriptionRaw
    case descriptionRefined
    case categories
    case keywords
    case clipFilename
    case thumbnailFilename
    case previewFilename
    case performers
    case lengthSeconds
    case priceCents
    case salesCount
    case incomeCents
    case contentDate
    case goLiveDate
    case status
    case notes

    public var label: String {
        switch self {
        case .ignore:             return "— ignore —"
        case .externalClipId:     return "External Clip ID (legacy #)"
        case .trackingTag:        return "Tracking Tag"
        case .personaCode:        return "Persona"
        case .title:              return "Title"
        case .descriptionRaw:     return "Description (raw)"
        case .descriptionRefined: return "Description (refined)"
        case .categories:         return "Categories"
        case .keywords:           return "Keywords"
        case .clipFilename:       return "Clip Filename"
        case .thumbnailFilename:  return "Thumbnail Filename"
        case .previewFilename:    return "Preview Filename"
        case .performers:         return "Performers"
        case .lengthSeconds:      return "Length"
        case .priceCents:         return "Price"
        case .salesCount:         return "Sales"
        case .incomeCents:        return "Income"
        case .contentDate:        return "Content Date"
        case .goLiveDate:         return "Go Live Date"
        case .status:             return "Status"
        case .notes:              return "Notes"
        }
    }
}

public struct ParsedClipRow: Identifiable {
    public let id = UUID()
    public var values: [ClipFieldKey: String]
    public var rawCategories: [String] = []
    public var rawKeywords: [String] = []
    public var isDuplicate: Bool = false
    public var isSelected: Bool = true
    public var sourceRowIndex: Int

    public init(
        values: [ClipFieldKey: String],
        rawCategories: [String] = [],
        rawKeywords: [String] = [],
        isDuplicate: Bool = false,
        isSelected: Bool = true,
        sourceRowIndex: Int
    ) {
        self.values = values
        self.rawCategories = rawCategories
        self.rawKeywords = rawKeywords
        self.isDuplicate = isDuplicate
        self.isSelected = isSelected
        self.sourceRowIndex = sourceRowIndex
    }
}

public struct ImportSession {
    public var sourceColumns: [String]
    public var rows: [[String]]
    public var mapping: [Int: ClipFieldKey]
    public var previewRows: [ParsedClipRow]
    public var sheetName: String?
    public var fileName: String?

    public init(
        sourceColumns: [String],
        rows: [[String]],
        mapping: [Int: ClipFieldKey],
        previewRows: [ParsedClipRow],
        sheetName: String? = nil,
        fileName: String? = nil
    ) {
        self.sourceColumns = sourceColumns
        self.rows = rows
        self.mapping = mapping
        self.previewRows = previewRows
        self.sheetName = sheetName
        self.fileName = fileName
    }
}
